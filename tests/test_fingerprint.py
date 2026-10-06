"""Fingerprint availability is read from PAM and fprintd, never assumed."""
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('fingerprint', ROOT/'scripts/fingerprint.py')
fp = importlib.util.module_from_spec(spec); spec.loader.exec_module(fp)
LISTING = 'found 1 devices\nDevice at /net/reactivated/Fprint/Device/0\nFingerprints for user outlaw on Goodix (press):\n - #0: right-index-finger\n - #1: left-thumb\n'


class Fingerprint(unittest.TestCase):
    def test_counts_enrolled_prints(self):
        self.assertEqual(fp.fingers(LISTING), 2)
        self.assertEqual(fp.fingers('found 1 devices\nNo fingerprints enrolled\n'), 0)
    def test_requires_pam_service_and_enrolled_print(self):
        with tempfile.TemporaryDirectory() as pam:
            self.assertFalse(fp.status(pam, 'someone')['configured'])
            (Path(pam)/fp.SERVICE).write_text('auth required pam_fprintd.so\n')
            with patch.object(fp.shutil, 'which', return_value='/usr/bin/fprintd-list'):
                with patch.object(fp.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, LISTING, '')) as run:
                    result = fp.status(pam, 'someone', run=run)
                    self.assertTrue(result['configured']); self.assertEqual(result['fingers'], 2)
                    self.assertEqual(run.call_args[0][0], ['fprintd-list', 'someone'])
                with patch.object(fp.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, 'found 1 devices\n', '')) as run:
                    self.assertFalse(fp.status(pam, 'someone', run=run)['configured'])
                with patch.object(fp.subprocess, 'run', side_effect=subprocess.TimeoutExpired('fprintd-list', 8)) as run:
                    self.assertFalse(fp.status(pam, 'someone', run=run)['configured'])
            with patch.object(fp.shutil, 'which', return_value=None):
                self.assertIn('fprintd', fp.status(pam, 'someone')['reason'])


if __name__ == '__main__':
    unittest.main()
