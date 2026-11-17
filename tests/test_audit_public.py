"""The publication privacy scan: placeholder homes pass, a real account still stops it."""
from pathlib import Path
import importlib.util
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('audit_public', ROOT / 'scripts/audit_public.py')
assert SPEC and SPEC.loader
audit = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(audit)


class PrivacyScan(unittest.TestCase):
    def categories(self, text):
        with tempfile.TemporaryDirectory() as tmp:
            fixture = Path(tmp) / 'fixture.txt'
            fixture.write_text(text)
            return [category for category, _ in audit.scan([fixture], Path(tmp))]

    def test_placeholder_accounts_are_not_personal_paths(self):
        for text in ('plugins_dir: "/home/user/.config/cedar/plugins.d"',
                     'path=u.plant_unit("/home/u/.local/bin/cedar-ai")',
                     '/home/username/Pictures'):
            self.assertNotIn('personal home path', self.categories(text), text)

    def test_a_named_account_is_still_a_personal_path(self):
        self.assertIn('personal home path', self.categories('/home/ethan/.config/cedar'))

    def test_network_and_credentials_are_still_caught(self):
        self.assertIn('private IPv4 endpoint', self.categories('host = 192.168.1.40'))
        self.assertIn('credential signature', self.categories('token ghp_' + 'a' * 36))

    def test_runtime_artifacts_are_reported_by_extension(self):
        with tempfile.TemporaryDirectory() as tmp:
            log = Path(tmp) / 'shell.log'
            log.write_text('anything')
            self.assertIn(('private/runtime artifact', 'shell.log'), audit.scan([log], Path(tmp)))


if __name__ == '__main__':
    unittest.main()
