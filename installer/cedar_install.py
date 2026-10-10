#!/usr/bin/env python3
"""CEDAR Installer entry point.

    cedar-install                 open the CEDAR Installer window (terminal flow without a display)
    cedar-install --dry-run       scan, build the plan, change nothing
    cedar-install --yes           install with the default plan without asking
    cedar-install --no-gui        the terminal flow even on a desktop
    cedar-install --resume        continue an interrupted installation
    cedar-install --start-over    discard the interrupted state and begin again
    cedar-install --restore       restore the previous system from the latest backup
    cedar-install --uninstall     undo CEDAR-owned changes; keep packages and your data
    cedar-install --repair        verify the installed copy and reinstall what does not match
    cedar-install --last-log      print the path of the most recent installer log

The window and the terminal share one engine (installer/engine). The window
is a Quickshell program, so when Quickshell is not installed yet the
terminal flow installs the dependencies first and then offers the window.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import uuid

HERE = Path(__file__).resolve().parent
SOURCE = HERE.parent
sys.path.insert(0, str(SOURCE))

from installer.engine import operations as ops  # noqa: E402
from installer.engine import plan as plan_module  # noqa: E402
from installer.engine import update as update_module  # noqa: E402
from installer.engine.host import Host  # noqa: E402
from installer.engine.server import Engine, serve  # noqa: E402


# The console as it was at startup: a step that redirects stdout into the
# log must not take the installer's own progress lines with it.
CONSOLE = sys.stdout


def say(text=''):
    print(text, file=CONSOLE, flush=True)


def ask(question, default=False):
    if not sys.stdin.isatty():
        try:
            with open('/dev/tty') as tty:
                sys.stdout.write(question + (' [Y/n] ' if default else ' [y/N] ')); sys.stdout.flush()
                reply = tty.readline().strip().lower()
        except OSError:
            return default
    else:
        reply = input(question + (' [Y/n] ' if default else ' [y/N] ')).strip().lower()
    if not reply:
        return default
    return reply in ('y', 'yes')


def update_plan(source, environ=None):
    """Where the newest CEDAR comes from: a Git checkout to pull, or the published release.

    A checkout wins when one exists (CEDAR_CHECKOUT, ~/cedar-shell, or the
    source itself when it is a checkout); otherwise the bootstrap downloads
    and verifies the latest release."""
    return update_module.locate(source, environ)


def update_arguments(argv):
    """Keep install options, never a stale source/channel or a second update loop."""
    clean = []
    values = iter(argv)
    for value in values:
        if value in ('--source', '--channel'):
            next(values, None)
        elif value in ('--update', '--updated', '--serve') or value.startswith(('--source=', '--channel=')):
            continue
        else:
            clean.append(value)
    return clean + ['--updated']


def start_updated(record, passthrough):
    """Execute the exact prepared source, with channel context understood by new installers.

    Context is passed in the environment so returning to an older main revision
    does not fail argument parsing. The selector itself requires the updater
    changes on that revision, as documented in the branch rollout notes.
    """
    installer = Path(record['source']) / 'installer/cedar_install.py'
    env = dict(os.environ)
    for key in ('CEDAR_INSTALLER_CHANNEL', 'CEDAR_INSTALLER_COMMIT', 'CEDAR_INSTALLER_SOURCE_DIGEST', 'CEDAR_INSTALLER_UPDATE_ID'):
        env.pop(key, None)
    if record.get('channel'):
        update_module.channel_branch(record['channel'])
        env.update({'CEDAR_INSTALLER_CHANNEL': record['channel'], 'CEDAR_INSTALLER_COMMIT': record['commit'],
                    'CEDAR_INSTALLER_SOURCE_DIGEST': record['sourceDigest']})
        update_module.verify_update_source(record['source'], env)
    os.execve(sys.executable, [sys.executable, str(installer), '--source', record['source'], *update_arguments(passthrough)], env)


def update(source, args, argv):
    """The update stage, then the fetched copy's installer with the same arguments.

    With a display the CEDAR Installer window opens at once and runs the
    update as its first stage: find, inspect, fetch, apply, hand off, with
    guidance instead of a traceback when something stops. When the window
    closes with a handoff recorded, this process starts the updated
    installer. In a terminal the same engine prints the same steps."""
    passthrough = update_arguments(argv)
    state_dir = Host().state_home() / 'cedar/installer'
    if wants_window(args, None):
        session_id = uuid.uuid4().hex
        code = launch_window(source, args, start='update', update_id=session_id)
        record = update_module.take_handoff(state_dir, session_id=session_id)
        if record is None:
            return code
        start_updated(record, passthrough)
    state = {'verbose': args.verbose}
    say('CEDAR update — fetching the newest CEDAR')
    say()
    channel = args.channel or os.environ.get('CEDAR_INSTALLER_CHANNEL') or update_module.installed_channel() or 'stable'
    updater = update_module.Updater(source, emit=terminal_listener(state), state_dir=state_dir, channel=channel)
    try:
        result = updater.run()
    except update_module.Guidance:
        say(); say('Nothing on your desktop was changed. The installed CEDAR keeps running.')
        return 1
    say()
    if result['current']:
        say('CEDAR is up to date on ' + result['branch'] + ' (' + result['commit'][:12] + ').')
        return 0
    say('Starting the updated installer…'); sys.stdout.flush()
    start_updated(result, passthrough)


def wants_window(args, engine):
    if args.no_gui or args.dry_run or args.uninstall or args.repair or args.restore or args.last_log or args.json:
        return False
    if args.gui:
        return True
    display = bool(os.environ.get('WAYLAND_DISPLAY') or os.environ.get('DISPLAY'))
    return display and bool(shutil.which('qs'))


def launch_window(source, args, start=None, update_id=None):
    env = {**os.environ, 'CEDAR_INSTALLER_SOURCE': str(source), 'CEDAR_INSTALLER_PYTHON': sys.executable,
           'QS_DISABLE_FILE_WATCHER': '1', 'CEDAR_INSTALLER': '1'}
    if args.channel: env['CEDAR_INSTALLER_CHANNEL'] = args.channel
    if update_id: env['CEDAR_INSTALLER_UPDATE_ID'] = update_id
    if args.updated: env['CEDAR_INSTALLER_UPDATE'] = '1'; env['CEDAR_INSTALLER_START'] = 'updated'
    if args.resume: env['CEDAR_INSTALLER_START'] = 'resume'
    if args.start_over: env['CEDAR_INSTALLER_START'] = 'start-over'
    if start: env['CEDAR_INSTALLER_START'] = start
    result = subprocess.run(['qs', '-p', str(source / 'installer.qml')], env=env)
    return result.returncode


def terminal_listener(state):
    def emit(event, data):
        if event == 'operation':
            marks = {'pending': '○', 'running': '◌', 'complete': '✓', 'warning': '!', 'failed': '×', 'skipped': '–'}
            line = '  ' + marks.get(data['state'], '○') + ' ' + data['title']
            if data.get('detail') and data['state'] != 'pending':
                line += '  ·  ' + data['detail']
            key = (data['id'], data['state'], data.get('detail'))
            if key != state.get('last'):
                say(line); state['last'] = key
        elif event == 'password':
            say('  ' + data['text'])
        elif event == 'log' and state.get('verbose'):
            say('      ' + data['line'])
        elif event == 'update-error':
            say()
            say('Update stopped: ' + data.get('title', ''))
            say('  ' + data.get('message', ''))
            for number, step in enumerate(data.get('steps', []), 1):
                say('  ' + str(number) + '. ' + step)
            for note in data.get('notes', []):
                say('  · ' + note)
            if data.get('log'): say('  Log: ' + data['log'])
    return emit


def main(argv=None):
    parser = argparse.ArgumentParser(prog='cedar-install', description='Install, resume, restore, repair or uninstall CEDAR.')
    parser.add_argument('--dry-run', action='store_true', help='scan and build the plan without changing anything')
    parser.add_argument('--yes', '-y', action='store_true', help='apply the default plan without asking')
    parser.add_argument('--no-gui', action='store_true', help='use the terminal flow')
    parser.add_argument('--gui', action='store_true', help='force the window even when a display was not detected')
    parser.add_argument('--resume', action='store_true', help='continue an interrupted installation')
    parser.add_argument('--start-over', action='store_true', help='discard the interrupted installation state and begin again')
    parser.add_argument('--restore', action='store_true', help='restore the previous system from the latest backup')
    parser.add_argument('--uninstall', action='store_true', help='undo CEDAR-owned changes; keep packages and your data')
    parser.add_argument('--repair', action='store_true', help='verify the installed copy and reinstall what does not match')
    parser.add_argument('--last-log', action='store_true', help='print the path of the most recent installer log')
    parser.add_argument('--update', action='store_true', help='check the selected branch in an isolated cache and run its installer')
    parser.add_argument('--channel', choices=tuple(update_module.CHANNELS), help='update from stable (main) or development (dev)')
    parser.add_argument('--updated', action='store_true', help=argparse.SUPPRESS)
    parser.add_argument('--json', action='store_true', help='print facts and plan as JSON (with --dry-run)')
    parser.add_argument('--verbose', '-v', action='store_true', help='print the technical log while installing')
    parser.add_argument('--no-session', action='store_true', help='install without starting CEDAR in this session')
    parser.add_argument('--cedar-launcher', action='store_true', help='also point the application-launcher shortcut at CEDAR Go')
    parser.add_argument('--trailwatch', action='store_true', help='also select CEDAR Trailwatch as the locker, with its password and lock tests')
    parser.add_argument('--fonts', action='store_true', help='also install the recommended fonts')
    parser.add_argument('--keybinds', dest='keybinds', action='store_true', default=None, help='install CEDAR’s keybinds (Caelestia layout) into the Hyprland configuration')
    parser.add_argument('--no-keybinds', dest='keybinds', action='store_false', help='leave the Hyprland keybinds untouched')
    parser.add_argument('--source', type=Path, default=SOURCE, help=argparse.SUPPRESS)
    parser.add_argument('--serve', action='store_true', help=argparse.SUPPRESS)
    parser.add_argument('--version', action='store_true', help='print the installer version')
    args = parser.parse_args(argv)
    source = args.source.resolve()
    if args.channel and not args.update:
        parser.error('--channel must be used with --update')
    if args.channel:
        os.environ['CEDAR_INSTALLER_CHANNEL'] = args.channel
    if args.version:
        say('cedar-install ' + ((source / 'VERSION').read_text().strip() if (source / 'VERSION').is_file() else 'unknown')); return 0
    if os.getuid() == 0:
        say('CEDAR installs into your own home directory. Run the installer as your ordinary user, never root.'); return 1
    if sys.version_info < (3, 11):
        say('CEDAR needs Python 3.11 or newer. Update Python with your package manager first.'); return 1
    if args.serve:
        serve(source); return 0
    if args.update:
        return update(source, args, argv if argv is not None else sys.argv[1:])

    engine = Engine(source)
    if args.last_log:
        path = engine.last_log()
        say(str(path) if path else 'No installer log yet.'); return 0 if path else 1
    if wants_window(args, engine):
        return launch_window(source, args)

    state = {'verbose': args.verbose}
    engine.emit = terminal_listener(state)
    say('CEDAR Installer ' + ((source / 'VERSION').read_text().strip() if (source / 'VERSION').is_file() else '') + ' — A living desktop environment for Hyprland.')
    say()
    if args.uninstall:
        report = engine.uninstall(dry_run=args.dry_run)
        say(json.dumps(report, indent=2)); return 0
    if args.restore:
        report = engine.restore(dry_run=args.dry_run)
        say(json.dumps(report, indent=2)); return 0
    if args.repair:
        say('Checking the installed copy…'); report = engine.repair(); say(json.dumps(report, indent=2)); return 0

    say('Scanning your system…')
    facts = engine.scan()
    env = facts['environment']
    say('  ' + facts['distro']['name'] + ' · ' + facts['architecture'] + ' · ' + (facts['compositor']['name'] or 'no compositor') + (' ' + facts['hyprlandVersion'] if facts['hyprlandVersion'] else ''))
    say('  Existing environment: ' + env['name'] + ('  (' + ', '.join(env.get('evidence', [])) + ')' if env.get('evidence') else ''))
    if facts['existingCedar']['installed']:
        say('  CEDAR ' + (facts['existingCedar']['version'] or '?') + ' is already installed; this run updates it' + (' and hands the desktop back while it does.' if facts['existingCedar']['session'] != 'not active' else '.'))
    previous = facts.get('previousInstall')
    if previous and not (args.resume or args.start_over):
        say()
        say('Previous installation interrupted: CEDAR completed ' + str(previous['completed']) + ' of ' + str(previous['total']) + ' stages.')
        say('  --resume to continue, --start-over to begin again, --restore to put the previous system back.')
        if not args.yes:
            return 3
        args.resume = True
    options = {'launcher': args.cedar_launcher, 'trailwatch': args.trailwatch, 'fonts': args.fonts}
    if args.keybinds is not None:
        options['keybinds'] = args.keybinds
    if args.no_session:
        options['session'] = False
    plan = engine.build_plan(options)
    say()
    say(plan_module.render(plan))
    if args.json:
        say(json.dumps({'facts': engine.public_facts(), 'plan': plan}, indent=2))
    if args.dry_run:
        say(); say('Dry run: nothing was changed.'); return 0 if not plan['blocked'] else 2
    if plan['blocked']:
        say(); say('CEDAR needs attention before installation (see above). Nothing was changed.'); return 2
    say()
    if args.resume:
        say('Resuming the interrupted installation.')
    elif not args.yes and not ask('Install CEDAR with this plan?'):
        say('Canceled. Nothing was changed.'); return 1
    say()
    say('Installing CEDAR')
    result = engine.resume() if args.resume else engine.install(plan['options'], plan['digest'])
    say()
    if not result.get('ok'):
        say('Installation stopped at ' + result.get('title', '?') + ': ' + result.get('message', ''))
        say('  ' + result.get('preserved', ''))
        if result.get('changedBefore'): say('  Completed before the failure: ' + ', '.join(result['changedBefore']))
        say('  Rollback of the failed step: ' + ('done' if result.get('rolledBack') else 'nothing to roll back'))
        say('  Resume with --resume' + (' or restore with --restore.' if result.get('backup') else '.'))
        say('  Log: ' + result.get('log', ''))
        return 1
    say('CEDAR IS READY')
    if result.get('imports'): say('  Imported: ' + ', '.join(result['imports']))
    say('  Backup: ' + result.get('backup', ''))
    say('  Log: ' + result.get('log', ''))
    if result.get('sessionState') == 'kept':
        say('  CEDAR is running and will start at login. cedar restore returns your previous desktop.')
    else:
        say('  Start CEDAR when you are ready: "$HOME/.local/bin/cedar" try, then cedar keep. Or open the isolated preview: cedar preview.')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print('\nCEDAR: canceled.', file=sys.stderr); sys.exit(130)
