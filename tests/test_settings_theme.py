import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import settings_theme as theme

class ThemeTransactions(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        p = Path(self.tmp.name)
        self.env = patch.dict(os.environ, XDG_CONFIG_HOME=str(p/'config'), XDG_STATE_HOME=str(p/'state'))
        self.env.start(); self.addCleanup(self.env.stop)

    def test_preview_does_not_write_and_apply_restores_absence(self):
        candidate = theme.preview('cedar', 'teal')
        self.assertFalse(theme.target().exists())
        theme.apply(candidate)
        self.assertTrue(theme.can_restore())
        self.assertEqual(json.loads(theme.target().read_text())['colors']['green'], candidate['palette']['teal'])
        theme.restore()
        self.assertFalse(theme.target().exists())

    def test_restores_exact_previous_bytes(self):
        before = b'{ "name": "cedar", "colors": {} }\n'
        theme.target().parent.mkdir(parents=True)
        theme.target().write_bytes(before)
        theme.apply(theme.preview('cedar', 'amber'))
        theme.restore()
        self.assertEqual(theme.target().read_bytes(), before)

    def test_external_changes_block_apply_and_restore(self):
        candidate = theme.preview('cedar')
        theme.target().parent.mkdir(parents=True)
        external = b'{"name":"cedar","colors":{}}'
        theme.target().write_bytes(external)
        with self.assertRaisesRegex(ValueError, 'outside'): theme.apply(candidate)
        theme.apply(theme.preview('cedar'))
        theme.target().write_bytes(external)
        with self.assertRaisesRegex(ValueError, 'outside'): theme.restore()
        self.assertEqual(theme.target().read_bytes(), external)

    def test_uninstalled_theme_and_invalid_accent_refused(self):
        with self.assertRaises(ValueError): theme.preview('../other')
        with self.assertRaises(ValueError): theme.preview('cedar', '#ffffff')

    def test_failed_write_preserves_existing_undo_point(self):
        theme.apply(theme.preview('cedar', 'teal'))
        previous = theme.target().read_bytes()
        undo = theme.journal().read_bytes()
        atomic = theme.runtime.atomic
        def fail_target(path, data):
            if path == theme.target(): raise OSError('disk full')
            return atomic(path, data)
        with patch.object(theme.runtime, 'atomic', side_effect=fail_target):
            with self.assertRaises(OSError): theme.apply(theme.preview('cedar', 'amber'))
        self.assertEqual(theme.target().read_bytes(), previous)
        self.assertEqual(theme.journal().read_bytes(), undo)
        theme.restore()
        self.assertFalse(theme.target().exists())
