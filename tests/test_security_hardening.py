"""Regression tests for the 2026-10-12 security findings (Cedar-Shell 1.7)."""
import gzip
import io
import os
from pathlib import Path
import sys
import tarfile
import tempfile
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / 'scripts'))
import distribution as d  # noqa: E402
import trailwatch  # noqa: E402
from installer.engine import backup as backup_module  # noqa: E402
from installer.migration import intent  # noqa: E402


class Updater(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def test_option_like_archive_name_never_reaches_openssl_and_help_is_not_verification(self):
        (self.root / '-help').write_bytes(b'not a release')
        seen = []
        cwd = os.getcwd(); os.chdir(self.root); self.addCleanup(os.chdir, cwd)
        with patch.object(d.shutil, 'which', return_value='/usr/bin/openssl'), \
             patch.object(d, 'command', side_effect=lambda argv, **_: seen.append(argv) or 'usage: dgst ...'), \
             patch.object(d, 'safe_extract') as extract:
            with self.assertRaises(d.Refused):
                d.update(Path('./-help'), Path('./-sig'), Path('./-key'))
        extract.assert_not_called()
        self.assertTrue(all(Path(arg).is_absolute() for arg in seen[0][4:7:2] + seen[0][-1:]))

    def test_extraction_reads_the_verified_snapshot_not_the_original_path(self):
        archive = self.root / 'release.tar.gz'; archive.write_bytes(b'signed bytes')
        def swap(argv, **_):
            archive.write_bytes(b'replaced after verification')
            return 'Verified OK\n'
        extracted = []
        with patch.object(d.shutil, 'which', return_value='/usr/bin/openssl'), \
             patch.object(d, 'command', side_effect=swap), \
             patch.object(d, 'safe_extract', side_effect=lambda src, dst: extracted.append(Path(src).read_bytes()) or (_ for _ in ()).throw(d.Refused('stop'))):
            with self.assertRaises(d.Refused):
                d.update(archive, self.root / 'sig', self.root / 'key')
        self.assertEqual(extracted, [b'signed bytes'])

    def test_extraction_stops_at_the_decompressed_budget(self):
        archive = self.root / 'big.tar.gz'
        with tarfile.open(archive, 'w:gz') as tar:
            info = tarfile.TarInfo('cedar-shell/zeros'); info.size = 4 * 1024 * 1024
            tar.addfile(info, io.BytesIO(bytes(info.size)))
        with patch.object(d, 'ARCHIVE_STREAM', 1024 * 1024), self.assertRaises(d.Refused):
            d.safe_extract(archive, self.root / 'out')

    def test_member_limit_applies_while_reading_headers(self):
        archive = self.root / 'many.tar.gz'
        with tarfile.open(archive, 'w:gz') as tar:
            for n in range(6):
                tar.addfile(tarfile.TarInfo(f'cedar-shell/{n}'), io.BytesIO(b''))
        with patch.object(d, 'ARCHIVE_MEMBERS', 5), self.assertRaises(d.Refused):
            d.safe_extract(archive, self.root / 'out')


class Reminders(unittest.TestCase):
    def test_message_symlinks_are_not_followed(self):
        with tempfile.TemporaryDirectory() as tmp:
            secret = Path(tmp) / 'secret'; secret.write_text('private contents')
            link = Path(tmp) / 'omarchy-reminder-x.message'; link.symlink_to(secret)
            self.assertEqual(trailwatch.reminder_title(link), '')
            plain = Path(tmp) / 'omarchy-reminder-y.message'; plain.write_text('Stretch\n')
            self.assertEqual(trailwatch.reminder_title(plain), 'Stretch')

    def test_shared_tmp_is_never_read_without_a_runtime_dir(self):
        timers = '[{"unit": "omarchy-reminder-a.timer", "next": %d}]' % ((time.time() + 3600) * 1e6)
        with patch.dict(os.environ, {}, clear=False), patch.object(trailwatch, 'omarchy', return_value=True), \
             patch.object(trailwatch, 'command', return_value=timers), patch.object(trailwatch, 'reminder_title') as read:
            os.environ.pop('XDG_RUNTIME_DIR', None)
            rows = trailwatch.reminders()
        read.assert_not_called()
        self.assertEqual([r['title'] for r in rows], ['Reminder'])


class RestoreScript(unittest.TestCase):
    def test_copy_paths_are_literal_shell_words(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp) / 'home'; home.mkdir()
            backup = backup_module.Backup(home / 'backups', home, '1.0', '1.0', stamp='2026-10-12T000000')
            backup.create({'id': 'hyprland'}, {}, services={}, packages={})
            backup.manifest['files'].append({'path': str(home / 'x.conf'), 'before': {'type': 'file'},
                                             'copy': 'files/$(touch pwned)`id`"q.conf'})
            backup.write_restore_script()
            line = next(l for l in (backup.root / 'restore.sh').read_text().splitlines() if l.startswith('mkdir'))
            self.assertIn('"$here"/\'files/$(touch pwned)`id`"q.conf\'', line)


class MonitorBlocks(unittest.TestCase):
    def test_unclosed_blocks_scan_in_linear_time(self):
        started = time.monotonic()
        self.assertEqual(intent.parse_monitors('monitorv2 {\n' * 40000, 'conf'), [])
        self.assertLess(time.monotonic() - started, 2)

    def test_closed_block_still_parses(self):
        rows = intent.parse_monitors('monitorv2 {\n  output = DP-2\n  scale = 2\n}\n', 'conf')
        self.assertEqual((rows[0]['output'], rows[0]['scale']), ('DP-2', '2'))


if __name__ == '__main__':
    unittest.main()
