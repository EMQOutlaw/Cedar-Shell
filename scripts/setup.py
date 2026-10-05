#!/usr/bin/env python3
"""Beginner entry point; package approval and desktop activation stay separate."""
import sys
from pathlib import Path
import distribution as d


def request(value):
    """Settings frontend uses the same planner, gates and recovery executor."""
    import contextlib,io
    backend=d.session_backend()
    action=value.get('action')
    if action=='status':
        if backend.__name__=='portable_session':return backend.status_report()
        row=backend.read_record()
        return {key:row.get(key) for key in ('stage','login','deadline','error','locker')} if row else {'stage':'not active'}
    if backend.__name__!='portable_session' and action in ('plan','try'):
        raise d.Refused('This existing Omarchy integration keeps its reviewed terminal flow. Run cedar try in a terminal; no provider was changed here.')
    launcher=value.get('launcher') is True
    trailwatch=value.get('trailwatch') is True
    if action=='activation-plan':
        if backend.__name__!='portable_session':raise d.Refused('Use the existing Omarchy terminal activation flow.')
        with backend.guard():
            row=backend.read_record()
            if not row or row['stage']!='kept':raise d.Refused('Keep a healthy trial before reviewing login activation.')
            backend.unlocked(row);backend.healthy(row)
            path,content=backend.startup_entry(row)
            digest=backend.adoption_plan.fingerprint({'path':str(path),'before':d.info(path),'content':content.decode()})
            return {'digest':digest,'path':str(path),'change':'Add the owned CEDAR startup block; preserve all other startup commands.','undo':'cedar restore'}
    if action=='plan':
        with backend.guard():
            _,plan=backend.inspect_plan(d.installed(),launcher,trailwatch)
        return {'digest':plan['digest'],'roles':plan['roles'],'mode':plan['mode'],
                'changes':[op['kind'] for op in plan['operations']],
                'recovery':'Independent recovery supervisor; an unconfirmed trial restores the prior unlocked desktop.'}
    if value.get('approved') is not True:raise d.Refused('Review and explicitly approve this operation first.')
    # Do not forward helper chatter, file paths, or authentication output to a
    # generic GUI log. Failures remain clear structured errors.
    with contextlib.redirect_stdout(io.StringIO()):
        if action=='try':
            if not value.get('digest'):raise d.Refused('Review a desktop plan first.')
            backend.trial(d.installed(),approved=True,cedar_launcher=launcher,trailwatch=trailwatch,expected_plan=value['digest'])
        elif action=='keep':backend.keep()
        elif action=='activate':
            if not value.get('loginDigest'):raise d.Refused('Review the login change before confirming.')
            backend.keep(login=True,approved=True,expected_login_digest=value['loginDigest'])
        elif action=='restore':backend.request_restore()
        else:raise d.Refused('Unknown setup action.')
    return request({'action':'status'})


def main(args=None):
    args = list(sys.argv[1:] if args is None else args)
    root = Path(__file__).resolve().parents[1]
    if d.os.getuid() == 0:
        raise d.Refused('Run bash ./install.sh as your ordinary user, never root.')
    if sys.version_info < (3, 11):
        raise d.Refused('CEDAR needs Python 3.11 or newer. Update Python using your distribution package manager first.')
    if args==['--request']:
        import json
        try: print(json.dumps({'ok':True,'data':request(json.loads(sys.stdin.readline(65537)))}))
        except (d.Refused,OSError,ValueError,d.subprocess.SubprocessError) as error: print(json.dumps({'ok':False,'error':str(error)}))
        return
    if args or not sys.stdin.isatty():
        # Explicit automation retains narrow, existing install-only semantics.
        return d.main(['install', *args])
    print('CEDAR '+(root/'VERSION').read_text().strip()+' — A living desktop environment for Hyprland.\n')
    print('This updates the installed cedar command only after installation succeeds. If canceled, your previous installation stays selected.')
    print('[1/6] Checking your system')
    if not d.shutil.which('hyprctl'):
        raise d.Refused('Install and start Hyprland before using CEDAR. This installer does not replace your compositor or login manager.')
    print('[2/6] Checking required software')
    for font in d.capabilities(root):
        if font['scope'] == 'font' and font['status'] != 'Ready':
            print('Recommended font unavailable: '+font['id']+'. Using its readable fallback; installation can continue.')
    packages = d.package_plan(root)
    if packages['packages']:
        print('On '+packages['distribution']+', this installs the listed packages and performs a full system upgrade.')
        print('Review pacman\'s transaction before confirming. No additional repositories or replacement desktop providers are added.')
        reply = input('Install these packages and perform that upgrade? [y/N] ').strip().lower()
        if reply not in ('y', 'yes'):
            raise d.Refused('Canceled. Your desktop was not changed. Use --approve-install-only to deliberately copy files without preparing dependencies.')
        d.install_packages(packages, approve_upgrade=True)
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
        if backend.__name__ == 'portable_session':
            launcher = input('Use CEDAR Go for the application-launcher shortcut? [Y/n] ').strip().lower() not in ('n', 'no')
            print('Trailwatch can replace native Noctalia\'s lockscreen after a local password test and one real lock/unlock test. Its existing idle timings are preserved; sleep/lid locking uses a private hypridle bridge.')
            trailwatch = input('Use CEDAR Trailwatch for locking? [y/N] ').strip().lower() in ('y', 'yes')
            backend.trial(d.installed(), cedar_launcher=launcher, trailwatch=trailwatch)
        else:
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
