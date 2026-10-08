"""Fetch the newest CEDAR as visible steps, then hand over to its installer.

The update is the first stage of the CEDAR Installer, not a terminal
prelude to it. Updater runs the same Operation/Runner model the install
stage renders: find the source (a Git checkout, or the published release),
look at it, fetch, apply, hand off. Each step reports what it did; a stop
is a Guidance: what happened in plain words, the numbered steps that put it
right, and, when the fix is safe and reversible, an action the window can
run. Nothing here resets, rewrites or deletes a checkout: a fast-forward is
the only way the branch moves, and edits are set aside with `git stash`
only when the person asks, with the command that brings them back shown.

A checkout wins when one exists (the source itself, $CEDAR_CHECKOUT,
~/cedar-shell); otherwise the bootstrap downloads and verifies the latest
release with CEDAR_FETCH_ONLY=1 and reports where it put it.
"""
import json
import os
from pathlib import Path
import re
import subprocess
import time

from . import operations as ops

GIT_TIMEOUT = 180
FETCH_TIMEOUT = 900


class Guidance(RuntimeError):
    """A stop the person can act on: message, numbered steps, an optional safe fix."""

    def __init__(self, title, message, steps=(), fix='', retry=True, code=''):
        super().__init__(message)
        self.title, self.message, self.steps, self.fix, self.retry, self.code = title, message, list(steps), fix, retry, code

    def to_dict(self):
        return {'title': self.title, 'message': self.message, 'steps': self.steps, 'fix': self.fix, 'fixLabel': FIX_LABELS.get(self.fix, ''),
                'retry': self.retry, 'code': self.code}


FIX_LABELS = {'stash': 'Set my edits aside and update', 'upstream': 'Track the main branch and update', 'safe-directory': 'Trust this checkout and update'}


def locate(source, environ=None):
    """Where the newest CEDAR comes from: ('checkout', path) or ('bootstrap', install.sh)."""
    environ = os.environ if environ is None else environ
    candidates = [Path(source)]
    if environ.get('CEDAR_CHECKOUT'):
        candidates.append(Path(environ['CEDAR_CHECKOUT']).expanduser())
    candidates.append(Path(environ.get('HOME') or Path.home()) / 'cedar-shell')
    for candidate in candidates:
        if (candidate / '.git').exists() and (candidate / 'installer/cedar_install.py').is_file():
            return 'checkout', candidate.resolve()
    return 'bootstrap', (Path(source) / 'installer/bootstrap/install.sh').resolve()


