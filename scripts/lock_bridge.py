#!/usr/bin/env python3
"""Translate Omarchy's lock IPC to the active native CEDAR locker.

This is an on-demand adapter, not a lock owner or a sleep inhibitor. The existing
Omarchy sleep monitor retains its overall deadline and warning behavior. Never
use a cached heartbeat or the UI's requested-lock flag as evidence of coverage.
"""
import json
import os
from pathlib import Path
import re
import selectors
import shutil
import subprocess
import sys
import time


MAX_OUTPUT = 32768
METHODS = {'lock', 'status', 'isLocked'}
IPC_ERRORS = ('Target not found.', 'Function not found.', 'Too few arguments provided',
              'Too many arguments provided', 'Not ready to accept queries yet')


class Unavailable(RuntimeError):
    pass


class InvalidState(RuntimeError):
    pass


def timeout_seconds(value):
    match = re.fullmatch(r'(\d+(?:\.\d*)?|\.\d+)(ms|s)?', str(value))
    if not match:
        return 2.0
    seconds = float(match[1]) / (1000 if match[2] == 'ms' else 1)
    return min(seconds, 2.0) if seconds > 0 else 2.0


def clean_environment(environ):
    env = dict(environ)
    for key in ('CEDAR_SHELL_PATH', 'CEDAR_QS_BIN', 'QS_CONFIG_PATH', 'QS_CONFIG_NAME', 'QS_MANIFEST'):
        env.pop(key, None)
    entries = []
    for entry in env.get('PATH', os.defpath).split(os.pathsep):
        if not entry:
            continue
        path = Path(entry).resolve()
        if ((path.name in ('shim', 'lock-shim') and path.parent.name == 'scripts')
                or path == Path(__file__).resolve().parent / 'lock-shim'):
            continue
        entries.append(entry)
    env['PATH'] = os.pathsep.join(entries)
    # Match the stock command's display recovery for user services started
    # before the compositor imported its environment. Never use --any-display.
    if not env.get('WAYLAND_DISPLAY'):
        runtime = Path(env.get('XDG_RUNTIME_DIR') or '/run/user/%d' % os.getuid())
        try:
            sockets = [p for p in runtime.glob('wayland-[0-9]*') if p.is_socket()]
            if sockets:
                env['WAYLAND_DISPLAY'] = max(sockets, key=lambda p: p.stat().st_mtime).name
        except OSError:
            pass
    return env


def bounded_command(argv, deadline, env):
    """Read at most MAX_OUTPUT bytes from a direct qs process before deadline.

    Do not detach its process group: the sleep monitor's outer timeout must
    still own and terminate the IPC client if it expires first. Only direct qs
    calls use this runner; it never launches an interactive shell or a daemon.
    """
    if time.monotonic() >= deadline:
        raise Unavailable('Lock IPC deadline expired.')
    try:
        process = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                   stderr=subprocess.DEVNULL, env=env)
    except OSError as exc:
        raise Unavailable('Lock IPC client is unavailable.') from exc
    output = bytearray()
    try:
        with selectors.DefaultSelector() as selector:
            selector.register(process.stdout, selectors.EVENT_READ)
            while selector.get_map():
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise Unavailable('Lock IPC deadline expired.')
                for key, _ in selector.select(remaining):
                    chunk = os.read(key.fileobj.fileno(), min(8192, MAX_OUTPUT + 1 - len(output)))
                    if not chunk:
                        selector.unregister(key.fileobj)
                    else:
                        output.extend(chunk)
                        if len(output) > MAX_OUTPUT:
                            raise InvalidState('Lock IPC response exceeded its size limit.')
            try:
                code = process.wait(timeout=max(0, deadline - time.monotonic()))
            except subprocess.TimeoutExpired as exc:
                raise Unavailable('Lock IPC deadline expired.') from exc
        if code:
            raise Unavailable('Lock IPC client could not reach its shell.')
        try:
            value = output.decode('utf-8').strip()
        except UnicodeDecodeError as exc:
            raise InvalidState('Lock IPC response was not valid text.') from exc
        if value.startswith(IPC_ERRORS):
            raise Unavailable('The shell does not provide the requested lock IPC.')
        return value
    finally:
        if process.poll() is None:
            process.kill()
        process.wait()
        process.stdout.close()


def document(value):
    try:
        data = json.loads(value)
    except (ValueError, TypeError) as exc:
        raise InvalidState('The shell returned malformed lock state.') from exc
    if not isinstance(data, dict):
        raise InvalidState('The shell returned malformed lock state.')
    return data


def booleans(data, keys):
    if any(type(data.get(key)) is not bool for key in keys):
        raise InvalidState('The shell returned incomplete or ambiguous lock state.')


