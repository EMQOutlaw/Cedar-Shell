#!/usr/bin/env python3
"""Beginner entry point; package approval and desktop activation stay separate."""
import sys
from pathlib import Path
import distribution as d


def main(args=None):
    args = list(sys.argv[1:] if args is None else args)
    root = Path(__file__).resolve().parents[1]
    if d.os.getuid() == 0:
        raise d.Refused('Run bash ./install.sh as your ordinary user, never root.')
    if sys.version_info < (3, 11):
        raise d.Refused('CEDAR needs Python 3.11 or newer. Update Python using your distribution package manager first.')
    if args or not sys.stdin.isatty():
        # Explicit automation retains narrow, existing install-only semantics.
        return d.main(['install', *args])
    print('CEDAR — A living desktop environment for Hyprland.\n')
    print('[1/6] Checking your system')
    if not d.shutil.which('hyprctl'):
        raise d.Refused('Install and start Hyprland before using CEDAR. This installer does not replace your compositor or login manager.')
    print('[2/6] Checking required software')
    packages = d.missing_packages(root)
    if packages:
        print('Missing software from the CEDAR dependency manifest: ' + ', '.join(packages))
        print('On Arch, installing these uses sudo pacman -Syu --needed and includes a full system upgrade.')
        print('No repository, compositor, driver, network or audio provider will be added or replaced.')
        reply = input('Install these packages and perform that upgrade? [y/N] ').strip().lower()
        if reply not in ('y', 'yes'):
            raise d.Refused('Canceled. Your desktop was not changed. Use --approve-install-only to deliberately copy files without preparing dependencies.')
        d.package_plan(root, True, True)
    print('[3/6] Preparing verified backups')
    plan = d.plan_install(root)
    d.approve(plan)
    print('[4/6] Installing CEDAR')
    d.install(root, approved=True)
    print('[5/6] Checking desktop integration')
    print('Your existing desktop is still running. Choose what happens next:')
    print('  1  Install only (default)\n  2  Open an isolated preview\n  3  Try the full CEDAR desktop with automatic recovery')
    choice = input('Choice [1]: ').strip() or '1'
    if choice == '2':
        d.preview(d.installed())
    elif choice == '3':
        backend = d.session_backend()
        backend.trial(d.installed())
        print('Review CEDAR on your screen. If the trial times out, your prior desktop returns.')
        if input('Keep this CEDAR session? [y/N] ').strip().lower() in ('y', 'yes'):
            backend.keep()
            if input('Also prepare CEDAR to start at login? [y/N] ').strip().lower() in ('y', 'yes'):
                backend.keep(login=True)
        else:
            backend.request_restore()
    elif choice != '1':
        raise d.Refused('Unknown choice. Files remain installed; desktop activation was not requested.')
    print('[6/6] Setup finished. Use cedar doctor for local health or cedar restore to undo desktop integration.')


if __name__ == '__main__':
    try:
        main()
    except (d.Refused, OSError, ValueError, d.subprocess.SubprocessError, KeyboardInterrupt, EOFError) as error:
        print('CEDAR: ' + (str(error) or 'Canceled; no further actions performed.'), file=sys.stderr)
        sys.exit(1)
