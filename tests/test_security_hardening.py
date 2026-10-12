"""Regression tests for the 2026-10-12 security findings (Cedar-Shell 1.7)."""
import gzip
import importlib.util
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

spec = importlib.util.spec_from_file_location('cedar_ai', ROOT / 'scripts/cedar_ai.py')
cedar_ai = importlib.util.module_from_spec(spec); spec.loader.exec_module(cedar_ai)


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


class RelayLauncher(unittest.TestCase):
    def agent(self, mode):
        out = cedar_ai.Emitter(); control = cedar_ai.Control(listen=False)
        return cedar_ai.Claude(Path('.'), mode, None, [], 10, out, control)

    def test_read_mode_allows_no_git_command_with_an_output_option(self):
        cmd = self.agent('read').command('x')
        rules = cmd[cmd.index('--allowedTools') + 1]
        for prefix in ('git log', 'git diff', 'git show'):
            self.assertNotIn(prefix, rules)

    def test_systemd_launch_keeps_secret_values_out_of_argv(self):
        calls = []
        args = cedar_ai.argparse.Namespace(socket=None)
        with tempfile.TemporaryDirectory() as tmp, \
             patch.dict(os.environ, {'XDG_RUNTIME_DIR': tmp, 'ANTHROPIC_API_KEY': 'sk-secret', 'CEDAR_AI_LAUNCHER': ''}), \
             patch.object(cedar_ai, 'RUNTIME_ROOT', Path(tmp) / 'cedar-ai'), \
             patch.object(cedar_ai.shutil, 'which', return_value='/usr/bin/systemd-run'), \
             patch.object(cedar_ai.subprocess, 'run', side_effect=lambda argv, **_: calls.append(argv) or cedar_ai.subprocess.CompletedProcess(argv, 0, '', '')), \
             patch('sys.stdout', io.StringIO()):
            cedar_ai.detach(args)
        self.assertIn('--setenv=ANTHROPIC_API_KEY', calls[0])
        self.assertFalse(any('sk-secret' in arg for arg in calls[0]))

    def test_tmp_fallback_refuses_a_symlinked_socket_directory(self):
        with tempfile.TemporaryDirectory() as tmp:
            outer = Path(tmp) / 'cedar-ai-1'; (Path(tmp) / 'elsewhere').mkdir()
            outer.symlink_to(Path(tmp) / 'elsewhere')
            with patch.dict(os.environ, {'XDG_RUNTIME_DIR': ''}), patch.object(cedar_ai, 'RUNTIME_ROOT', outer / 'cedar-ai'):
                with self.assertRaises(SystemExit):
                    cedar_ai.private_runtime_root()

    def test_tmp_fallback_creates_private_directories(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / 'cedar-ai-1' / 'cedar-ai'
            with patch.dict(os.environ, {'XDG_RUNTIME_DIR': ''}), patch.object(cedar_ai, 'RUNTIME_ROOT', root):
                self.assertEqual(cedar_ai.private_runtime_root(), root)
            self.assertEqual(root.parent.stat().st_mode & 0o777, 0o700)
            self.assertEqual(root.stat().st_mode & 0o777, 0o700)


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
