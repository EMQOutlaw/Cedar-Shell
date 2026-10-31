"""Package providers. pacman and dnf are reviewed; apt and zypper say so instead of pretending.

pacman serves Arch Linux, CachyOS and Omarchy; dnf serves Fedora using only the
repositories the person has enabled. No provider ever adds a repository, a key,
a COPR or a community build.
"""
import re


class Unsupported(RuntimeError):
    pass


class PackageProvider:
    id = 'none'
    status = 'unsupported'
    manager = ''

    def available(self, host):
        return bool(self.manager) and bool(host.which(self.manager))

    def check(self, host, packages):
        """Read-only preflight: raise Unsupported with a clear reason, or return notes."""
        raise Unsupported('No automatic package setup for this system. Install the dependencies with your own package manager, then run the installer again: ' + ', '.join(packages))

    def argv(self, packages):
        raise Unsupported('No automatic package setup for this system.')

    def describe(self, packages):
        return 'Install ' + str(len(packages)) + ' package' + ('s' if len(packages) != 1 else '') + ' with ' + (self.manager or 'your package manager')


class PacmanProvider(PackageProvider):
    """pacman. On Omarchy, packages are added the way `omarchy pkg add` does: `pacman -S --needed`,
    no system upgrade, because Omarchy's pacman guard (00-omarchy-update-guard.hook, on any package
    upgrade) refuses a direct `pacman -Syu` and keeps system upgrades for `omarchy update`."""
    id, status, manager = 'pacman', 'supported', 'pacman'

    def __init__(self, omarchy=False):
        self.omarchy = omarchy

    def check(self, host, packages):
        notes = []
        if not host.which('pacman'):
            raise Unsupported('pacman is not available.')
        if host.exists('/var/lib/pacman/db.lck'):
            raise Unsupported('The package manager is busy (another pacman is running or a lock was left behind). Finish that first; CEDAR will not remove the lock.')
        for package in packages:
            code, _, err = host.run(['pacman', '-Si', package], timeout=20)
            if code != 0:
                raise Unsupported('Package ' + package + ' is not in your configured repositories. No repositories are added by CEDAR; install it yourself or enable the repository that provides it.')
        notes.append('Uses your configured pacman repositories with their existing signature settings; no repository, AUR helper or community build is added.')
        if self.omarchy:
            notes.append('Added the way omarchy pkg add does (pacman -S --needed), without a system upgrade: Omarchy’s pacman guard refuses a direct pacman -Syu, and system upgrades stay with omarchy update.')
        else:
            notes.append('pacman -Syu performs a full system upgrade along with the new packages, as Arch requires for a consistent system.')
        return notes

    def argv(self, packages):
        if self.omarchy:
            return ['pacman', '-S', '--needed', '--noconfirm', *packages]
        return ['pacman', '-Syu', '--needed', '--noconfirm', *packages]

    def describe(self, packages):
        if self.omarchy:
            return 'Install ' + ', '.join(packages) + ' with pacman (no system upgrade; Omarchy keeps those for omarchy update)'
        return 'Install ' + ', '.join(packages) + ' with pacman (full system upgrade)'


class AptProvider(PackageProvider):
    id, manager = 'apt', 'apt-get'


def version_tuple(text):
    """Leading numeric fields of a version string ("0.2.1^git20260209" -> (0, 2, 1))."""
    return tuple(int(n) for n in re.findall(r'\d+', text.split('^')[0].split('~')[0])[:4])


class DnfProvider(PackageProvider):
    """dnf on Fedora. `dnf install` adds only the listed packages from the repositories that are
    already enabled; Fedora has no partial-upgrade rule, so no system upgrade is run. Hyprland is
    in Fedora's own repositories; a current Quickshell (Fedora 44+ ships a 0.2.1 snapshot CEDAR
    cannot load, Fedora 42 and 43 none), hypridle on Fedora 42+ and hyprsunset come from a
    repository the person enables (a COPR, for example). A package `dnf info` cannot find, or
    whose candidate version is below the manifest's floor, stops the plan instead of guessing.
    rpm-ostree hosts (Fedora Atomic) are refused: their packages are layered, not dnf-installed."""
    id, status, manager = 'dnf', 'supported', 'dnf'
    # Lowest candidate version dnf may install, from data/dependencies.json
    # (packageManagement.backends[dnf].versionFloors); set by select().
    floors = {'quickshell': '0.3'}

    def check(self, host, packages):
        if not host.which('dnf'):
            raise Unsupported('dnf is not available.')
        if host.exists('/run/ostree-booted'):
            raise Unsupported('This is an rpm-ostree system (Fedora Atomic). CEDAR does not layer packages with rpm-ostree; install the dependencies yourself (rpm-ostree install …, then reboot), then run the installer again.')
        for package in packages:
            code, _, err = host.run(['dnf', '-q', 'info', package], timeout=120)
            if code != 0:
                raise Unsupported('Package ' + package + ' is not in your enabled repositories. Enable a repository that provides it (on Fedora, a current Quickshell, hypridle and hyprsunset come from a repository you add, such as a COPR), or install a compatible build yourself, then check again. CEDAR adds no repository.')
            floor = self.floors.get(package)
            if floor:
                code, out, _ = host.run(['dnf', '-q', 'repoquery', '--qf', '%{version}\n', package], timeout=120)
                candidates = [line.strip() for line in out.splitlines() if line.strip()]
                if code == 0 and candidates and max(version_tuple(v) for v in candidates) < version_tuple(floor):
                    raise Unsupported('Your enabled repositories offer ' + package + ' ' + candidates[-1] + ', but CEDAR needs ' + floor + ' or newer (Fedora ships an older Quickshell snapshot). Enable a repository that provides a current build, or build it yourself, then check again. CEDAR adds no repository.')
        return ['Uses your enabled dnf repositories with their existing GPG settings; no repository, COPR or RPM Fusion is added.',
                'dnf install adds only the listed packages; no system upgrade is run.',
                'Candidate versions are checked against the manifest floor (Quickshell 0.3 or newer) before anything is installed.']

    def argv(self, packages):
        return ['dnf', 'install', '-y', *packages]

    def describe(self, packages):
        return 'Install ' + ', '.join(packages) + ' with dnf (no system upgrade)'


