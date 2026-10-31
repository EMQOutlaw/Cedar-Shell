#!/usr/bin/env python3
"""Which package family this machine belongs to: arch or fedora, decided once from /etc/os-release.

Every script that names a package, prints an install command or picks a package manager asks
here, so CEDAR never guesses from whichever package manager happens to be installed. ID and
ID_LIKE decide: Arch Linux, CachyOS and Omarchy are 'arch'; Fedora and its derivatives are
'fedora'; anything else is '' and gets the plain "install X with your package manager" wording.
"""
from pathlib import Path
import shutil

FAMILIES = {
    'arch': {'label': 'Arch', 'key': 'archPackage', 'manager': 'pacman', 'install': 'sudo pacman -S --needed', 'upgrade': True,
             'tools': {'sha256sum': 'coreutils', 'python3': 'python', 'python': 'python'}},
    'fedora': {'label': 'Fedora', 'key': 'fedoraPackage', 'manager': 'dnf', 'install': 'sudo dnf install', 'upgrade': False,
               'tools': {'sha256sum': 'coreutils', 'python3': 'python3', 'python': 'python3', 'tar': 'tar', 'curl': 'curl', 'git': 'git'}},
}


def os_release(path='/etc/os-release'):
    release = {}
    try:
        for line in Path(path).read_text().splitlines():
            if '=' in line and not line.startswith('#'):
                key, value = line.split('=', 1)
                release[key.strip()] = value.strip().strip('"')
    except OSError:
        pass
    return release


def family(release=None):
    """'arch', 'fedora' or '' from ID and ID_LIKE; a package manager on disk never decides."""
    release = os_release() if release is None else release
    ids = [release.get('ID', '').lower(), *release.get('ID_LIKE', '').lower().split()]
    for name in FAMILIES:
        if name in ids:
            return name
    return ''


def package_key(fam=None):
    fam = family() if fam is None else fam
    return FAMILIES.get(fam, FAMILIES['arch'])['key']


def package_name(row, fam=None):
    """The manifest row's package for this family; null means the family has no equivalent, so None.
    The older imageFormats 'package' column is an Arch name and is only read for Arch."""
    fam = family() if fam is None else fam
    key = package_key(fam)
    if key in row:
        return row.get(key)
    return row.get('package') if fam in ('arch', '') else None


def manager(fam=None):
    fam = family() if fam is None else fam
    return FAMILIES.get(fam, {}).get('manager', '')


def install_command(packages, fam=None):
    """A copyable command for this family, or plain words when the family is unknown."""
    fam = family() if fam is None else fam
    names = [FAMILIES[fam]['tools'].get(p, p) for p in packages] if fam in FAMILIES else list(packages)
    if fam in FAMILIES:
        return FAMILIES[fam]['install'] + ' ' + ' '.join(names)
    return 'install ' + ', '.join(names) + ' with your package manager'


def install_hint(packages, fam=None):
    """A guidance line: 'Install it: `sudo dnf install git`.' or plain words for an unknown family."""
    fam = family() if fam is None else fam
    verb = 'Install it' if len(packages) == 1 else 'Install them'
    if fam in FAMILIES:
        return verb + ': `' + install_command(packages, fam) + '`.'
    return verb.split()[0] + ' ' + ', '.join(packages) + ' with your package manager.'


def installed_packages():
    """Installed package name → version through the family's own query; {} elsewhere. Read-only."""
    import subprocess
    fam = family()
    if fam == 'arch' and shutil.which('pacman'):
        argv = ['pacman', '-Q']
    elif fam == 'fedora' and shutil.which('rpm'):
        argv = ['rpm', '-qa', '--qf', '%{NAME} %{VERSION}\n']
    else:
        return {}
    result = subprocess.run(argv, capture_output=True, text=True, timeout=30)
    if result.returncode:
        return {}
    return dict(line.split(' ', 1) for line in result.stdout.splitlines() if ' ' in line)


if __name__ == '__main__':
    import json
    fam = family()
    print(json.dumps({'family': fam or 'unknown', 'manager': manager(fam), 'packageKey': package_key(fam), 'installCommand': install_command(['git'], fam)}, indent=2))
