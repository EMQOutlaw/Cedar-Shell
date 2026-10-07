#!/usr/bin/env python3
"""Update a Git checkout of CEDAR and reinstall it from a terminal.

Runs the documented update, one visible step at a time:

    git pull --ff-only                 in the checkout
    cedar restore                      only while a CEDAR desktop session is active
    bash ./install.sh                  the ordinary interactive installer

The pull comes first so a refused pull changes nothing on the desktop. Git
decides whether local edits or divergent history block the update; nothing
here resets, stashes or deletes the checkout. The installer keeps its own
approval prompts, so this needs a real terminal and never installs silently.

The checkout is the first argument, else $CEDAR_CHECKOUT, else ~/cedar-shell.
"""
import os
from pathlib import Path
import shlex
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import distribution as d

GIT_PULL = ['git', 'pull', '--ff-only']
CLONE_HINT = 'git clone --branch main https://github.com/EMQOutlaw/Cedar-Shell.git cedar-shell'


def say(message=''):
    print(message, flush=True)


def resolve_checkout(argv=(), environ=None):
    environ = os.environ if environ is None else environ
    raw = argv[0] if argv else environ.get('CEDAR_CHECKOUT') or str(Path(environ.get('HOME') or Path.home()) / 'cedar-shell')
    checkout = Path(raw).expanduser()
    if not checkout.is_dir():
        raise d.Refused('No CEDAR checkout at ' + str(checkout) + '. Clone one first:\n  ' + CLONE_HINT + '\nor set CEDAR_CHECKOUT to where yours lives.')
    if not (checkout / '.git').exists():
        raise d.Refused(str(checkout) + ' is not a Git checkout, so there is nothing to pull. Extracted archives update through cedar update.')
    if not (checkout / 'install.sh').is_file():
        raise d.Refused(str(checkout) + ' has no install.sh; it does not look like the CEDAR source.')
    return checkout.resolve()


def git(checkout, *args, check=True, strip=True):
    out = subprocess.run(['git', '-C', str(checkout), *args], check=check, text=True, capture_output=True).stdout
    return out.strip() if strip else out.rstrip('\n')


def describe(checkout):
    branch = git(checkout, 'rev-parse', '--abbrev-ref', 'HEAD')
    upstream = git(checkout, 'rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{u}', check=False) or '(no upstream)'
    say('Checkout  ' + str(checkout))
    say('Branch    ' + branch + ' -> ' + upstream)
    version = checkout / 'VERSION'
    if version.is_file():
        say('Version   ' + version.read_text().strip())
    changes = git(checkout, 'status', '--porcelain', check=False, strip=False)
    if changes:
        say('Local changes (Git decides whether they block the pull; they are never discarded):')
        for line in changes.splitlines():
            say('  ' + line)


def pull(checkout):
    """Run the exact documented command; a refusal leaves the checkout as it was."""
    say('$ ' + shlex.join(GIT_PULL))
    result = subprocess.run(GIT_PULL, cwd=str(checkout), text=True)
    if result.returncode:
        raise d.Refused('git pull --ff-only stopped. Keep your edits; do not reset or delete the checkout. Resolve the branch state, then update again.')


def cedar_command():
    launcher = d.paths()['bin']
    if launcher.is_file():
        return [str(launcher)]
    recovery = d.paths()['data'] / 'recovery/distribution.py'
    if recovery.is_file():
        return ['python3', str(recovery)]
    return None


def restore_if_active(active=None, command=None):
    """Restore the previous desktop only while a CEDAR session is running.

    `cedar restore` with no active session would roll back the last install
    instead, so it is never run blindly.
    """
    active = d.session_active() if active is None else active
    if not active:
        say('No CEDAR desktop session is active; nothing to restore.')
        return False
    command = cedar_command() if command is None else command
    if not command:
        raise d.Refused('A CEDAR session is active but the cedar command is missing. Run the recovery tool by hand before installing.')
    say('A CEDAR desktop session is active. Restoring the previous desktop first; this window stays open.')
    say('$ ' + shlex.join(command + ['restore']))
    if subprocess.run(command + ['restore']).returncode:
        raise d.Refused('cedar restore did not finish. The installed release and your checkout are unchanged; run cedar status.')
    return True


def install(checkout):
    say('$ bash ./install.sh')
    result = subprocess.run(['bash', './install.sh'], cwd=str(checkout))
    if result.returncode:
        raise d.Refused('The installer stopped or was canceled. The previously installed release stays selected.')


def main(argv=None):
    argv = sys.argv[1:] if argv is None else list(argv)
    if not sys.stdin.isatty():
        raise d.Refused('Run the update from a terminal; the installer asks for approval there.')
    say('CEDAR update')
    say('============')
    checkout = resolve_checkout(argv)
    describe(checkout)
    say()
    say('Steps: git pull --ff-only, then cedar restore if a session is active, then bash ./install.sh.')
    say('The installer asks before changing anything. Press Enter to begin, or Ctrl-C to stop.')
    input()
    pull(checkout)
    say()
    restored = restore_if_active()
    say()
    install(checkout)
    say()
    say('Update finished.' + (' Your desktop was restored before installing; start the new candidate with cedar try, then cedar keep.' if restored else ''))


if __name__ == '__main__':
    code = 0
    try:
        main()
    except KeyboardInterrupt:
        say('\nStopped. Nothing else was changed.')
        code = 130
    except (d.Refused, OSError, subprocess.SubprocessError) as error:
        say('CEDAR: ' + str(error))
        code = 1
    try:
        input('Press Enter to close this window.')
    except (EOFError, KeyboardInterrupt):
        pass
    sys.exit(code)
