#!/usr/bin/env python3
"""CEDAR's own session: the desktop shell starts with Hyprland and nothing else.

Hyprland runs `cedar_session.py start` at login. CEDAR needs Hyprland,
Quickshell and Python; it does not read a desktop theme or wait for another
shell. When Omarchy is installed its shell is a known overlap: CEDAR lets it
finish loading (stopping a Quickshell mid-incubation segfaults it), then stops
it through its own supervisor so it exits cleanly and is not relaunched.

  start      start CEDAR if it is not running; retire the Omarchy shell
  restart    restart CEDAR in place (after an update); never while locked
  reconcile  only retire an Omarchy shell that appeared beside CEDAR
  stop       stop CEDAR and give the Omarchy shell back when Omarchy is here
  status     print what is running as JSON

Stdlib only, so it runs before anything else in the session is ready.
"""
import fcntl
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

HOME = Path.home()
CONFIG = Path(os.environ.get('XDG_CONFIG_HOME') or HOME / '.config')
DATA = Path(os.environ.get('XDG_DATA_HOME') or HOME / '.local/share')
STATE = Path(os.environ.get('XDG_STATE_HOME') or HOME / '.local/state')
RUNTIME = Path(os.environ.get('XDG_RUNTIME_DIR') or '/run/user/%d' % os.getuid())
LOG = STATE / 'cedar/shell.log'
UNIT = 'cedar-shell'


def omarchy_shell():
    """Omarchy's shell config when Omarchy is installed; None everywhere else."""
    path = Path(os.environ.get('OMARCHY_PATH') or '/usr/share/omarchy') / 'shell'
    return path if (path / 'shell.qml').is_file() else None


def run(argv, timeout=6):
    try:
        return subprocess.run(argv, text=True, capture_output=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired):
        return subprocess.CompletedProcess(argv, 1, '', '')


def selector():
    """The live CEDAR is whatever owns the `cedar` profile, else the installed release."""
    if (CONFIG / 'quickshell/cedar/shell.qml').is_file():
        return ['-c', 'cedar']
    release = DATA / 'cedar/current/shell.qml'
    if release.is_file():
        return ['-p', str(release)]
    raise SystemExit('CEDAR is not installed: no ~/.config/quickshell/cedar profile and no release in ' + str(DATA / 'cedar/current'))


def instances(sel):
    result = run(['qs', 'list', '-j', *sel])
    try:
        rows = json.loads(result.stdout) if result.returncode == 0 else []
    except ValueError:
        return []
    return rows if isinstance(rows, list) else []


def is_cedar(config_path):
    """A Quickshell config that is CEDAR: the `cedar` profile (by name or by what it
    points at) or a copy in the release store, however the instance was launched."""
    path = Path(str(config_path or ''))
    if path.name != 'shell.qml':
        return False
    profile = CONFIG / 'quickshell/cedar/shell.qml'
    try:
        resolved = path.resolve()
    except (OSError, RuntimeError):
        resolved = path
    if path == profile or resolved == profile:
        return True
    try:
        if profile.exists() and resolved == profile.resolve():
            return True
    except (OSError, RuntimeError):
        pass
    return resolved.is_relative_to(DATA / 'cedar/releases')


def cedar_instances():
    """Every running CEDAR, matched by the live selector and by what each instance loads."""
    rows = {r.get('pid'): r for r in instances(selector()) if isinstance(r, dict)}
    for row in instances(['--all']):
        if isinstance(row, dict) and row.get('pid') not in rows and is_cedar(row.get('config_path')):
            rows[row.get('pid')] = row
    return list(rows.values())


def cedar_ready():
    result = run(['qs', *selector(), 'ipc', 'call', 'shell', 'isLocked'], timeout=2)
    return result.returncode == 0 and result.stdout.strip() == 'false'


def cedar_answers():
    result = run(['qs', *selector(), 'ipc', 'call', 'shell', 'isLocked'], timeout=2)
    return result.returncode == 0 and result.stdout.strip() in ('true', 'false')


def omarchy_locked():
    """True while Omarchy's own locker may hold the session. Unknown counts as locked."""
    if not shutil.which('omarchy-hyprland-session-locked'):
        return False
    return run(['omarchy-hyprland-session-locked']).returncode != 1


def wait_for(predicate, seconds, step=0.2):
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        if predicate():
            return True
        time.sleep(step)
    return predicate()


def supervisors():
    """omarchy-launch-shell processes: they relaunch the shell after any non-zero exit."""
    pids = []
    for entry in Path('/proc').iterdir():
        if not entry.name.isdigit():
            continue
        try:
            argv = (entry / 'cmdline').read_bytes().split(b'\0')
            owner = entry.stat().st_uid
        except OSError:
            continue
        if owner == os.getuid() and any(Path(a.decode(errors='replace')).name == 'omarchy-launch-shell' for a in argv[:2] if a):
            pids.append(int(entry.name))
    return pids


def retire_omarchy():
    """Stop a running Omarchy shell cleanly. Returns False when it must wait (locked, still loading)."""
    shell = omarchy_shell()
    if not shell or not instances(['-p', str(shell)]):
        return True
    if omarchy_locked():
        print('Omarchy shell left running: the session may be locked by it.', file=sys.stderr)
        return False
    # A Quickshell stopped while its QML is still incubating segfaults; wait for it to answer.
    if not wait_for(lambda: run(['qs', '-p', str(shell), 'ipc', 'call', 'shell', 'ping'], timeout=2).returncode == 0, 20, 0.5):
        print('Omarchy shell never finished loading; leaving it for the next reconcile.', file=sys.stderr)
        return False
    # TERM to the supervisor stops the shell and exits 0, so nothing relaunches it.
    for pid in supervisors():
        try:
            os.kill(pid, 15)
        except OSError:
            pass
    if not wait_for(lambda: not instances(['-p', str(shell)]), 8):
        run(['qs', 'kill', '-p', str(shell)])
        if not wait_for(lambda: not instances(['-p', str(shell)]), 8):
            print('Omarchy shell did not stop.', file=sys.stderr)
            return False
    return True


