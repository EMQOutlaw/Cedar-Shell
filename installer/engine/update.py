"""Check CEDAR update channels and hand verified source to its installer.

The desktop and CLI choose an allowlisted branch, fetch into CEDAR-owned
bare caches, and export immutable commit snapshots. They never change the
user's checkout. Installed channel provenance is written only after final
installation verification and is tied to the installed release's bytes.

The channel=None API retains the original checkout/release updater for
older programmatic callers; all current front ends use managed channels.
"""
import contextlib
import fcntl
import hashlib
import io
import json
import os
from pathlib import Path
import re
import subprocess
import tarfile
import tempfile
import threading
import uuid
import shutil
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


# Public channels deliberately do not accept arbitrary refs or repositories.
CHANNELS = {'stable': 'main', 'development': 'dev'}
REPOSITORY = 'https://github.com/EMQOutlaw/Cedar-Shell.git'


def channel_branch(channel):
    if not isinstance(channel, str) or channel not in CHANNELS:
        raise Guidance('Unknown update branch', 'Choose Stable Branch or Development Branch.',
                       retry=False, code='channel')
    return CHANNELS[channel]


def _home_path(environ, kind, default):
    home = Path(environ.get('HOME') or Path.home())
    value = Path(environ.get('XDG_' + kind + '_HOME') or home / default)
    return value if value.is_absolute() else home / default


def content_digest(root):
    """Hash exactly the source inventory installed by distribution, including executable bits."""
    from scripts.distribution import files
    digest = hashlib.sha256()
    for path, rel in files(Path(root)):
        digest.update(str(rel).encode() + b'\0')
        digest.update(hashlib.sha256(path.read_bytes()).digest())
        digest.update(str(path.stat().st_mode & 0o111).encode() + b'\0')
    return digest.hexdigest()


def installed_channel(environ=None):
    """Only trust a successful install record that still describes the selected runtime."""
    environ = os.environ if environ is None else environ
    marker = _home_path(environ, 'CONFIG', '.config') / 'cedar/installation.json'
    current = _home_path(environ, 'DATA', '.local/share') / 'cedar/current'
    try:
        record = json.loads(marker.read_text())
        if not isinstance(record, dict):
            return ''
        provenance = record.get('update', {})
        if not isinstance(provenance, dict):
            return ''
        channel = provenance.get('channel')
        if (channel in CHANNELS and current.is_symlink()
                and str(current.resolve()) == provenance.get('installedRelease')
                and content_digest(current.resolve()) == provenance.get('sourceDigest')):
            return channel
    except (OSError, ValueError, TypeError, RuntimeError):
        pass
    return ''