# ------------------------------------------------------------ classification
def classify(stderr, checkout='', branch='main'):
    """Turn git's refusal into a Guidance. Only safe, reversible fixes are offered."""
    text = stderr or ''
    low = text.lower()
    where = str(checkout) or 'the checkout'
    if re.search(r'could not resolve host|unable to access|connection (refused|timed out|reset)|network is unreachable|could not read from remote|failed to connect|temporary failure in name resolution|ssl|tls', low):
        return Guidance('No connection to GitHub', 'CEDAR could not reach the repository to look for a newer version. Nothing was changed.',
                        ['Check that this computer is online (open any website).', 'If you use a VPN or proxy, make sure it allows github.com.', 'Press Try again.'],
                        retry=True, code='network')
    if 'would be overwritten' in low and 'untracked working tree files' in low:
        files = _listed_files(text)
        return Guidance('Files in the checkout are in the way', 'The update brings files that already exist in ' + where + ' but are not part of Git. CEDAR does not delete your files.',
                        ['Move these files out of the checkout (or delete them if you no longer need them): ' + (', '.join(files) if files else 'see the log') + '.', 'Press Try again.'],
                        retry=True, code='untracked')
    if 'would be overwritten' in low or 'your local changes' in low:
        files = _listed_files(text)
        return Guidance('You have edits in the checkout', 'Files you changed in ' + where + ' would be replaced by the update' + (': ' + ', '.join(files) if files else '') + '. CEDAR never discards edits.',
                        ['Set my edits aside: this runs `git stash` in the checkout, which keeps every edit in Git’s stash list; `git stash pop` brings them back afterwards.',
                         'Or commit them yourself: `git -C ' + where + ' commit -am "my changes"`, then press Try again (a commit of your own makes the history diverge; see the next message if so).'],
                        fix='stash', retry=True, code='edits')
    if 'not possible to fast-forward' in low or 'diverg' in low or 'need to specify how to reconcile' in low:
        return Guidance('This checkout has its own commits', 'The branch in ' + where + ' has commits that are not on GitHub, so the update cannot be applied as a plain fast-forward. CEDAR does not rewrite history.',
                        ['Open a terminal in the checkout: `cd ' + where + '`.', 'Put your commits on top of the newest CEDAR: `git rebase origin/' + branch + '` (or merge: `git merge origin/' + branch + '`).',
                         'If you do not need those commits, clone a fresh copy next to this one instead; nothing here is deleted for you.', 'Press Try again.'],
                        retry=True, code='diverged')
    if 'no tracking information' in low or 'no upstream' in low or 'does not have any commits yet' in low or 'no such ref was fetched' in low:
        return Guidance('The branch is not following GitHub', 'Git does not know which GitHub branch ' + where + ' should update from.',
                        ['Track the main branch: `git -C ' + where + ' branch --set-upstream-to=origin/' + branch + '`.', 'Press Try again.'],
                        fix='upstream', retry=True, code='upstream')
    if 'dubious ownership' in low:
        return Guidance('Git does not trust this checkout', 'The checkout at ' + where + ' is owned by a different user than the one running the update, so Git refuses to touch it.',
                        ['If this is your checkout, mark it safe: `git config --global --add safe.directory ' + where + '`.', 'Press Try again.'],
                        fix='safe-directory', retry=True, code='ownership')
    if 'permission denied (publickey)' in low or 'authentication failed' in low or 'could not read username' in low:
        return Guidance('GitHub needs a login for this checkout', 'The checkout at ' + where + ' uses a remote that asks for credentials, and none were available to the installer.',
                        ['Switch the remote to the public HTTPS address: `git -C ' + where + ' remote set-url origin https://github.com/EMQOutlaw/Cedar-Shell.git`.', 'Press Try again.'],
                        retry=True, code='auth')
    if 'cannot lock ref' in low:
        return Guidance('Git could not update a reference', 'An earlier interrupted Git operation left ' + where + ' with a reference Git cannot read.',
                        ['Open a terminal in the checkout: `cd ' + where + '`.', 'Run `git fsck` and remove the file it names under `.git/` (only that file).', 'Press Try again.'],
                        retry=True, code='refs')
    if 'not a git repository' in low or 'does not appear to be a git repository' in low:
        return Guidance('The source is not a checkout anymore', where + ' no longer looks like a Git checkout, or its remote is gone.',
                        ['Clone a fresh copy: `git clone --branch main https://github.com/EMQOutlaw/Cedar-Shell.git ~/cedar-shell`.', 'Press Try again.'],
                        retry=True, code='repository')
    first = next((line for line in text.strip().splitlines() if line.strip()), '').strip()
    return Guidance('Git stopped', first or 'Git stopped without saying why.',
                    ['Open a terminal in the checkout: `cd ' + where + '`.', 'Run `git pull --ff-only` and read its message.', 'Press Try again once it succeeds, or keep the terminal output for a bug report.'],
                    retry=True, code='git')