def cedar_status(data):
    booleans(data, ('externalLock', 'lockReady', 'locked', 'lockSecure'))
    if type(data.get('stage')) is not int or data['stage'] not in (1, 2, 3):
        raise InvalidState('The shell returned an invalid runtime stage.')
    if type(data.get('screenCount')) is not int or data['screenCount'] < 0:
        raise InvalidState('The shell returned an invalid screen count.')
    if data['lockSecure'] and not data['locked']:
        raise InvalidState('The shell returned inconsistent lock state.')
    if data['externalLock']:
        return None
    ready = data['lockReady'] and data['stage'] == 3
    secure = data['lockSecure'] and ready
    requested = data['locked']
    return {'locked': requested, 'requested': requested, 'pending': requested and not secure,
            # sessionInfo does not expose WlSessionLock.locked. Only a secure
            # compositor acknowledgement proves that a session lock is held.
            'sessionLocked': secure, 'secure': secure, 'realScreens': data['screenCount'],
            # Native readiness means the component exists, not a PAM probe.
            'ready': ready, 'provider': 'cedar'}


def stock_status(data):
    booleans(data, ('locked', 'requested', 'secure', 'sessionLocked', 'passwordPam'))
    if data['secure'] and not data['locked']:
        raise InvalidState('Omarchy returned inconsistent lock state.')
    return data


class Bridge:
    """The runner and clock are internal fixture seams, never IPC inputs."""
    def __init__(self, qs, omarchy, env, duration, runner=bounded_command, clock=time.monotonic):
        self.qs, self.omarchy, self.env = qs, Path(omarchy), env
        self.runner, self.clock = runner, clock
        self.deadline = clock() + duration

    def portion(self, fraction):
        now = self.clock()
        return now + max(0, self.deadline - now) * fraction

    def run(self, args, deadline=None):
        return self.runner([self.qs, *args], min(deadline or self.deadline, self.deadline), self.env)

    def instance(self, selector, deadline):
        value = self.run(['list', '-j', *selector], deadline)
        if value.startswith('No running instances'):
            return None
        try:
            rows = json.loads(value)
        except ValueError as exc:
            raise InvalidState('The shell inventory was unreadable.') from exc
        if not isinstance(rows, list) or len(rows) > 1:
            raise InvalidState('The lock owner is ambiguous.')
        if not rows:
            return None
        ident = rows[0].get('id') if isinstance(rows[0], dict) else None
        if not isinstance(ident, str) or not re.fullmatch(r'[A-Za-z0-9]+', ident):
            raise InvalidState('The shell inventory contains an invalid identity.')
        return ident

    def ipc(self, ident, target, method, deadline=None):
        return self.run(['ipc', '--id', ident, 'call', '--', target, method], deadline)

    def answer(self, method, status, ident, cedar=False):
        if method == 'status':
            return json.dumps(status, separators=(',', ':'))
        if method == 'isLocked':
            return 'true' if status['locked'] or status['secure'] else 'false'
        if status['secure']:
            return 'ok'
        if not status['ready' if cedar else 'passwordPam']:
            return 'failed' if cedar else 'missing-pam'
        if status['requested']:
            return 'ok'
        reply = self.ipc(ident, 'lock', 'lock')
        if reply not in (('', 'ok') if cedar else ('ok', 'missing-pam', 'failed')):
            raise InvalidState('The shell did not acknowledge the lock request.')
        return 'ok' if cedar else reply

    def call(self, method):
        # Inventory distinguishes a stopped host from an unresponsive boot
        # locker. Never start a competing locker when the host state is unknown.
        stock_deadline = self.portion(.35)
        stock_id = self.instance(['-p', str(self.omarchy / 'shell')], stock_deadline)
        stock = None
        if stock_id:
            stock = stock_status(document(self.ipc(stock_id, 'lock', 'status', stock_deadline)))
            if stock['secure'] or stock['requested'] or stock['locked'] or stock['sessionLocked']:
                return self.answer(method, stock, stock_id)

        cedar_deadline = self.portion(.75)
        ident = self.instance(['-c', 'cedar'], cedar_deadline)
        # A known CEDAR instance with unreadable state could already own a lock.
        # Only proven absence or explicit external ownership permits fallback.
        native = cedar_status(document(self.ipc(ident, 'shell', 'sessionInfo', cedar_deadline))) if ident else None
        if native is not None:
            return self.answer(method, native, ident, cedar=True)
        if stock is not None:
            return self.answer(method, stock, stock_id)
        raise Unavailable('No available shell can confirm or request a secure session lock.')


def main(argv=None):
    original = list(sys.argv[1:] if argv is None else argv)
    quiet = bool(original and original[0] == '-q')
    args = original[1:] if quiet else original
    env = clean_environment(os.environ)
    omarchy = Path(env.get('OMARCHY_PATH') or '/usr/share/omarchy')
    env['OMARCHY_PATH'] = str(omarchy)
    if len(args) != 2 or args[0] != 'lock' or args[1] not in METHODS:
        real = str(omarchy / 'bin/omarchy-shell')
        os.execve(real, [real, *original], env)
    try:
        qs = shutil.which('qs', path=env['PATH'])
        if not qs:
            raise Unavailable('Quickshell IPC is unavailable.')
        response = Bridge(qs, omarchy, env, timeout_seconds(env.get('OMARCHY_SHELL_IPC_TIMEOUT', '2s'))).call(args[1])
        if not quiet:
            print(response)
        return 0
    except (Unavailable, InvalidState) as exc:
        if not quiet:
            print('cedar-lock-bridge: ' + str(exc), file=sys.stderr)
        return 0 if quiet else 1


if __name__ == '__main__':
    sys.exit(main())
