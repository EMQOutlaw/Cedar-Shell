"""The keybind set: one definition, two rendered syntaxes, the approved layout."""
import re
import os
import json
import tempfile
from types import SimpleNamespace
from unittest.mock import patch
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import keybinds  # noqa: E402

APPROVED = {
    # combination: (part of the Lua action, part of the conf action)
    'SUPER + SPACE': ('menu toggle apps', 'menu toggle apps'),
    'SUPER + T': ('launch("terminal")', '$cedarLaunch terminal'),
    'SUPER + W': ('launch("browser")', '$cedarLaunch browser'),
    'SUPER + E': ('launch("files")', '$cedarLaunch files'),
    'SUPER + C': ('clipboard("copy")', 'clipboard copy'),
    'SUPER + X': ('clipboard("cut")', 'clipboard cut'),
    'SUPER + V': ('clipboard("paste")', 'clipboard paste'),
    'SUPER + SHIFT + V': ('canopy flip clipboard', 'canopy flip clipboard'),
    'SUPER + Q': ('window.close()', 'killactive'),
    'SUPER + F': ('fullscreen', 'fullscreen, 0'),
    'SUPER + ALT + SPACE': ('float({ action = "toggle" })', 'togglefloating'),
    'SUPER + LEFT': ('focus({ direction = "l" })', 'movefocus, l'),
    'SUPER + SHIFT + RIGHT': ('window.move({ direction = "r" })', 'movewindow, r'),
    'SUPER + MOUSE:272': ('window.drag()', 'movewindow'),
    'SUPER + MOUSE:273': ('window.resize()', 'resizewindow'),
    'SUPER + 1': ('workspace = "1"', 'workspace, 1'),
    'SUPER + 9': ('workspace = "9"', 'workspace, 9'),
    'SUPER + 0': ('workspace = "10"', 'workspace, 10'),
    'SUPER + SHIFT + 1': ('window.move({ workspace = "1" })', 'movetoworkspace, 1'),
    'SUPER + SHIFT + 0': ('window.move({ workspace = "10" })', 'movetoworkspace, 10'),
    'SUPER + S': ('toggle_special("special")', 'togglespecialworkspace, special'),
    'SUPER + ALT + S': ('workspace = "special:special", follow = false', 'movetoworkspacesilent, special:special'),
    'SUPER + L': ('lock lock', 'lock lock'),
    'SUPER + ESCAPE': ('power toggle', 'power toggle'),
    'SUPER + P': ('menu toggle capture', 'menu toggle capture'),
    'SUPER + K': ('canopy flip keybinds', 'canopy flip keybinds'),
    'SUPER + COMMA': ('settings toggle', 'settings toggle'),
    'PRINT': ('menu toggle capture', 'menu toggle capture'),
    'XF86AUDIORAISEVOLUME': ('osd volume 5', 'osd volume 5'),
    'XF86MONBRIGHTNESSDOWN': ('osd brightness -5', 'osd brightness -5'),
}
RETIRED = ['SUPER + SUPER_L', 'SUPER + SHIFT + SPACE', 'SUPER + N', 'SUPER + SHIFT + N', 'CTRL + ALT + DELETE', 'SUPER + ALT + L', 'SUPER + SHIFT + L',
           'SUPER + ALT + P', 'SUPER + G', 'SUPER + SHIFT + P', 'SUPER + SHIFT + F', 'SUPER + SHIFT + H', 'SUPER + TAB', 'SUPER + ALT + V',
           'SUPER + ALT + 1', 'SUPER + CTRL + 1', 'SUPER + CTRL + ALT + 1', 'SUPER + M', 'SUPER + D', 'SUPER + R', 'SUPER + Z', 'SUPER + ALT + F',
           'ALT + TAB', 'SUPER + SHIFT + A', 'SUPER + SHIFT + S', 'SUPER + SHIFT + C']


