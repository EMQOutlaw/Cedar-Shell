"""The native package recipes stay consistent with each other and with the dependency manifest.

Recipe text only: no makepkg or rpmbuild runs here. The RPM build itself is exercised by
tests/check_fedora_package.py inside a Fedora container (.github/workflows/validate.yml).
"""
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = json.loads((ROOT / 'data/dependencies.json').read_text())
SPEC = (ROOT / 'packaging/fedora/cedar-shell.spec').read_text()


def manifest_fedora_names():
    names = set()
    for section in ('commands', 'pythonModules', 'pkgconfigModules', 'modules', 'imageFormats', 'fonts'):
        for row in MANIFEST[section]:
            if row.get('fedoraPackage'):
                names.add(row['fedoraPackage'])
    return names


def install_sh_list(variable):
    text = (ROOT / 'install.sh').read_text()
    match = re.search(r'^' + variable + r'="([^"]+)"', text, flags=re.M)
    return match.group(1).split()


class Recipes(unittest.TestCase):
    def test_every_recipe_carries_the_published_version(self):
        version = (ROOT / 'VERSION').read_text().strip()
        self.assertIn('pkgver=' + version + '\n', (ROOT / 'packaging/arch/PKGBUILD').read_text())
        self.assertIn('  version = "' + version + '";', (ROOT / 'packaging/nix/package.nix').read_text())
        self.assertTrue(re.search(r'^Version:\s+' + re.escape(version) + r'$', SPEC, flags=re.M), 'spec Version is not ' + version)
        self.assertIn('- ' + version + '-', SPEC.split('\n%changelog\n', 1)[1].splitlines()[0])

    def test_the_spec_builds_from_the_release_archive_without_scriptlets(self):
        self.assertIn('cedar-%{version}-x86_64.tar.gz', SPEC)
        self.assertIn('%autosetup -n cedar-shell', SPEC)
        for scriptlet in ('%pre', '%post', '%preun', '%postun', '%posttrans', '%triggerin'):
            self.assertNotRegex(SPEC, r'^' + re.escape(scriptlet) + r'\b', scriptlet + ' would change the system on install')
        self.assertIn('%undefine __brp_mangle_shebangs', SPEC); self.assertIn('%undefine __brp_python_bytecompile', SPEC)
        for path in ('%{_bindir}/cedar', '%{_bindir}/cedar-task-manager', '%{_datadir}/cedar/', '%{_datadir}/applications/cedar-task-manager.desktop'):
            self.assertIn('\n' + path + '\n', SPEC)
        for shipped in ('licenses/Omarchy-MIT.txt', 'docs/LICENSES.md', 'data/applications/cedar-task-manager.desktop', 'data/icons/cedar-shield.svg', 'scripts/build_task_manager.py'):
            self.assertTrue((ROOT / shipped).is_file(), shipped)

    def test_spec_requirements_are_manifest_fedora_names(self):
        declared = set(re.findall(r'^(?:Requires|Recommends|Suggests):\s+(\S+)', SPEC, flags=re.M))
        self.assertIn('quickshell', declared); self.assertIn('hyprland', declared); self.assertIn('python3', declared)
        # Packages the manifest does not list are Quickshell's own Qt modules and audio stack; everything else must be a manifest name.
        allowed_extra = {'qt6-qtmultimedia', 'qt6-qt5compat', 'qt6-qtimageformats', 'wireplumber', 'cliphist', 'ppd-service'}
        unknown = declared - manifest_fedora_names() - allowed_extra
        self.assertEqual(unknown, set(), 'spec names not in data/dependencies.json fedoraPackage: ' + ', '.join(sorted(unknown)))

    def test_every_manifest_row_decides_its_fedora_name(self):
        for section in ('commands', 'pythonModules', 'pkgconfigModules', 'modules', 'imageFormats', 'fonts'):
            for row in MANIFEST[section]:
                self.assertIn('fedoraPackage', row, section + ': ' + json.dumps(row)[:80])
        # The Task Manager's Qt Quick build files are a runtime package on Arch and a -devel package on Fedora; the probe is the same.
        self.assertEqual([(r['archPackage'], r['fedoraPackage'], r['probe'][:2]) for r in MANIFEST['pkgconfigModules']], [('qt6-declarative', 'qt6-qtdeclarative-devel', ['pkg-config', '--exists'])])
        # Arch names never leak into the Fedora column.
        arch_only = {'python', 'qt6-declarative', 'qt6-base', 'qt6-svg', 'networkmanager', 'libnm', 'libpulse', 'pacman-contrib', 'ttf-jetbrains-mono-nerd', 'pkgconf', 'gcc', 'modemmanager', 'imagemagick', 'xorg-xrandr', 'nvidia-utils'}
        self.assertEqual(manifest_fedora_names() & arch_only, set())
        backends = {b['id']: b for b in MANIFEST['packageManagement']['backends']}
        self.assertEqual(backends['dnf']['packageKey'], 'fedoraPackage'); self.assertFalse(backends['dnf']['upgradeRequired'])
        self.assertEqual(backends['dnf']['distributions'], {'fedora': 'Fedora Linux'})

    def test_install_sh_fedora_list_matches_the_manifest(self):
        fedora = install_sh_list('fedora_packages')
        self.assertEqual(len(fedora), len(set(fedora)), 'duplicates')
        self.assertEqual(set(fedora) - manifest_fedora_names(), set())
        for required in ('git', 'python3', 'python3-gobject', 'hyprland', 'quickshell', 'qt6-qtdeclarative', 'gcc-c++', 'pkgconf-pkg-config', 'qt6-qtbase-devel', 'qt6-qtdeclarative-devel'):
            self.assertIn(required, fedora)
        self.assertNotIn('pacman-contrib', fedora); self.assertNotIn('ttf-jetbrains-mono-nerd', fedora)
        self.assertNotIn('power-profiles-daemon', fedora, 'conflicts with tuned-ppd on Fedora Workstation')


if __name__ == '__main__':
    unittest.main()