@contextlib.contextmanager
def update_lock(state_dir):
    """Serialize managed fetches and installations across independent installer windows."""
    state_dir = Path(state_dir)
    from scripts.distribution import private_directory
    try:
        private_directory(state_dir)
    except RuntimeError as error:
        raise Guidance('The update store needs attention', str(error), retry=False, code='cache') from error
    path = state_dir / 'update.lock'
    fd = os.open(path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise Guidance('Another update is running', 'Wait for the other CEDAR updater to finish, then try again.',
                           retry=True, code='busy') from None
        yield
    finally:
        os.close(fd)


def verify_update_source(source, environ):
    """A handed-off snapshot must still match the bytes reviewed in the update stage."""
    expected = environ.get('CEDAR_INSTALLER_SOURCE_DIGEST', '')
    if expected and content_digest(source) != expected:
        raise Guidance('The prepared update changed', 'The prepared source no longer matches the checked update. Nothing was installed.',
                       ['Close this installer and check for updates again.'], retry=False, code='source-changed')


def install_provenance(source, installed, environ):
    """Called by the final verification step, never by fetching or choosing a tab."""
    channel = environ.get('CEDAR_INSTALLER_CHANNEL')
    if channel is None:
        return {}
    branch = channel_branch(channel)
    if not environ.get('CEDAR_INSTALLER_SOURCE_DIGEST') or not environ.get('CEDAR_INSTALLER_COMMIT'):
        raise RuntimeError('A branch selection must come from a checked update.')
    verify_update_source(source, environ)
    digest = content_digest(source)
    if content_digest(installed) != digest:
        raise RuntimeError('The installed release does not match the prepared source.')
    commit = environ.get('CEDAR_INSTALLER_COMMIT', '')
    if commit and not re.fullmatch(r'[0-9a-f]{40,64}', commit):
        raise RuntimeError('Invalid update commit.')
    return {'channel': channel, 'branch': branch, 'commit': commit, 'sourceDigest': digest,
            'installedRelease': str(Path(installed).resolve())}


# ------------------------------------------------------------------- updater
class Updater:
    """Find, inspect, fetch, apply, hand off; emits the same events the install stage renders."""

    def __init__(self, source, emit=None, environ=None, state_dir=None, log=None, channel=None, repository=None):
        self.source = Path(source).resolve()
        self.emit = emit or (lambda event, data: None)
        self.environ = dict(os.environ if environ is None else environ)
        self.state_dir = Path(state_dir) if state_dir else Path(self.environ.get('XDG_STATE_HOME') or Path(self.environ.get('HOME') or Path.home()) / '.local/state') / 'cedar/installer'
        self.log = log
        self.channel = channel
        if channel is not None:
            channel_branch(channel)
        self.repository = REPOSITORY if repository is None else str(repository)
        self.cancelled = threading.Event()
        self.prepared = False
        self.session_id = self.environ.get('CEDAR_INSTALLER_UPDATE_ID', '')
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
        return self.state_dir / handoff_name(self.session_id)

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

    # -- managed branch updates --------------------------------------------
    def check_cancelled(self):
        if self.cancelled.is_set():
            raise Guidance('Update cancelled', 'The prepared update was cancelled. Your installed CEDAR was not changed.',
                           retry=True, code='cancelled')

    def managed_git(self, *args, binary=False, timeout=GIT_TIMEOUT):
        self.check_cancelled()
        env = {**self.environ, 'GIT_TERMINAL_PROMPT': '0', 'LC_ALL': 'C'}
        # Ignore inherited per-command config and worktree overrides. Only this
        # owned cache and the allowlisted public URL belong to the channel flow.
        for key in list(env):
            if key.startswith('GIT_') and key not in ('GIT_TERMINAL_PROMPT',):
                env.pop(key)
        env.update({'GIT_CONFIG_NOSYSTEM': '1', 'GIT_CONFIG_GLOBAL': os.devnull})
        command = ['git', '--no-replace-objects', '-C', str(self.cache), *args]
        proc = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
        started = time.monotonic()
        try:
            while True:
                self.check_cancelled()
                if time.monotonic() - started > timeout:
                    raise Guidance('The update timed out', 'GitHub did not finish responding. Your installed CEDAR was not changed.',
                                   ['Check your connection and try again.'], retry=True, code='network')
                try:
                    out, err = proc.communicate(timeout=0.2)
                    break
                except subprocess.TimeoutExpired:
                    pass
        finally:
            if proc.poll() is None:
                proc.kill()
                proc.communicate()
        if proc.returncode:
            message = (err + out).decode('utf-8', 'replace')
            if 'couldn\'t find remote ref' in message.lower():
                raise Guidance('This branch is not available', 'The repository does not publish the ' + self.branch + ' branch yet. Your installed CEDAR was not changed.',
                               ['Choose the other branch or try again after the branch is published.'], code='branch-missing')
            raise classify(message, self.cache, self.branch)
        return out if binary else out.decode('utf-8', 'replace').strip()

    def channel_locate(self, ctx, op):
        self.check_cancelled()
        self.result['previousVersion'] = self.installed_version()
        op.detail = ('Stable Branch' if self.channel == 'stable' else 'Development Branch') + ' · ' + self.branch
        self.say(op.id, op.detail)

    def channel_inspect(self, ctx, op):
        self.check_cancelled()
        if not _which('git'):
            raise Guidance('Git is not installed', 'Branch updates need Git, including installations downloaded as an archive.',
                           ['Install it: `sudo pacman -S --needed git`.', 'Press Try again.'], code='tools')
        from scripts.distribution import private_directory
        private_directory(self.cache)
        if not (self.cache / 'HEAD').exists():
            self.managed_git('init', '--bare', '--quiet')
        if self.managed_git('rev-parse', '--is-bare-repository') != 'true':
            raise Guidance('The update cache is not valid', 'The managed update cache must be a bare Git repository.',
                           ['Move ' + str(self.cache) + ' aside, then try again.'], code='cache')
        op.detail = 'Isolated update cache; your source checkout stays unchanged'

    def channel_fetch(self, ctx, op):
        ctx.progress(op, 0.1, 'Checking ' + self.branch + ' on GitHub')
        self.managed_git('fetch', '--depth=1', '--no-tags', '--no-write-fetch-head', '--force', self.repository,
                         '+refs/heads/' + self.branch + ':refs/cedar/' + self.branch, timeout=FETCH_TIMEOUT)
        self.check_cancelled()
        commit = self.managed_git('rev-parse', '--verify', 'refs/cedar/' + self.branch + '^{commit}')
        if not re.fullmatch(r'[0-9a-f]{40,64}', commit):
            raise Guidance('Git returned an invalid revision', 'The branch did not resolve to a commit.', retry=True, code='commit')
        self.result['commit'] = commit
        op.detail = self.branch + ' · ' + commit[:12]

    def channel_prepare(self, ctx, op):
        self.check_cancelled()
        commit = self.result['commit']
        parent = self.state_dir / 'update-sources' / self.channel
        from scripts.distribution import private_directory
        private_directory(parent)
        target = parent / commit
        metadata = parent / (commit + '.json')
        if target.exists() or target.is_symlink():
            try:
                record = json.loads(metadata.read_text())
                if (target.is_symlink() or record.get('commit') != commit or record.get('channel') != self.channel
                        or record.get('sourceDigest') != content_digest(target)):
                    raise ValueError('prepared source changed')
            except (OSError, ValueError, RuntimeError):
                raise Guidance('The prepared update changed', 'A cached update no longer matches its verified source. It was not installed.',
                               ['Move ' + str(target) + ' aside and check for updates again.'], code='source-changed') from None
        else:
            raw = self.managed_git('archive', '--format=tar', commit, binary=True)
            self.check_cancelled()
            temporary = Path(tempfile.mkdtemp(prefix='.prepare-', dir=parent))
            try:
                with tarfile.open(fileobj=io.BytesIO(raw), mode='r:') as archive:
                    for member in archive:
                        self.check_cancelled()
                        rel = Path(member.name)
                        if (rel.is_absolute() or '..' in rel.parts or '.git' in rel.parts
                                or not (member.isfile() or member.isdir())):
                            raise Guidance('The source archive is unsafe', 'The branch contains a link or an unsafe archive path.', retry=False, code='archive')
                        destination = temporary / rel
                        if member.isdir():
                            destination.mkdir(parents=True, exist_ok=True)
                        else:
                            destination.parent.mkdir(parents=True, exist_ok=True)
                            with archive.extractfile(member) as src, destination.open('xb') as dest:
                                shutil.copyfileobj(src, dest)
                            os.chmod(destination, member.mode & 0o777)
                if not (temporary / 'installer/cedar_install.py').is_file():
                    raise Guidance('The branch has no installer', 'The selected branch does not contain the CEDAR installer.', retry=False, code='handoff')
                digest = content_digest(temporary)
                self.check_cancelled()
                os.replace(temporary, target)
                record = {'commit': commit, 'channel': self.channel, 'sourceDigest': digest}
                temp_meta = metadata.with_suffix('.tmp')
                temp_meta.write_text(json.dumps(record)); os.chmod(temp_meta, 0o600)
                os.replace(temp_meta, metadata)
            finally:
                if temporary.exists():
                    shutil.rmtree(temporary)
        self.result.update({'source': str(target), 'sourceDigest': record['sourceDigest'], 'version': self.version_of(target)})
        op.detail = 'Prepared ' + self.branch + ' at ' + commit[:12] + '; installed copy unchanged'

    def channel_handoff(self, ctx, op):
        self.check_cancelled()
        current = _home_path(self.environ, 'DATA', '.local/share') / 'cedar/current'
        try:
            same_contents = current.is_symlink() and content_digest(current.resolve()) == self.result['sourceDigest']
        except (OSError, ValueError, RuntimeError):
            same_contents = False
        self.result['installedChannel'] = installed_channel(self.environ)
        self.result['current'] = same_contents and self.result['installedChannel'] == self.channel
        self.result['changed'] = not same_contents
        self.prepared = True
        op.detail = ('CEDAR is up to date on ' + self.branch if self.result['current'] else
                     'Ready to install from ' + self.branch + ' · ' + self.result['commit'][:12])

    def run_channel(self):
        self.cancelled.clear()
        self.prepared = False
        self.branch = channel_branch(self.channel)
        self.cache = self.state_dir / 'update-cache' / (self.channel + '.git')
        self.result = {'kind': 'channel', 'channel': self.channel, 'branch': self.branch,
                       'installedChannel': installed_channel(self.environ), 'source': '', 'sourceDigest': '',
                       'commit': '', 'version': '', 'previousVersion': '', 'current': False, 'notes': [], 'changed': False}
        rows = [('locate', 'Branch', 'The CEDAR branch you selected', self.channel_locate),
                ('inspect', 'Prepare', 'Use an isolated update cache', self.channel_inspect),
                ('fetch', 'Check', 'Fetch the latest branch revision', self.channel_fetch),
                ('apply', 'Prepare source', 'Verify an immutable copy of the selected revision', self.channel_prepare),
                ('handoff', 'Installer', 'Compare the prepared source with your installed CEDAR', self.channel_handoff)]
        runner = ops.Runner([ops.Operation(*row) for row in rows], self.state_dir / 'update-state.json',
                            self.log, self.emit, version=self.version_of(self.source), run_id='update-' + uuid.uuid4().hex)
        try:
            with update_lock(self.state_dir):
                self.handoff_path.unlink(missing_ok=True)
                self.emit('operations', [op.to_dict() for op in runner.operations])
                runner.run(_Context(runner))
                self.check_cancelled()
        except (ops.Failed, Guidance) as failure:
            self.prepared = False
            cause = failure.__cause__ if isinstance(failure, ops.Failed) else failure
            guidance = cause if isinstance(cause, Guidance) else Guidance('Update stopped', str(failure), ['Press Try again.'], code='unexpected')
            self.emit('update-error', {**guidance.to_dict(), 'operation': getattr(getattr(failure, 'operation', None), 'id', ''),
                                      'channel': self.channel, 'branch': self.branch, 'installedChannel': installed_channel(self.environ),
                                      'notes': self.result['notes'], 'log': str(self.log.path) if self.log else ''})
            raise guidance
        self.emit('updated', dict(self.result))
        return dict(self.result)

    # -- fixes -------------------------------------------------------------
    def fix(self, name):
        """A safe, reversible repair the person asked for by its button."""
        if self.channel is not None or self.kind != 'checkout':
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
        if self.channel is not None:
            return self.run_channel()
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
        if self.channel is not None:
            self.check_cancelled()
            if not self.prepared or content_digest(self.result['source']) != self.result['sourceDigest']:
                raise Guidance('Check for updates again', 'The prepared update is missing or changed.', retry=True, code='source-changed')
        self.state_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
        record = {'format': 1, 'sessionId': self.session_id, 'source': self.result['source'], 'version': self.result['version'], 'argv': list(argv), 'at': time.time()}
        if self.channel is not None:
            record.update({key: self.result[key] for key in ('channel', 'branch', 'commit', 'sourceDigest')})
        temporary = self.handoff_path.with_name(self.handoff_path.name + '.tmp')
        temporary.write_text(json.dumps(record, indent=2)); os.chmod(temporary, 0o600)
        os.replace(temporary, self.handoff_path)
        self.emit('handoff', record)
        return record

    def cancel(self):
        self.cancelled.set()
        self.prepared = False
        try:
            self.handoff_path.unlink()
        except OSError:
            pass


def handoff_name(session_id=''):
    if session_id and not re.fullmatch(r'[0-9a-f]{32}', session_id):
        raise ValueError('Invalid update session identifier')
    return 'update-handoff' + ('-' + session_id if session_id else '') + '.json'


def take_handoff(state_dir, max_age=3600, session_id=''):
    """Read and remove the handoff record a window left behind; None when there is none or it is stale."""
    path = Path(state_dir) / handoff_name(session_id)
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
    try:
        age = time.time() - float(record.get('at', 0))
    except (TypeError, ValueError):
        return None
    if age < 0 or age > max_age or record.get('sessionId', '') != session_id:
        return None
    if 'channel' in record:
        try:
            if (record.get('branch') != channel_branch(record['channel'])
                    or content_digest(record['source']) != record.get('sourceDigest')):
                return None
        except (OSError, ValueError, RuntimeError, KeyError, TypeError):
            return None
    if not isinstance(record.get('source'), str) or not (Path(record['source']) / 'installer/cedar_install.py').is_file():
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
