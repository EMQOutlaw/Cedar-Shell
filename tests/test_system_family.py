"""The package family comes from /etc/os-release once and every package name, hint and query follows it."""
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import system_family as sf  # noqa: E402


class Family(unittest.TestCase):
    def test_id_and_id_like_decide_never_the_installed_manager(self):
        self.assertEqual(sf.family({'ID': 'fedora'}), 'fedora')
        self.assertEqual(sf.family({'ID': 'nobara', 'ID_LIKE': 'fedora'}), 'fedora')
        self.assertEqual(sf.family({'ID': 'arch'}), 'arch')
        self.assertEqual(sf.family({'ID': 'cachyos', 'ID_LIKE': 'arch'}), 'arch')
        self.assertEqual(sf.family({'ID': 'omarchy', 'ID_LIKE': 'arch'}), 'arch')
        self.assertEqual(sf.family({'ID': 'debian'}), '')
        self.assertEqual(sf.family({}), '')
        with patch.object(sf.shutil, 'which', return_value='/usr/bin/dnf'):
            self.assertEqual(sf.family({'ID': 'arch'}), 'arch', 'a dnf binary on an Arch box changes nothing')

    def test_package_names_follow_the_family_and_null_is_not_guessed(self):
        row = {'archPackage': 'qt6-declarative', 'fedoraPackage': 'qt6-qtdeclarative'}
        self.assertEqual(sf.package_name(row, 'arch'), 'qt6-declarative')
        self.assertEqual(sf.package_name(row, 'fedora'), 'qt6-qtdeclarative')
        self.assertIsNone(sf.package_name({'archPackage': 'pacman-contrib', 'fedoraPackage': None}, 'fedora'))
        self.assertEqual(sf.package_name({'package': 'qt6-base'}, 'arch'), 'qt6-base')
        self.assertIsNone(sf.package_name({'package': 'qt6-base'}, 'fedora'), 'the legacy column is an Arch name')
        self.assertEqual(sf.package_key('fedora'), 'fedoraPackage'); self.assertEqual(sf.package_key(''), 'archPackage')

    def test_install_hints_are_copyable_commands_for_known_families(self):
        self.assertEqual(sf.install_hint(['git'], 'arch'), 'Install it: `sudo pacman -S --needed git`.')
        self.assertEqual(sf.install_hint(['git'], 'fedora'), 'Install it: `sudo dnf install git`.')
        self.assertEqual(sf.install_hint(['tar', 'sha256sum'], 'arch'), 'Install them: `sudo pacman -S --needed tar coreutils`.')
        self.assertEqual(sf.install_hint(['python'], 'fedora'), 'Install it: `sudo dnf install python3`.')
        self.assertEqual(sf.install_hint(['git'], ''), 'Install git with your package manager.')
        self.assertEqual(sf.manager('fedora'), 'dnf'); self.assertEqual(sf.manager(''), '')

    def test_os_release_parsing_strips_quotes_and_survives_absence(self):
        path = ROOT / 'tests' / 'fixtures' / 'os-release.fedora'
        with patch.object(sf, 'os_release', return_value={'ID': 'fedora', 'ID_LIKE': ''}):
            self.assertEqual(sf.family(), 'fedora')
        self.assertEqual(sf.os_release('/nonexistent/os-release'), {})
        with patch.object(Path, 'read_text', return_value='NAME="Fedora Linux"\nID=fedora\nVARIANT_ID=workstation\n# comment\n'):
            self.assertEqual(sf.os_release()['NAME'], 'Fedora Linux'); self.assertEqual(sf.os_release()['ID'], 'fedora')

    def test_capabilities_and_installer_hints_use_the_detector(self):
        import distribution as d
        with patch.object(sf, 'family', return_value='fedora'):
            caps = {c['id']: c['package'] for c in d.capabilities(d.ROOT)}
        self.assertEqual(caps['qs'], 'quickshell'); self.assertEqual(caps['python3'], 'python3'); self.assertIsNone(caps['checkupdates'])
        self.assertEqual(caps['Qt6Quick'], 'qt6-qtdeclarative-devel')
        with patch.object(sf, 'family', return_value='arch'):
            caps = {c['id']: c['package'] for c in d.capabilities(d.ROOT)}
        self.assertEqual(caps['python3'], 'python'); self.assertEqual(caps['checkupdates'], 'pacman-contrib')
        sys.path.insert(0, str(ROOT))
        from installer.engine import update
        with patch.object(sf, 'family', return_value='fedora'):
            self.assertEqual(update.install_hint(['git']), 'Install it: `sudo dnf install git`.')


if __name__ == '__main__':
    unittest.main()
