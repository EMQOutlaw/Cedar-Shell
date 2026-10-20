import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import settings_theme as theme
from theming import tokens

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

    def test_every_bundled_theme_previews_applies_and_restores(self):
        items = theme.runtime.themes()
        expected = {'cedar', 'catppuccin-mocha', 'catppuccin-latte',
                    'decay-green', 'rose-pine', 'tokyo-night', 'nord'}
        self.assertTrue(expected <= {item['name'] for item in items})
        self.assertEqual(len(items), 17)
        for item in items:
            with self.subTest(theme=item['name']):
                candidate = theme.preview(item['name'])
                self.assertFalse(theme.target().exists())
                self.assertEqual(candidate['palette'], item['palette'])
                theme.apply(candidate)
                saved = json.loads(theme.target().read_text())
                self.assertEqual(saved['mode'], item['mode'])
                self.assertEqual(saved['colors'], candidate['colors'])
                theme.restore()
                self.assertFalse(theme.target().exists())
                # The non-Settings command uses the same resolver and mode.
                theme.runtime.set_theme(item['name'])
                self.assertEqual(json.loads(theme.target().read_text()), saved)
                theme.target().unlink()

    def test_bundled_colors_are_complete_readable_and_compile_for_applications(self):
        for item in theme.runtime.themes():
            with self.subTest(theme=item['name']):
                colors = item['palette']
                self.assertEqual(set(colors), set(theme.runtime.COLORS))
                theme.runtime.validate_palette({'colors': colors, 'mode': item['mode']})
                for foreground in ('text', 'muted'):
                    for surface in ('background', 'surface', 'elevated'):
                        self.assertGreaterEqual(tokens.contrast(colors[foreground], colors[surface]), 4.5)
                self.assertGreaterEqual(tokens.contrast(colors['ink'], colors['paper']), 4.5)
                compiled = tokens.compile_theme(tokens.preset(item['name']))
                self.assertEqual(compiled['mode'], item['mode'])
                for key in ('background', 'surface', 'elevated', 'text', 'muted', 'violet'):
                    self.assertEqual(compiled['colors'][key].lower(), colors[key].lower())

    def test_personal_palette_overrides_builtin_without_duplicate_and_restores(self):
        path = theme.runtime.config()/'themes/catppuccin-latte.json'
        path.parent.mkdir(parents=True)
        path.write_text(json.dumps({'name': 'My Latte', 'mode': 'light',
                                    'colors': {'blue': '#123456', 'paper': '#ffffff'}}))
        items = theme.runtime.themes()
        self.assertEqual(sum(item['name']=='catppuccin-latte' for item in items), 1)
        candidate = theme.preview('catppuccin-latte')
        self.assertEqual(candidate['palette']['blue'], '#123456')
        theme.apply(candidate)
        self.assertEqual(json.loads(theme.target().read_text())['mode'], 'light')
        theme.restore()
        self.assertTrue(path.exists())

    def test_invalid_personal_palettes_do_not_hide_builtins_or_default(self):
        directory = theme.runtime.config()/'themes'
        directory.mkdir(parents=True)
        for content in ('[]', '{bad', '{"colors":{"blue":"red"}}',
                        '{"mode":"sepia","colors":{"green":"#abcdef"}}'):
            (directory/'nord.json').write_text(content)
            self.assertEqual(theme.preview('nord')['palette']['background'], '#2e3440')
        (directory/'cedar.json').write_text('{"colors":{"green":"#123456"}}')
        self.assertEqual(theme.preview('cedar')['colors'], {})
        self.assertFalse(theme.target().exists())

    def test_light_theme_accent_keeps_mode_and_resets_to_default(self):
        candidate = theme.preview('catppuccin-latte', 'teal')
        theme.apply(candidate)
        saved = json.loads(theme.target().read_text())
        self.assertEqual(saved['mode'], 'light')
        self.assertEqual(saved['colors']['green'], candidate['palette']['teal'])
        theme.apply(theme.preview('cedar'))
        self.assertEqual(json.loads(theme.target().read_text()),
                         {'name': 'cedar', 'mode': 'dark', 'colors': {}})
        theme.restore()
        self.assertEqual(json.loads(theme.target().read_text()), saved)