def classify_bootstrap(output):
    """The bootstrap's own refusals, turned into guidance."""
    low = (output or '').lower()
    if 'no published cedar release' in low:
        return Guidance('No published release yet', 'GitHub has no CEDAR release to download, so the update has nothing newer to install.',
                        ['Install from the source branch instead: `curl -fsSL https://raw.githubusercontent.com/EMQOutlaw/Cedar-Shell/main/installer/bootstrap/install.sh | CEDAR_CHANNEL=development sh`.',
                         'Or clone the repository: `git clone --branch main https://github.com/EMQOutlaw/Cedar-Shell.git ~/cedar-shell`; later updates then pull that checkout.'],
                        retry=False, code='no-release')
    if 'verification failed' in low or 'checksum' in low:
        return Guidance('The download did not verify', 'The downloaded release did not match its published checksum, so nothing was extracted or installed.',
                        ['Press Try again; a partial download is the usual cause.', 'If it keeps failing, check your network path to github.com before installing anything from it.'],
                        retry=True, code='checksum')
    if 'curl or wget' in low:
        return Guidance('A download tool is missing', 'Neither curl nor wget is installed, so the release cannot be downloaded.',
                        ['Install one: `sudo pacman -S --needed curl`.', 'Press Try again.'], retry=True, code='tools')
    if 'tar is needed' in low or 'sha256sum' in low:
        return Guidance('A tool for unpacking is missing', 'tar or sha256sum is missing, so the release cannot be unpacked and verified.',
                        ['Install them: `sudo pacman -S --needed tar coreutils`.', 'Press Try again.'], retry=True, code='tools')
    if 'python 3.11' in low:
        return Guidance('Python is too old', 'CEDAR needs Python 3.11 or newer.', ['Update Python: `sudo pacman -S --needed python`.', 'Press Try again.'], retry=True, code='python')
    if re.search(r'could not resolve|failed to connect|network|timed out|unable to access|curl: \(\d+\)', low):
        return Guidance('No connection to GitHub', 'CEDAR could not download the release. Nothing was changed.',
                        ['Check that this computer is online.', 'If you use a VPN or proxy, make sure it allows github.com.', 'Press Try again.'], retry=True, code='network')
    first = next((line for line in (output or '').strip().splitlines() if line.strip()), '').strip()
    return Guidance('The download stopped', first or 'The bootstrap stopped without saying why.',
                    ['Press Try again.', 'If it keeps stopping, run the bootstrap from a terminal and keep its output: `sh ' + '<source>/installer/bootstrap/install.sh --dry-run`.'],
                    retry=True, code='bootstrap')


def _listed_files(text):
    files = []
    for line in text.splitlines():
        if line.startswith('\t') or line.startswith('        '):
            files.append(line.strip())
    return files[:8]


