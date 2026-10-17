"""Package providers. pacman and dnf are reviewed; apt and zypper say so instead of pretending.

pacman serves Arch Linux, CachyOS and Omarchy; dnf serves Fedora using the
person's enabled repositories. Runtime availability varies by Fedora release.
No provider ever adds a repository, a key or a community build.
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


class DnfProvider(PackageProvider):
    """dnf on Fedora. `dnf install` adds only the listed packages from the repositories that
    are already enabled; Fedora has no partial-upgrade rule, so no system upgrade is run.
    Hyprland and Quickshell availability varies by Fedora release; additional
    repositories such as COPR must be enabled by the person. A package that
    `dnf info` cannot find stops the plan."""
    id, status, manager = 'dnf', 'supported', 'dnf'

    def check(self, host, packages):
        if not host.which('dnf'):
            raise Unsupported('dnf is not available.')
        for package in packages:
            code, _, err = host.run(['dnf', '-q', 'info', package], timeout=120)
            if code != 0:
                raise Unsupported('Package ' + package + ' is not in your enabled repositories. Runtime package availability varies by Fedora release; configure a repository that provides it, or install a compatible runtime yourself. CEDAR adds no repository.')
        return ['Uses your configured dnf repositories with their existing signature settings; no repository or COPR is added.',
                'dnf install adds only the listed packages; no system upgrade is run.']

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
            return PacmanProvider(omarchy=omarchy) if provider.id == 'pacman' else provider
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
        return 'A listed package is not in your enabled repositories. Runtime package availability varies by Fedora release; configure a repository that provides it, or install a compatible runtime yourself, then retry this step. CEDAR adds no repository.'
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
