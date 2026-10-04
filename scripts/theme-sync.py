#!/usr/bin/env python3
"""Theme-scoped shell handoff for this machine's Omarchy installation.
Called by theme-set and post-boot hooks. Never changes global desktop files.
"""
import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys
import time

HOME_DIR = Path.home()
CONFIG = Path(os.environ.get('XDG_CONFIG_HOME', str(HOME_DIR/'.config')))
STATE = Path(os.environ.get('XDG_STATE_HOME', HOME_DIR/'.local/state'))/'omarchy/current/theme.name'
RUNTIME = Path(os.environ.get('XDG_RUNTIME_DIR', f'/run/user/{os.getuid()}'))
OMARCHY = Path(os.environ.get('OMARCHY_PATH', '/usr/share/omarchy'))/'shell'
LOG_DIR = Path(os.environ.get('XDG_STATE_HOME', str(HOME_DIR/'.local/state')))/'cedar'


def run(args, timeout=6):
    try:
        return subprocess.run(args, text=True, capture_output=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired):
        return subprocess.CompletedProcess(args, 1, '', '')


def selected():
    try: return STATE.read_text().strip().lower()
    except OSError: return ''


def instances(selector):
    result = run(['qs', 'list', '-j', *selector])
    try: return json.loads(result.stdout) if result.returncode == 0 else []
    except ValueError: return []


def locked():
    # Refuse on unknown compositor state: do not tear down any live locker.
    state = run(['omarchy-hyprland-session-locked'])
    if state.returncode != 1: return True
    for selector,target in [(['-c','cedar'], 'shell'), (['-p',str(OMARCHY)], 'lock')]:
        if instances(selector):
            result = run(['qs', *selector, 'ipc', 'call', target, 'isLocked'])
            if result.returncode != 0 or result.stdout.strip() != 'false': return True
    return False


def launch_service(unit, command, logfile):
    # Independent cgroup: neither theme picker exit nor hook completion may kill it.
    result = run(['systemd-run', '--user', '--collect', '--quiet', '--unit=' + unit,
                  '--property=Restart=on-failure',
                  '--property=StandardOutput=append:' + str(LOG_DIR/logfile),
                  '--property=StandardError=append:' + str(LOG_DIR/logfile),
                  *(['--setenv=QSG_RENDER_LOOP=threaded', '--setenv=QSG_USE_SIMPLE_ANIMATION_DRIVER=1'] if unit == 'cedar-shell' else []),
                  '--', *command])
    if result.returncode:
        print(result.stderr or 'Could not launch ' + unit, file=sys.stderr)
    return result.returncode == 0


def start_omarchy():
    if instances(['-p', str(OMARCHY)]): return
    launch_service('cedar-normal-shell', ['omarchy-launch-shell'], 'normal-shell.log')


def wait_for(predicate, seconds=8):
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        if predicate(): return True
        time.sleep(.15)
    return False


def sync(reconcile_only=False):
    LOG_DIR.mkdir(parents=True, exist_ok=True, mode=0o700)
    LOG_DIR.chmod(0o700)
    if not os.environ.get('WAYLAND_DISPLAY'): return 0
    with (RUNTIME/'cedar-theme.lock').open('w') as mutex:
        fcntl.flock(mutex, fcntl.LOCK_EX)
        # The launch guard only removes a known overlap. It never starts a shell
        # or interferes with an intentional switch to another theme.
        if reconcile_only and (selected() != 'cedar' or not instances(['-c', 'cedar']) or not instances(['-p', str(OMARCHY)])):
            return 0
        if locked():
            if reconcile_only:
                print('Shell overlap cleanup deferred until the session is unlocked.', file=sys.stderr)
                return 75  # The guard service retries; never tear down a locker.
            # Hook returns promptly; one detached worker retries after unlock.
            if '--deferred' not in sys.argv:
                # A child of the short-lived hook would be killed with its
                # systemd cgroup. Give the deferred worker its own unit instead.
                return 0 if launch_service('cedar-deferred-theme',
                    [sys.executable, str(Path(__file__).resolve()), '--deferred'], 'theme.log') else 1
            while locked():
                if run(['hyprctl','-j','monitors']).returncode != 0: return 1
                time.sleep(1)
        name = selected()  # Re-read after acquiring the lock; ignore stale hook arguments.
        if reconcile_only and name != 'cedar': return 0
        fox = ['-c', 'cedar']
        normal = ['-p', str(OMARCHY)]
        if name != 'cedar':
            (LOG_DIR/'previous-theme').write_text(name)
            if instances(fox):
                run(['qs', *fox, 'ipc', 'call', 'shell', 'stop'])
                if not wait_for(lambda: not instances(fox)):
                    print('CEDAR did not stop; preserving the live shell.', file=sys.stderr)
                    return 1
            start_omarchy()
            return 0
        # Stop only the known Omarchy config, never arbitrary bars/daemons.
        had_normal = bool(instances(normal))
        if had_normal:
            result = run(['qs', 'kill', *normal])
            # Quickshell may still list the terminating instance briefly, and
            # kill's exit status alone is not evidence that a shell is alive.
            if not wait_for(lambda: not instances(normal), seconds=10):
                print('Normal shell has not exited; aborting handoff: ' + result.stderr, file=sys.stderr)
                return 1
        # Reconcile even when CEDAR was already running.
        if instances(fox): return 0
        if reconcile_only: return 0
        launch_service('cedar-shell', ['qs', '-n', '-c', 'cedar'], 'shell.log')
        def ready():
            result = run(['qs', *fox, 'ipc', 'call', 'shell', 'isLocked'], timeout=1)
            return result.returncode == 0 and result.stdout.strip() == 'false'
        if wait_for(ready): return 0
        print('CEDAR failed to start; restoring the normal shell.', file=sys.stderr)
        if had_normal: start_omarchy()
        previous = LOG_DIR/'previous-theme'
        if previous.exists() and previous.read_text().strip() not in ('', 'cedar'):
            with (LOG_DIR/'theme.log').open('a') as log:
                subprocess.Popen(['omarchy','theme','set',previous.read_text().strip()], stdout=log, stderr=log, start_new_session=True)
        return 1


if __name__ == '__main__':
    raise SystemExit(sync(reconcile_only='--reconcile-only' in sys.argv))
