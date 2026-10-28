"""Private fixture installations only; no service, display or shell activation."""
import json
import os
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import lock_bridge_install as bridge


class LockBridgeInstall(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='cedar-bridge-install-')
        self.addCleanup(temporary.cleanup)
        self.base = Path(temporary.name)
        env = patch.dict(os.environ, {'HOME': str(self.base), 'XDG_DATA_HOME': str(self.base / 'data'),
                                     'XDG_CONFIG_HOME': str(self.base / 'config'),
                                     'XDG_STATE_HOME': str(self.base / 'state'),
                                     'CEDAR_INJECT_FAILURE': ''})
        env.start(); self.addCleanup(env.stop)
        self.source = self.base / 'source'
        (self.source / 'scripts/lock-shim').mkdir(parents=True)
        (self.source / 'scripts/lock_bridge.py').write_text('print("fixture bridge")\n')
        (self.source / 'scripts/lock-shim/omarchy-shell').write_text('#!/bin/sh\nexec python3 "$(dirname "$0")/../lock_bridge.py" "$@"\n')
        self.paths = bridge.locations()

    def test_private_copies_and_monitor_only_environment_without_activation(self):
        with patch.object(bridge.d, 'command', side_effect=AssertionError('No commands may be activated')):
            result = bridge.install(self.source)
        self.assertFalse(result['activated'])
        self.assertEqual(self.paths['bridge'].read_bytes(), (self.source / 'scripts/lock_bridge.py').read_bytes())
        self.assertEqual(self.paths['shim'].stat().st_mode & 0o777, 0o755)
        self.assertEqual(self.paths['bridge'].parent.stat().st_mode & 0o777, 0o700)
        content = self.paths['dropin'].read_text()
        self.assertIn('[Service]\nEnvironment="PATH=' + str(self.paths['shim'].parent), content)
        self.assertIn(':/usr/share/omarchy/bin:/usr/local/bin:/usr/bin"', content)
        self.assertNotIn('ExecStart=', content)
        self.assertFalse((self.base / '.local/bin/omarchy-shell').exists())
        record = json.loads(Path(result['journal']).read_text())
        self.assertEqual(record['action'], 'lock-bridge')
        self.assertEqual(record['stage'], 'commit')
        self.assertEqual({entry['path'] for entry in record['files']}, {str(p) for p in self.paths.values()})

    def test_identical_install_is_idempotent(self):
        first = bridge.install(self.source)
        second = bridge.install(self.source)
        self.assertEqual(second['action'], 'unchanged')
        self.assertEqual(second['journal'], first['journal'])
        self.assertEqual(len(list((bridge.d.paths()['state'] / 'transactions').iterdir())), 1)

    def test_idempotent_install_does_not_ignore_loosened_private_directory(self):
        bridge.install(self.source)
        self.paths['shim'].parent.chmod(0o755)
        with self.assertRaisesRegex(bridge.d.Refused, 'private, user-owned'):
            bridge.install(self.source)
        self.assertEqual(self.paths['shim'].parent.stat().st_mode & 0o777, 0o755)

    def test_restore_removes_only_our_files_and_preserves_neighbor_dropin(self):
        bridge.install(self.source)
        neighbor = self.paths['dropin'].with_name('99-user.conf')
        neighbor.write_text('[Service]\nNice=1\n')
        result = bridge.restore()
        self.assertFalse(result['activated'])
        self.assertTrue(all(not path.exists() for path in self.paths.values()))
        self.assertEqual(neighbor.read_text(), '[Service]\nNice=1\n')

    def test_updated_install_restores_previous_owned_version_then_original_absence(self):
        first = bridge.install(self.source)
        original = self.paths['bridge'].read_bytes()
        (self.source / 'scripts/lock_bridge.py').write_text('print("updated fixture")\n')
        second = bridge.install(self.source)
        self.assertNotEqual(first['journal'], second['journal'])
        bridge.restore()
        self.assertEqual(self.paths['bridge'].read_bytes(), original)
        self.assertEqual(bridge.receipt_journal(self.paths), Path(first['journal']))
        bridge.restore()
        self.assertTrue(all(not path.exists() for path in self.paths.values()))

    def test_unknown_existing_file_is_not_adopted_or_overwritten(self):
        self.paths['dropin'].parent.mkdir(parents=True)
        self.paths['dropin'].write_text('user content')
        with self.assertRaisesRegex(bridge.d.Refused, 'no ownership receipt'):
            bridge.install(self.source)
        self.assertEqual(self.paths['dropin'].read_text(), 'user content')
        self.assertFalse(self.paths['bridge'].exists())

    def test_later_user_edits_refuse_install_and_all_or_nothing_restore(self):
        bridge.install(self.source)
        self.paths['dropin'].write_text('later user edit')
        before = {name: path.read_bytes() for name, path in self.paths.items()}
        for operation in (lambda: bridge.install(self.source), bridge.restore):
            with self.assertRaises(bridge.d.Refused):
                operation()
            self.assertEqual({name: path.read_bytes() for name, path in self.paths.items()}, before)

    def test_symlink_file_and_parent_are_refused(self):
        outside = self.base / 'outside'; outside.mkdir()
        self.paths['bridge'].parent.mkdir(parents=True)
        self.paths['bridge'].symlink_to(outside / 'file')
        with self.assertRaisesRegex(bridge.d.Refused, 'symlink'):
            bridge.install(self.source)
        self.assertFalse((outside / 'file').exists())
        self.paths['bridge'].unlink()
        self.paths['bridge'].parent.rmdir()
        self.paths['bridge'].parent.symlink_to(outside, target_is_directory=True)
        with self.assertRaisesRegex(bridge.d.Refused, 'symlink'):
            bridge.install(self.source)
        self.assertEqual(list(outside.iterdir()), [])

    def test_source_symlink_and_excessive_source_size_are_refused(self):
        source = self.source / 'scripts/lock_bridge.py'
        source.unlink(); source.symlink_to(self.source / 'scripts/lock-shim/omarchy-shell')
        with self.assertRaises(bridge.d.Refused): bridge.install(self.source)
        source.unlink(); source.write_bytes(b'x' * (bridge.MAX_FILE + 1))
        with self.assertRaises(bridge.d.Refused): bridge.install(self.source)
        self.assertFalse(self.paths['receipt'].exists())

    def test_foreign_owned_dropin_parent_is_refused_before_any_write(self):
        parent = self.paths['dropin'].parent
        parent.mkdir(parents=True)
        original = Path.stat
        def foreign_owner(path, *args, **kwargs):
            info = original(path, *args, **kwargs)
            if path == parent: return SimpleNamespace(st_mode=info.st_mode, st_uid=os.getuid() + 1)
            return info
        with patch.object(Path, 'stat', foreign_owner):
            with self.assertRaisesRegex(bridge.d.Refused, 'Unsafe lock bridge parent'):
                bridge.install(self.source)
        self.assertTrue(all(not path.exists() for path in self.paths.values()))

    def test_edit_between_ownership_check_and_backup_is_not_adopted(self):
        bridge.install(self.source)
        (self.source / 'scripts/lock_bridge.py').write_text('print("new fixture")\n')
        original = bridge.d.Transaction.backup
        def edited(transaction, path):
            if path == self.paths['dropin']: path.write_text('concurrent user edit')
            return original(transaction, path)
        with patch.object(bridge.d.Transaction, 'backup', edited):
            with self.assertRaisesRegex(bridge.d.Refused, 'changed during preparation'):
                bridge.install(self.source)
        self.assertEqual(self.paths['dropin'].read_text(), 'concurrent user edit')
        self.assertIn('fixture bridge', self.paths['bridge'].read_text())

    def test_mid_apply_failure_restores_before_any_activation(self):
        original = bridge.d.Transaction.apply_file
        def fail_dropin(transaction, entry, data, mode=0o600):
            if entry['path'] == str(self.paths['dropin']): raise OSError('fixture write failure')
            return original(transaction, entry, data, mode)
        with patch.object(bridge.d.Transaction, 'apply_file', fail_dropin):
            with self.assertRaisesRegex(OSError, 'fixture write failure'):
                bridge.install(self.source)
        self.assertTrue(all(not path.exists() for path in self.paths.values()))

    def test_commit_failure_rolls_back_receipt_as_well_as_payload(self):
        with patch.dict(os.environ, {'CEDAR_INJECT_FAILURE': 'commit'}):
            with self.assertRaises(OSError): bridge.install(self.source)
        self.assertTrue(all(not path.exists() for path in self.paths.values()))

    def test_receipt_cannot_point_to_unrelated_recovery_journal(self):
        bridge.install(self.source)
        receipt = json.loads(self.paths['receipt'].read_text())
        receipt['journal'] = '../../unrelated/journal.json'
        self.paths['receipt'].write_text(json.dumps(receipt))
        with self.assertRaisesRegex(bridge.d.Refused, 'leaves its owned location'):
            bridge.restore()
        self.assertTrue(self.paths['bridge'].exists())

    def test_systemd_environment_escaping_and_invalid_path_components(self):
        self.assertEqual(bridge.systemd_quote('PATH=/home/space % "quote"/bin'), '"PATH=/home/space %% \\"quote\\"/bin"')
        with self.assertRaises(bridge.d.Refused): bridge.systemd_quote('path\nInjected=yes')
        with self.assertRaises(bridge.d.Refused): bridge.dropin_content(Path('/home/colon:path/omarchy-shell'))


if __name__ == '__main__':
    unittest.main()