# ------------------------------------------------------------------- updater
class Updater:
    """Find, inspect, fetch, apply, hand off; emits the same events the install stage renders."""

    def __init__(self, source, emit=None, environ=None, state_dir=None, log=None):
        self.source = Path(source).resolve()
        self.emit = emit or (lambda event, data: None)
        self.environ = dict(os.environ if environ is None else environ)
        self.state_dir = Path(state_dir) if state_dir else Path(self.environ.get('XDG_STATE_HOME') or Path(self.environ.get('HOME') or Path.home()) / '.local/state') / 'cedar/installer'
        self.log = log
        self.kind, self.target = locate(self.source, self.environ)
        self.branch = ''
        self.result = {'kind': self.kind, 'source': '', 'version': '', 'previousVersion': '', 'current': False, 'notes': [], 'changed': False}

    # -- helpers ---------------------------------------------------------
    def say(self, operation, line):
        if self.log:
            self.log.output(line, operation)
        self.emit('log', {'operation': operation, 'line': line})

    def note(self, operation, text):
        self.result['notes'].append(text)
        self.say(operation, text)

    def git(self, *args, check=True, timeout=GIT_TIMEOUT):
        proc = subprocess.run(['git', '-C', str(self.target), *args], text=True, capture_output=True, timeout=timeout, env={**self.environ, 'GIT_TERMINAL_PROMPT': '0', 'LC_ALL': 'C'})
        if check and proc.returncode:
            raise classify(proc.stderr + proc.stdout, self.target, self.branch or 'main')
        return proc

    def version_of(self, root):
        path = Path(root) / 'VERSION'
        return path.read_text().strip() if path.is_file() else ''

    @property
    def handoff_path(self):
        return self.state_dir / 'update-handoff.json'

    # -- operations --------------------------------------------------------
    def locate_run(self, ctx, op):
        if self.kind == 'checkout':
            op.detail = 'Git checkout at ' + str(self.target)
            self.result['previousVersion'] = self.version_of(self.target)
        else:
            if not self.target.is_file():
                raise Guidance('The installer is incomplete', 'This copy of CEDAR has no bootstrap script, so it cannot download a release.',
                               ['Download the installer again: `curl -fsSL https://raw.githubusercontent.com/EMQOutlaw/Cedar-Shell/main/installer/bootstrap/install.sh | sh`.'], retry=False, code='bootstrap-missing')
            op.detail = 'The published release (no Git checkout here)'
            self.result['previousVersion'] = self.version_of(self.source)
        self.say(op.id, op.detail)

    def inspect_run(self, ctx, op):
        if self.kind != 'checkout':
            missing = [tool for tool in ('tar', 'sha256sum') if not _which(tool)]
            if not (_which('curl') or _which('wget')):
                missing.append('curl')
            if missing:
                raise Guidance('Tools for the download are missing', 'The release is downloaded, verified and unpacked with ' + ', '.join(missing) + ', which ' + ('is' if len(missing) == 1 else 'are') + ' not installed.',
                               ['Install them: `sudo pacman -S --needed ' + ' '.join('coreutils' if m == 'sha256sum' else m for m in missing) + '`.', 'Press Try again.'], retry=True, code='tools')
            op.detail = 'Download tools present'
            return
        if not _which('git'):
            raise Guidance('Git is not installed', 'The checkout at ' + str(self.target) + ' can only be updated with Git.', ['Install it: `sudo pacman -S --needed git`.', 'Press Try again.'], retry=True, code='tools')
        self.clear_broken_scratch_ref(op)
        head = self.git('rev-parse', '--abbrev-ref', 'HEAD').stdout.strip()
        if head == 'HEAD':
            raise Guidance('The checkout is not on a branch', str(self.target) + ' has a detached HEAD, so there is no branch to fast-forward.',
                           ['Return to the main branch: `git -C ' + str(self.target) + ' switch main`.', 'Press Try again.'], retry=True, code='detached')
        self.branch = head
        upstream = self.git('rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{u}', check=False)
        if upstream.returncode:
            raise classify(upstream.stderr or 'no upstream', self.target, head)
        changes = self.git('status', '--porcelain').stdout.rstrip('\n')
        detail = 'Branch ' + head + ' → ' + upstream.stdout.strip()
        if changes:
            count = len(changes.splitlines())
            detail += ' · ' + str(count) + ' local edit' + ('' if count == 1 else 's') + ' kept'
            for line in changes.splitlines():
                self.say(op.id, line)
        op.detail = detail
        self.say(op.id, detail)
        if changes:
            raise ops.Warn(detail)

    def fetch_run(self, ctx, op):
        if self.kind == 'checkout':
            ctx_detail = 'Asking GitHub for the newest CEDAR'
            ctx.progress(op, 0.2, ctx_detail)
            proc = self.git('fetch', '--prune', 'origin', timeout=FETCH_TIMEOUT)
            for line in (proc.stderr + proc.stdout).splitlines():
                if line.strip():
                    self.say(op.id, line.rstrip())
            behind = self.git('rev-list', '--count', 'HEAD..@{u}').stdout.strip()
            op.detail = 'Already current' if behind == '0' else behind + ' new commit' + ('' if behind == '1' else 's')
            return
        ctx.progress(op, 0.1, 'Downloading the latest verified release')
        env = {**self.environ, 'CEDAR_FETCH_ONLY': '1'}
        lines = []
        def on_line(line):
            lines.append(line.rstrip())
            self.say(op.id, line.rstrip())
            if line.lower().startswith('downloading'):
                ctx.progress(op, 0.4, line.strip())
            elif line.lower().startswith('verifying'):
                ctx.progress(op, 0.8, line.strip())
        proc = subprocess.Popen(['sh', str(self.target)], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=env)
        for line in proc.stdout:
            on_line(line)
        code = proc.wait(timeout=FETCH_TIMEOUT)
        if code:
            raise classify_bootstrap('\n'.join(lines))
        fetched = next((line.split('=', 1)[1].strip() for line in lines if line.startswith('CEDAR_SOURCE=')), '')
        if not fetched or not (Path(fetched) / 'installer/cedar_install.py').is_file():
            raise Guidance('The download has no installer', 'The bootstrap finished but did not report a CEDAR source with an installer.', ['Press Try again.'], retry=True, code='bootstrap')
        self.result['source'] = fetched
        op.detail = 'Downloaded CEDAR ' + (self.version_of(fetched) or '?')

    def apply_run(self, ctx, op):
        if self.kind != 'checkout':
            raise ops.Skip('Verified release ready to install')
        before = self.git('rev-parse', 'HEAD').stdout.strip()
        behind = self.git('rev-list', '--count', 'HEAD..@{u}').stdout.strip()
        if behind == '0':
            self.result['source'] = str(self.target)
            raise ops.Skip('Already the newest CEDAR (' + (self.version_of(self.target) or '?') + ')')
        proc = self.git('merge', '--ff-only', '@{u}')
        for line in (proc.stdout + proc.stderr).splitlines():
            if line.strip():
                self.say(op.id, line.rstrip())
        after = self.git('rev-parse', 'HEAD').stdout.strip()
        if after == before:
            raise Guidance('The update did not apply', 'Git reported success but the checkout did not move.', ['Open a terminal in ' + str(self.target) + ' and run `git pull --ff-only`.', 'Press Try again.'], retry=True, code='git')
        self.result['source'] = str(self.target)
        self.result['changed'] = True
        op.detail = (self.result['previousVersion'] or '?') + ' → ' + (self.version_of(self.target) or '?')

    def handoff_run(self, ctx, op):
        source = Path(self.result['source'] or (self.target if self.kind == 'checkout' else ''))
        installer = source / 'installer/cedar_install.py'
        if not installer.is_file():
            raise Guidance('The updated CEDAR has no installer', str(source) + ' has no installer/cedar_install.py.', ['Press Try again.', 'If it keeps failing, clone a fresh copy next to this one.'], retry=True, code='handoff')
        self.result['source'] = str(source)
        self.result['version'] = self.version_of(source)
        self.result['current'] = (not self.result['changed']) and bool(self.result['version']) and self.result['version'] == self.installed_version()
        op.detail = ('CEDAR ' + self.result['version'] + ' is already installed' if self.result['current'] else 'CEDAR ' + (self.result['version'] or '?') + ' ready to install')

    def installed_version(self):
        data = Path(self.environ.get('XDG_DATA_HOME') or Path(self.environ.get('HOME') or Path.home()) / '.local/share') / 'cedar/current/VERSION'
        try:
            return data.read_text().strip()
        except OSError:
            return ''

    def clear_broken_scratch_ref(self, op):
        """Remove an unreadable ORIG_HEAD so git can pull again; a readable one is kept."""
        git_dir = Path(self.git('rev-parse', '--git-dir', check=False).stdout.strip() or '.git')
        if not git_dir.is_absolute():
            git_dir = self.target / git_dir
        scratch = git_dir / 'ORIG_HEAD'
        if not scratch.is_file():
            return False
        if self.git('rev-parse', '--verify', '-q', 'ORIG_HEAD', check=False).returncode == 0:
            return False
        scratch.unlink()
        self.note(op.id, 'Removed an unreadable scratch pointer (.git/ORIG_HEAD) left by an interrupted git operation; nothing else was touched.')
        return True

    # -- fixes -------------------------------------------------------------
    def fix(self, name):
        """A safe, reversible repair the person asked for by its button."""
        if self.kind != 'checkout':
            raise Guidance('Nothing to fix here', 'This fix applies to a Git checkout only.', retry=True, code='fix')
        if name == 'stash':
            stamp = time.strftime('%Y-%m-%d %H:%M')
            proc = self.git('stash', 'push', '-m', 'CEDAR update ' + stamp, check=False)
            if proc.returncode:
                raise classify(proc.stderr + proc.stdout, self.target, self.branch or 'main')
            self.note('fix', 'Your edits were set aside as a Git stash ("CEDAR update ' + stamp + '"). Bring them back with: git -C ' + str(self.target) + ' stash pop')
            return 'stash'
        if name == 'upstream':
            branch = self.branch or self.git('rev-parse', '--abbrev-ref', 'HEAD').stdout.strip() or 'main'
            remotes = self.git('remote', check=False).stdout.split()
            if 'origin' not in remotes:
                self.git('remote', 'add', 'origin', 'https://github.com/EMQOutlaw/Cedar-Shell.git')
                self.note('fix', 'Added the GitHub remote as origin.')
            self.git('fetch', 'origin', timeout=FETCH_TIMEOUT)
            target_branch = branch if self.git('rev-parse', '--verify', '-q', 'origin/' + branch, check=False).returncode == 0 else 'main'
            self.git('branch', '--set-upstream-to=origin/' + target_branch, branch)
            self.note('fix', 'Branch ' + branch + ' now follows origin/' + target_branch + '.')
            return 'upstream'
        if name == 'safe-directory':
            subprocess.run(['git', 'config', '--global', '--add', 'safe.directory', str(self.target)], check=True, text=True, capture_output=True, env=self.environ)
            self.note('fix', 'Marked ' + str(self.target) + ' as a safe directory in your Git configuration.')
            return 'safe-directory'
        raise Guidance('Unknown fix', 'There is no fix called ' + str(name) + '.', retry=True, code='fix')

    # -- driving -----------------------------------------------------------
    def operations(self):
        rows = [('locate', 'Source', 'Where the newest CEDAR comes from', self.locate_run),
                ('inspect', 'Checkout', 'Branch, upstream and your local edits', self.inspect_run),
                ('fetch', 'Fetch', 'Ask GitHub for the newest CEDAR', self.fetch_run),
                ('apply', 'Apply', 'Fast-forward the checkout; your edits stay', self.apply_run),
                ('handoff', 'Installer', 'Start the updated installer', self.handoff_run)]
        return [ops.Operation(op_id, title, description, run) for op_id, title, description, run in rows]

    def run(self):
        """Run every step; return the result, or raise Guidance (never a bare git error)."""
        self.kind, self.target = locate(self.source, self.environ)
        self.result.update({'kind': self.kind, 'source': '', 'version': '', 'current': False, 'changed': False})
        state_path = self.state_dir / 'update-state.json'
        try:
            state_path.unlink()
        except OSError:
            pass
        runner = ops.Runner(self.operations(), state_path, self.log, self.emit, version=self.version_of(self.source), run_id='update-' + time.strftime('%Y%m%dT%H%M%S'))
        self.emit('operations', [op.to_dict() for op in runner.operations])
        ctx = _Context(runner)
        try:
            runner.run(ctx)
        except ops.Failed as failure:
            cause = failure.__cause__
            guidance = cause if isinstance(cause, Guidance) else Guidance(failure.operation.title + ' stopped', str(failure), ['Press Try again.', 'If it keeps stopping, open the log and keep it for a bug report.'], retry=True, code='unexpected')
            data = {**guidance.to_dict(), 'operation': failure.operation.id, 'notes': list(self.result['notes']), 'log': str(self.log.path) if self.log else ''}
            self.emit('update-error', data)
            raise guidance
        self.emit('updated', dict(self.result))
        return dict(self.result)

    def proceed(self, argv=()):
        """Record the handoff for the process that owns the window, so it can start the updated installer."""
        self.state_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
        record = {'format': 1, 'source': self.result['source'], 'version': self.result['version'], 'argv': list(argv), 'at': time.time()}
        temporary = self.handoff_path.with_name(self.handoff_path.name + '.tmp')
        temporary.write_text(json.dumps(record, indent=2)); os.chmod(temporary, 0o600)
        os.replace(temporary, self.handoff_path)
        self.emit('handoff', record)
        return record

    def cancel(self):
        try:
            self.handoff_path.unlink()
        except OSError:
            pass


def take_handoff(state_dir, max_age=3600):
    """Read and remove the handoff record a window left behind; None when there is none or it is stale."""
    path = Path(state_dir) / 'update-handoff.json'
    try:
        record = json.loads(path.read_text())
    except (OSError, ValueError):
        return None
    try:
        path.unlink()
    except OSError:
        pass
    if not isinstance(record, dict) or record.get('format') != 1:
        return None
    if time.time() - float(record.get('at', 0)) > max_age:
        return None
    if not (Path(record.get('source', '')) / 'installer/cedar_install.py').is_file():
        return None
    return record


class _Context:
    """The little the update operations need from a context: progress and output."""

    def __init__(self, runner):
        self.runner = runner

    def progress(self, op, progress, detail=None):
        self.runner.update(op, progress=progress, detail=detail)

    def output(self, op, line):
        self.runner.emit('log', {'operation': op.id, 'line': line})


def _which(name):
    from shutil import which
    return which(name)
