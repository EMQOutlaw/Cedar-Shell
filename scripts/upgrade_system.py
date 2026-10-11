#!/usr/bin/env python3
"""Interactive Topgrade entry point for the Signals hub."""
import fcntl
import os
from pathlib import Path
import shutil
import subprocess
import sys

from desktop_runtime import omarchy


def upgrade():
    topgrade = shutil.which('topgrade')
    if not topgrade:
        if omarchy():
            installer = ['omarchy', 'pkg', 'aur', 'add', 'topgrade-bin']
        else:
            helper = next((name for name in ('yay', 'paru') if shutil.which(name)), None)
            installer = [helper, '-S', '--needed', 'topgrade-bin'] if helper else None
        if not installer:
            print('Install Topgrade from https://github.com/topgrade-rs/topgrade, then try again.')
            return 1
        if input('Topgrade is not installed. Install it now? [Y/n] ').strip().lower() not in ('', 'y', 'yes'):
            print('Upgrade cancelled.')
            return 0
        result = subprocess.run(installer, cwd=Path.home())
        if result.returncode:
            print('Topgrade installation failed. No upgrade was started.')
            return result.returncode
        topgrade = shutil.which('topgrade')
        if not topgrade:
            print('Topgrade is still unavailable. Check the installation output above.')
            return 1
    print('Starting Topgrade. Follow its prompts to upgrade your installed tools and packages.', flush=True)
    result = subprocess.run([topgrade], cwd=Path.home())
    print('\nTopgrade finished.' if result.returncode == 0 else f'\nTopgrade exited with status {result.returncode}. Review the results above.')
    return result.returncode


def main():
    if not sys.stdin.isatty():
        print('Open Upgrade system from Signals, or run this command in a terminal.', file=sys.stderr)
        return 1
    state = Path(os.environ.get('XDG_STATE_HOME') or Path.home() / '.local/state') / 'cedar'
    state.mkdir(parents=True, exist_ok=True)
    with (state / 'topgrade.lock').open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print('A system upgrade is already open. Use its terminal to continue.')
            input('Press Enter to close.')
            return 0
        try:
            code = upgrade()
        except KeyboardInterrupt:
            print('\nUpgrade interrupted.')
            code = 130
        except (OSError, EOFError) as error:
            print(f'Could not complete the upgrade: {error}')
            code = 1
        try:
            input('\nPress Enter to close.')
        except (EOFError, KeyboardInterrupt):
            pass
        return code


if __name__ == '__main__':
    raise SystemExit(main())