class Definition(unittest.TestCase):
    spec = keybinds.load()

    def combos(self):
        return {keybinds.normalize(r['keys']): r for r in keybinds.rows(self.spec)}

    def test_rendered_files_match_the_definition(self):
        self.assertEqual(keybinds.check(self.spec), [], 'run scripts/keybinds.py --write')

    def test_no_combination_is_bound_twice(self):
        self.assertEqual(keybinds.duplicates(self.spec), [])
        seen = [(keybinds.normalize(r['keys']), 'release' in r['flags']) for r in keybinds.rows(self.spec)]
        self.assertEqual(len(seen), len(set(seen)), 'every key combination and event appears once')

    def test_groups_are_the_reference_sections(self):
        self.assertEqual([g['id'] for g in self.spec['groups']], ['applications', 'dictation', 'windows', 'workspaces', 'scratchpad', 'capture', 'session', 'media'])
        self.assertEqual([g['title'] for g in self.spec['groups']][-1], 'Media and hardware')

    def test_hold_to_talk_has_nonrepeating_press_and_release_actions(self):
        rows = [r for r in keybinds.rows(self.spec) if r['keys'] == 'F9']
        self.assertEqual([r['flags'] for r in rows], [[], ['release']])
        self.assertEqual([r['lua'] for r in rows], ['ipc("dictation start")', 'ipc("dictation stop")'])
        lua = keybinds.render_lua(self.spec)
        self.assertIn('bind("F9", ipc("dictation start"), "' + rows[0]['description'] + '")', lua)
        self.assertIn('bind("F9", ipc("dictation stop"), "' + rows[1]['description'] + '", { release = true })', lua)
        conf = keybinds.render_conf(self.spec)
        bindings = [line for line in conf.splitlines() if ', F9,' in line]
        self.assertEqual(bindings, [
            'bindd = , F9, ' + rows[0]['description'] + ', exec, $cedarShell dictation start',
            'bindrd = , F9, ' + rows[1]['description'] + ', exec, $cedarShell dictation stop',
        ])
        self.assertEqual(conf.splitlines().count('unbind = , F9'), 1)

    def test_duplicate_detection_distinguishes_press_and_release(self):
        entry = {'keys': ['F9'], 'description': 'Talk', 'lua': 'start', 'conf': 'start',
                 'release': {'lua': 'stop', 'conf': 'stop'}}
        spec = {'groups': [{'id': 'dictation', 'entries': [entry]}]}
        self.assertEqual(keybinds.duplicates(spec), [])
        for flags in ([], ['release']):
            with self.subTest(flags=flags):
                duplicate = {**entry, 'keys': ['f9'], 'release': None, 'flags': flags}
                spec['groups'][0]['entries'] = [entry, duplicate]
                self.assertEqual(keybinds.duplicates(spec), ['F9'])

    def test_the_approved_set_is_present_with_its_actions(self):
        combos = self.combos()
        for combo, (lua, conf) in APPROVED.items():
            self.assertIn(combo, combos, combo)
            self.assertIn(lua, combos[combo]['lua'], combo)
            self.assertIn(conf, combos[combo]['conf'], combo)

    def test_zero_is_workspace_ten_and_numbers_cover_one_to_ten(self):
        combos = self.combos()
        for n in range(1, 11):
            key = str(n % 10)
            self.assertIn('workspace = "' + str(n) + '"', combos['SUPER + ' + key]['lua'])
            self.assertIn('workspace = "' + str(n) + '"', combos['SUPER + SHIFT + ' + key]['lua'])
            self.assertNotIn('follow = false', combos['SUPER + SHIFT + ' + key]['lua'])
            self.assertEqual(combos['SUPER + SHIFT + ' + key]['conf'], 'movetoworkspace, ' + str(n))
        self.assertNotIn('follow = false', combos['SUPER + SHIFT + 0']['lua'])

    def test_one_scratchpad(self):
        combos = self.combos()
        self.assertEqual(self.spec['scratchpad'], 'special')
        self.assertIn('"special"', combos['SUPER + S']['lua'])
        self.assertIn('special:special', combos['SUPER + ALT + S']['lua'])
        self.assertIn('follow = false', combos['SUPER + ALT + S']['lua'])

    def test_retired_combinations_are_gone(self):
        combos = self.combos()
        for combo in RETIRED:
            self.assertNotIn(combo, combos, combo)

    def test_flags_and_text_are_renderable(self):
        for row in keybinds.rows(self.spec):
            self.assertTrue(set(row['flags']) <= set(keybinds.FLAGS), row['keys'])
            self.assertTrue(all(32 <= ord(c) < 127 for c in row['description'] + row['keys']), row['keys'])
            self.assertNotIn('#', row['description'])
        for row in keybinds.rows(self.spec):
            if 'mouse' in row['flags']:
                self.assertTrue(row['keys'].endswith(('mouse:272', 'mouse:273')))

    def test_both_syntaxes_bind_the_same_keys(self):
        lua = (ROOT / 'themes/keybinds.lua').read_text()
        conf = (ROOT / 'themes/keybinds.conf').read_text()
        lua_keys = {keybinds.normalize(m.group(1)) for m in re.finditer(r'^bind\("([^"]+)"', lua, re.M)}
        conf_keys = {keybinds.normalize(' + '.join(m.group(1).split() + [m.group(2).strip()])) for m in re.finditer(r'^bind[a-z]*\s*=\s*([^,]*),\s*([^,]+),', conf, re.M)}
        expected = {keybinds.normalize(r['keys']) for r in keybinds.rows(self.spec)}
        self.assertEqual(lua_keys, expected)
        self.assertEqual(conf_keys, expected)
        unbinds = {keybinds.normalize(' + '.join(m.group(1).split() + [m.group(2).strip()])) for m in re.finditer(r'^unbind\s*=\s*([^,]*),\s*(.+)$', conf, re.M)}
        self.assertEqual(unbinds, expected, 'every conf bind is preceded by its unbind')