class ZypperProvider(PackageProvider):
    id, manager = 'zypper', 'zypper'


PROVIDERS = (PacmanProvider(), AptProvider(), DnfProvider(), ZypperProvider())


def select(facts):
    backend = facts['support'].get('backend', '')
    omarchy = (facts.get('environment') or {}).get('id') == 'omarchy'
    for provider in PROVIDERS:
        if provider.id == backend or (backend == '' and provider.manager == facts.get('packageManager')):
            if provider.id == 'pacman':
                return PacmanProvider(omarchy=omarchy)
            if provider.id == 'dnf':
                floors = next((b.get('versionFloors') for b in (facts.get('dependencies') or {}).get('backends', []) if b.get('id') == 'dnf'), None)
                if floors:
                    provider.floors = dict(floors)
            return provider
    return PackageProvider()


def explain(lines, omarchy=False):
    """What a failed package transaction meant, in words the person can act on; '' when unknown.

    pacman and dnf phrases are distinct, so one reader serves both backends."""
    text = '\n'.join(lines).lower()
    upgrade = 'omarchy update' if omarchy else 'sudo pacman -Syu'
    if 'omarchy update' in text and ('direct pacman' in text or 'woah' in text):
        return 'Omarchy’s pacman guard refused a direct system upgrade. Run omarchy update first (Super+Escape › Update, or omarchy update in a terminal), then retry this step; CEDAR adds its packages without upgrading the system.'
    if 'failed retrieving file' in text or 'error 404' in text or 'not found in the repositories' in text:
        return 'The package databases are out of date, so a listed package is no longer downloadable. Run ' + upgrade + ' first, then retry this step.'
    if 'no match for argument' in text:
        return 'A listed package is not in your enabled repositories. Enable a repository that provides it (CEDAR adds none), or install a compatible build yourself, then retry this step.'
    if 'unable to lock database' in text or 'db.lck' in text:
        return 'Another package manager is running or left its lock behind. Let it finish (or remove /var/lib/pacman/db.lck only if nothing is running), then retry this step.'
    if 'waiting for process with pid' in text or 'holding the yum lock' in text or 'holding the dnf lock' in text:
        return 'Another package manager is running or left its lock behind. Let it finish, then retry this step.'
    if 'exists in filesystem' in text or 'conflicting files' in text:
        return 'A package would overwrite a file that is already on this system. Read the file names in the log, resolve the conflict with pacman yourself, then retry this step.'
    if 'transaction test error' in text or re.search(r'file .* conflicts', text):
        return 'A package would overwrite a file that is already on this system. Read the file names in the log, resolve the conflict with dnf yourself, then retry this step.'
    if ('could not resolve host' in text or 'failed to synchronize' in text or 'connection timed out' in text or 'temporary failure' in text
            or 'failed to download metadata' in text or 'cannot download' in text):
        return 'The package mirror could not be reached. Check the connection, then retry this step.'
    if 'not authorized' in text or 'dismissed' in text or 'authentication failed' in text or 'incorrect password' in text:
        return 'The password prompt was dismissed or refused. Retry this step and enter your password when the system asks.'
    if 'gpg check failed' in text or 'public key for' in text:
        return 'A package signature could not be verified against the repository key. Import or enable the repository key, then retry this step.'
    if 'signature' in text and ('unknown trust' in text or 'invalid or corrupted' in text):
        return 'A package signature could not be verified. Refresh the keyrings (' + ('omarchy update' if omarchy else 'sudo pacman -Sy archlinux-keyring') + '), then retry this step.'
    return ''