def give_back_omarchy():
    if omarchy_shell() and shutil.which('omarchy-launch-shell') and not instances(['-p', str(omarchy_shell())]):
        launch('omarchy-shell-restored', ['omarchy-launch-shell'], quickshell=False)


SESSION_KEYS = ('WAYLAND_DISPLAY', 'DISPLAY', 'PATH', 'LANG', 'LC_ALL', 'OMARCHY_PATH', 'DBUS_SESSION_BUS_ADDRESS')
SESSION_PREFIXES = ('HYPRLAND_', 'XDG_', 'QT_', 'QSG_', 'XCURSOR_', 'GTK_', 'GDK_')


def session_env():
    """Hyprland's environment for the unit. systemd-run uses the user manager's,
    which has no WAYLAND_DISPLAY at login until (if ever) something imports it."""
    keys = sorted(k for k in os.environ if k in SESSION_KEYS or k.startswith(SESSION_PREFIXES))
    return ['--setenv=' + k + '=' + os.environ[k] for k in keys if '\n' not in os.environ[k]]


def launch(unit, command, quickshell=True):
    env = session_env()
    if quickshell:
        env += ['--setenv=QSG_RENDER_LOOP=threaded', '--setenv=QSG_USE_SIMPLE_ANIMATION_DRIVER=1']
    LOG.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    if shutil.which('systemd-run'):
        # Its own cgroup: the hook or terminal that started it can exit freely.
        result = run(['systemd-run', '--user', '--collect', '--quiet', '--unit=' + unit, '--property=Restart=on-failure',
                      '--property=StandardOutput=append:' + str(LOG), '--property=StandardError=append:' + str(LOG),
                      *env, '--', *command], timeout=15)
        if result.returncode == 0:
            return True
        print(result.stderr.strip() or 'systemd-run failed', file=sys.stderr)
    # No systemd user session: a detached process is still a working desktop.
    extra = {e.split('=', 1)[0][len('--setenv='):]: e.split('=', 1)[1] for e in env}
    with LOG.open('a') as log:
        subprocess.Popen(command, env={**os.environ, **extra}, stdin=subprocess.DEVNULL, stdout=log, stderr=log, start_new_session=True)
    return True


def stop_cedar():
    if shutil.which('systemctl'):
        run(['systemctl', '--user', 'stop', UNIT + '.service'], timeout=15)
    if not wait_for(lambda: not cedar_instances(), 10):
        # A CEDAR launched another way (an older release path, a hand launch): by instance.
        for row in cedar_instances():
            run(['qs', 'kill', '--pid', str(row.get('pid'))] if row.get('pid') else ['qs', 'kill', *selector()])
        if not wait_for(lambda: not cedar_instances(), 5):
            raise SystemExit('The running CEDAR shell did not stop.')


def start_cedar():
    if shutil.which('systemctl'):
        run(['systemctl', '--user', 'reset-failed', UNIT + '.service'])
    launch(UNIT, ['qs', '-n', *selector()])
    if wait_for(cedar_answers, 30, 0.25):
        return True
    print('CEDAR did not start; see ' + str(LOG), file=sys.stderr)
    return False


def start():
    if cedar_instances():
        retire_omarchy()
        return 0
    retired = retire_omarchy()
    if start_cedar():
        return 0
    # Never leave the person without a desktop shell.
    if retired:
        give_back_omarchy()
    return 1


def restart():
    if cedar_instances():
        if not cedar_ready():
            raise SystemExit('CEDAR is locked or not answering; not restarted.')
        stop_cedar()
    return start()


def reconcile():
    if not cedar_instances():
        return 0
    return 0 if retire_omarchy() else 75  # 75: temporary, the guard retries


def stop():
    if cedar_instances():
        if cedar_answers() and not cedar_ready():
            raise SystemExit('CEDAR is locked; not stopped.')
        stop_cedar()
    give_back_omarchy()
    return 0


def status():
    shell = omarchy_shell()
    print(json.dumps({'cedar': [r.get('pid') for r in cedar_instances()], 'selector': selector(), 'ready': cedar_ready(),
                      'profile': os.readlink(CONFIG / 'quickshell/cedar') if (CONFIG / 'quickshell/cedar').is_symlink() else None,
                      'omarchy': [r.get('pid') for r in instances(['-p', str(shell)])] if shell else None}, indent=2))
    return 0


ACTIONS = {'start': start, 'restart': restart, 'reconcile': reconcile, 'stop': stop, 'status': status}


def main(argv):
    action = argv[0] if argv else 'start'
    if action not in ACTIONS:
        raise SystemExit('usage: cedar_session.py [' + '|'.join(ACTIONS) + ']')
    if action == 'status':
        return status()
    if not os.environ.get('WAYLAND_DISPLAY'):
        # The guard can fire before a session exists; there is nothing to reconcile then.
        print('No Wayland session in this environment.', file=sys.stderr)
        return 0 if action == 'reconcile' else 1
    RUNTIME.mkdir(parents=True, exist_ok=True)
    with (RUNTIME / 'cedar-session.lock').open('w') as mutex:
        fcntl.flock(mutex, fcntl.LOCK_EX)
        return ACTIONS[action]()


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
