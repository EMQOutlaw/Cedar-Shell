"""IPC and prompt-reply hardening: the helper only writes where mktemp can point."""
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('menu_reply', ROOT/'scripts/menu_reply.py')
reply = importlib.util.module_from_spec(spec); spec.loader.exec_module(reply)


class MenuReply(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='cedar reply ')
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.selection = self.base/'selection'
        self.selection.write_text('')
        self.done = self.base/'done'

    def test_writes_selection_and_creates_marker(self):
        reply.reply({'selectionFile': str(self.selection), 'doneFile': str(self.done), 'selection': 'Two\tsecond'})
        self.assertEqual(self.selection.read_text(), 'Two\tsecond\n')
        self.assertTrue(self.done.is_file())
        self.assertEqual(oct(self.done.stat().st_mode & 0o777), '0o600')

    def test_cancel_marks_done_without_selection(self):
        reply.reply({'selectionFile': str(self.selection), 'doneFile': str(self.done), 'selection': None})
        self.assertEqual(self.selection.read_text(), '')
        self.assertTrue(self.done.exists())

    def test_existing_marker_is_never_replaced(self):
        self.done.write_text('someone else')
        with self.assertRaises(FileExistsError):
            reply.reply({'selectionFile': str(self.selection), 'doneFile': str(self.done), 'selection': 'x'})
        self.assertEqual(self.done.read_text(), 'someone else')

    def test_selection_symlink_is_not_followed(self):
        target = self.base/'target'; target.write_text('keep')
        link = self.base/'link'; link.symlink_to(target)
        with self.assertRaises(OSError):
            reply.reply({'selectionFile': str(link), 'doneFile': str(self.done), 'selection': 'x'})
        self.assertEqual(target.read_text(), 'keep')
        self.assertFalse(self.done.exists())

    def test_missing_selection_file_is_refused(self):
        with self.assertRaises(OSError):
            reply.reply({'selectionFile': str(self.base/'absent'), 'doneFile': str(self.done), 'selection': 'x'})
        self.assertFalse(self.done.exists())

    def test_paths_outside_temporary_directories_are_refused(self):
        with tempfile.TemporaryDirectory(dir=Path.home()) as home:
            outside = Path(home)/'selection'; outside.write_text('')
            for request in [
                {'selectionFile': str(outside), 'doneFile': str(self.done), 'selection': 'x'},
                {'selectionFile': str(self.selection), 'doneFile': str(Path(home)/'done'), 'selection': 'x'},
                {'selectionFile': 'relative', 'doneFile': str(self.done), 'selection': 'x'},
                {'selectionFile': str(self.selection), 'doneFile': str(self.done)+'\n', 'selection': 'x'},
            ]:
                with self.assertRaises(ValueError):
                    reply.reply(request)
            self.assertEqual(outside.read_text(), '')
        self.assertFalse(self.done.exists())

    def test_oversized_selection_is_refused(self):
        with self.assertRaises(ValueError):
            reply.reply({'selectionFile': str(self.selection), 'doneFile': str(self.done), 'selection': 'x'*70000})
        self.assertFalse(self.done.exists())

    def test_command_line_protocol(self):
        request = json.dumps({'selectionFile': str(self.selection), 'doneFile': str(self.done), 'selection': 'One'})
        result = subprocess.run([sys.executable, str(ROOT/'scripts/menu_reply.py')], input=request+'\n', capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(json.loads(result.stdout)['ok'])
        bad = subprocess.run([sys.executable, str(ROOT/'scripts/menu_reply.py')], input='not json\n', capture_output=True, text=True, timeout=10)
        self.assertEqual(bad.returncode, 1)
        self.assertFalse(json.loads(bad.stdout)['ok'])


class IpcPolicy(unittest.TestCase):
    """Static guarantees about the shell's IPC surface; runtime behavior is covered offscreen."""
    def test_settings_ipc_routes_through_policy(self):
        shell = (ROOT/'shell.qml').read_text()
        self.assertIn('return Config.ipcSet(key, value);', shell)
        self.assertIn('return Config.ipcGet(key);', shell)
        self.assertNotIn('Config.set(key, typeof current', shell)

    def test_protected_settings_cover_commands_network_location_and_lock(self):
        config = (ROOT/'Config.qml').read_text()
        protected = set(re.findall(r'"(\w+)"', re.search(r'ipcProtected: \[(.*?)\]', config).group(1)))
        for key in ['terminal', 'browser', 'editor', 'files', 'applicationTargets', 'localOnly', 'weatherEnabled', 'weatherAutomatic', 'remoteArtwork', 'latitude', 'longitude', 'idleLockSeconds', 'lockPrivacy', 'clipboardHistory', 'forestTrails', 'whisperLedger']:
            self.assertIn(key, protected)
        saved = set(re.findall(r'property (?:var|string|bool|int|real) (\w+):', config.split('JsonAdapter {',1)[1]))
        self.assertTrue(protected <= saved, protected - saved)

    def test_prompt_replies_never_build_a_shell_string(self):
        go = (ROOT/'services/Go.qml').read_text()
        self.assertNotIn('["bash", "-c"', go)
        self.assertIn('script: "scripts/menu_reply.py"', go)

    def test_always_mapped_surfaces_use_stepped_breath(self):
        for path in ['components/core/CoreSurface.qml', 'components/ArcGauge.qml', 'modules/TrailwatchView.qml']:
            text = (ROOT/path).read_text()
            self.assertIn('Breath {', text, path)
            self.assertNotIn('loops: Animation.Infinite', text, path)
        for path in ['components/CedarAtmosphere.qml', 'components/StationCore.qml']:
            self.assertIn('Motion.active', (ROOT/path).read_text(), path)


if __name__ == '__main__':
    unittest.main()
