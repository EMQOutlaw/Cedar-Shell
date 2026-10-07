"""Package providers. Only pacman is reviewed; the others say so instead of pretending."""


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
    id, status, manager = 'pacman', 'supported', 'pacman'

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
        notes.append('pacman -Syu performs a full system upgrade along with the new packages, as Arch requires for a consistent system.')
        return notes

    def argv(self, packages):
        return ['pacman', '-Syu', '--needed', '--noconfirm', *packages]

    def describe(self, packages):
        return 'Install ' + ', '.join(packages) + ' with pacman (full system upgrade)'


class AptProvider(PackageProvider):
    id, manager = 'apt', 'apt-get'


class DnfProvider(PackageProvider):
    id, manager = 'dnf', 'dnf'


class ZypperProvider(PackageProvider):
    id, manager = 'zypper', 'zypper'


PROVIDERS = (PacmanProvider(), AptProvider(), DnfProvider(), ZypperProvider())


def select(facts):
    backend = facts['support'].get('backend', '')
    for provider in PROVIDERS:
        if provider.id == backend or (backend == '' and provider.manager == facts.get('packageManager')):
            return provider
    return PackageProvider()