class Clipboard(unittest.TestCase):
    def setUp(self):
        import desktop_runtime
        self.runtime = desktop_runtime
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.config = Path(self.tmp.name)
        env = patch.dict(os.environ, {'XDG_CONFIG_HOME': self.tmp.name})
        env.start(); self.addCleanup(env.stop)

    def send(self, action, app, lua=True):
        if lua:
            (self.config / 'hypr').mkdir(exist_ok=True)
            (self.config / 'hypr/hyprland.lua').touch()
        with patch.object(self.runtime, 'hyprctl', return_value={'class': app}), \
             patch.object(self.runtime, 'configured_argv', return_value=[]), \
             patch.object(self.runtime.subprocess, 'run', return_value=SimpleNamespace(returncode=0, stdout='ok', stderr='')) as run:
            result = self.runtime.clipboard(action)
            return result, run.call_args_list

    def test_terminal_copy_and_paste_use_shift_and_release(self):
        for app in ('Alacritty', 'foot', 'com.mitchellh.ghostty', 'org.wezfurlong.wezterm'):
            for action, key in [('copy', 'c'), ('paste', 'v')]:
                result, calls = self.send(action, app)
                self.assertTrue(result)
                command = calls[0].args[0][-1]
                self.assertIn('mods = "CTRL SHIFT"', command)
                self.assertIn('key = "' + key + '"', command)
                self.assertIn('state = "down"', command)
                self.assertIn('state = "up"', command)
                self.assertIn('hl.timer', command)

    def test_terminal_cut_sends_nothing(self):
        result, calls = self.send('cut', 'kitty')
        self.assertFalse(result)
        self.assertEqual(calls, [])

    def test_normal_apps_and_legacy_hyprland(self):
        result, calls = self.send('paste', 'browser', lua=False)
        self.assertTrue(result)
        self.assertEqual(calls[0].args[0], ['hyprctl', 'dispatch', 'sendshortcut', 'CTRL, v,'])

    def test_failed_window_query_never_sends_an_interrupt(self):
        with patch.object(self.runtime, 'hyprctl', side_effect=RuntimeError('unavailable')), \
             patch.object(self.runtime.subprocess, 'run') as run:
            with self.assertRaises(RuntimeError): self.runtime.clipboard('copy')
            run.assert_not_called()

    def test_dispatch_errors_are_reported(self):
        with patch.object(self.runtime, 'hyprctl', return_value={'class': 'kitty'}), \
             patch.object(self.runtime.subprocess, 'run', return_value=SimpleNamespace(returncode=1, stdout='', stderr='error')):
            with self.assertRaisesRegex(RuntimeError, 'did not send'): self.runtime.clipboard('paste')

if __name__ == '__main__':
    unittest.main()
