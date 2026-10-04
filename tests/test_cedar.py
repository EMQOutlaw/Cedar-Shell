"""Meaningful regression checks: readable colors, parsers and theme lifetime."""
from pathlib import Path
import importlib.util
import json
import os
import re
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]

def module(name, path):
    spec = importlib.util.spec_from_file_location(name, ROOT/path)
    obj = importlib.util.module_from_spec(spec); spec.loader.exec_module(obj); return obj

telemetry = module('telemetry', 'scripts/telemetry.py')
sync = module('theme_sync', 'scripts/theme-sync.py')
plugins = module('plugins', 'scripts/plugins.py')

class Palette(unittest.TestCase):
    def test_text_on_worst_case_glass(self):
        colors = dict(re.findall(r'property color (\w+): "(#[0-9A-Fa-f]{6})"', (ROOT/'Theme.qml').read_text()))
        def rgb(c): return [int(c[i:i+2],16)/255 for i in (1,3,5)]
        def lum(c): return sum(v*k for v,k in zip([x/12.92 if x <= .04045 else ((x+.055)/1.055)**2.4 for x in c], [.2126,.7152,.0722]))
        # 88% dark glass composited over pure white: worst-case light wallpaper.
        bg = lum([x*.88 + .12 for x in rgb(colors['background'])])
        for key in ['text','muted','green','teal','amber','ember']:
            ratio = (lum(rgb(colors[key]))+.05)/(bg+.05)
            self.assertGreaterEqual(ratio,4.5, (key,ratio))
    def test_only_theme_defines_qml_colors(self):
        for path in ROOT.rglob('*.qml'):
            if path.name != 'Theme.qml': self.assertIsNone(re.search(r'#[0-9a-fA-F]{6}',path.read_text()), str(path))
    def test_ansi_has_sixteen_colors(self):
        rows=re.findall(r'^color(\d+) ', (ROOT/'themes/kitty.conf').read_text(), re.M)
        self.assertEqual(list(map(int,rows)),list(range(16)))

class Telemetry(unittest.TestCase):
    def test_sensor_missing_is_not_zero(self):
        with patch.object(telemetry,'run',return_value=''):
            self.assertIsNone(telemetry.temperatures()['temperature'])
    def test_temperature_skips_bad_sensors(self):
        with patch.object(telemetry,'run',return_value=json.dumps({'chip': {'a':{'temp1_input': 42, 'temp1_max':100}, 'b': {'temp2_input': -273}, 'c': {'temp3_input':63}}})):
            self.assertEqual(telemetry.temperatures()['temperature'],63)
    def test_wifi_five_ghz_is_not_cellular_5g(self):
        with patch.object(telemetry,'run',side_effect=['wifi:connected','*:87:5180 MHz']):
            self.assertEqual(telemetry.network()['label'],'WI-FI 5 GHz 87%')
    def test_cellular_5g_requires_modem_evidence(self):
        with patch.object(telemetry,'run',side_effect=['gsm:connected','{"modem-list":["/modem/0"]}',json.dumps({'modem':{'generic':{'state':'connected','access-technologies':['5gnr'], 'signal-quality':{'value':74}}}})]):
            self.assertEqual(telemetry.network()['label'],'5G 74%')
    def test_bad_coordinates(self):
        with self.assertRaises(ValueError): telemetry.weather(200, 0, 'celsius')
    def test_brightness_failure_visible(self):
        with patch.object(telemetry,'run',return_value=''):
            self.assertEqual(telemetry.brightness('',5)['error'],'Brightness change failed')

class ThemeLifecycle(unittest.TestCase):
    def exercise(self, selected, fox=False, normal=True, ready=True, is_locked=False, reconcile_only=False):
        calls=[]; running={'fox':fox,'normal':normal}
        def instances(selector): return [1] if running['fox' if '-c' in selector else 'normal'] else []
        def run(args, **kwargs):
            calls.append(args)
            if 'kill' in args: running['normal']=False
            if 'stop' in args: running['fox']=False
            if '--unit=cedar-shell' in args: running['fox']=True
            return subprocess.CompletedProcess(args,0,'false','')
        def popen(args, **kwargs):
            calls.append(args)
            if args[:2] == ['qs','-n']: running['fox']=True
        with tempfile.TemporaryDirectory() as tmp, patch.object(sync,'RUNTIME',Path(tmp)), patch.object(sync,'LOG_DIR',Path(tmp)), patch.object(sync,'selected',return_value=selected), patch.object(sync,'locked',return_value=is_locked), patch.object(sync,'instances',side_effect=instances), patch.object(sync,'run',side_effect=run), patch.object(sync,'wait_for',side_effect=lambda predicate,seconds=8: predicate() and (ready if running['fox'] else True)), patch.object(sync.subprocess,'Popen',side_effect=popen), patch.dict(os.environ,{'WAYLAND_DISPLAY':'test'}):
            result=sync.sync(reconcile_only=reconcile_only)
        return result,calls
    def test_preview_exists_for_graphical_selector(self):
        self.assertTrue((ROOT/'themes/preview.png').is_file())
        self.assertTrue((ROOT/'themes/backgrounds/field-station.png').is_file())
    def test_other_theme_does_not_start_cedar(self):
        _,calls=self.exercise('tokyo-night')
        self.assertEqual(calls,[])
    def test_enter_handoff(self):
        result,calls=self.exercise('cedar')
        self.assertEqual(result,0)
        self.assertEqual(calls[0][:2],['qs','kill'])
        self.assertEqual(calls[1][0],'systemd-run')
        self.assertEqual(calls[1][-4:],['qs','-n','-c','cedar'])
    def test_leave_restores_normal(self):
        result,calls=self.exercise('tokyo-night',fox=True,normal=False)
        self.assertEqual(result,0)
        self.assertIn(['qs','-c','cedar','ipc','call','shell','stop'],calls)
        self.assertTrue(any(c[0] == 'systemd-run' and c[-1] == 'omarchy-launch-shell' for c in calls))
    def test_repeat_selection_idempotent(self):
        _,calls=self.exercise('cedar',fox=True,normal=False)
        self.assertEqual(calls,[])
    def test_existing_cedar_removes_overlapping_normal_shell(self):
        result,calls=self.exercise('cedar',fox=True,normal=True)
        self.assertEqual(result,0)
        self.assertEqual(len(calls),1)
        self.assertEqual(calls[0][:2],['qs','kill'])
        self.assertEqual(calls[0][-1],str(sync.OMARCHY))
    def test_guard_never_launches_a_missing_shell(self):
        for theme,fox,normal in [('cedar',False,True),('cedar',True,False),('tokyo-night',True,True)]:
            result,calls=self.exercise(theme,fox=fox,normal=normal,reconcile_only=True)
            self.assertEqual(result,0)
            self.assertEqual(calls,[])
    def test_guard_removes_only_overlap(self):
        result,calls=self.exercise('cedar',fox=True,normal=True,reconcile_only=True)
        self.assertEqual(result,0)
        self.assertEqual(len(calls),1)
        self.assertEqual(calls[0][:2],['qs','kill'])
    def test_guard_keeps_lock_safety_when_deferring(self):
        result,calls=self.exercise('cedar',fox=True,normal=True,is_locked=True,reconcile_only=True)
        self.assertEqual(result,75)
        self.assertEqual(calls,[])
    def test_locked_handoff_defers_without_killing(self):
        _,calls=self.exercise('cedar',is_locked=True)
        self.assertEqual(len(calls),1)
        self.assertIn('--deferred',calls[0])
    def test_failed_start_restores_normal(self):
        result,calls=self.exercise('cedar',ready=False)
        self.assertEqual(result,1)
        self.assertTrue(any(c[0] == 'systemd-run' and c[-1] == 'omarchy-launch-shell' for c in calls))


def strip_jsonc(raw):
    return re.sub(r',(\s*[}\]])', r'\1', re.sub(r'^\s*//[^\n]*(\n|$)', '', raw, flags=re.M))


class GoMenu(unittest.TestCase):
    def ipc_surface(self):
        text = (ROOT/'shell.qml').read_text()
        surface = {}
        for match in re.finditer(r'IpcHandler \{', text):
            depth, end = 0, match.end() - 1
            while True:
                depth += {'{': 1, '}': -1}.get(text[end], 0)
                if depth == 0: break
                end += 1
            body = text[match.end():end]
            surface[re.search(r'target: "(\w+)"', body).group(1)] = set(re.findall(r'function (\w+)\(', body))
        return surface
    def test_cedar_overlay_parses_and_targets_real_ipc(self):
        items = json.loads(strip_jsonc((ROOT/'menus/cedar-menu.jsonc').read_text()))
        self.assertIn('cedar.settings', items)
        surface = self.ipc_surface()
        calls = [(i, m.group(1), m.group(2)) for i, row in items.items() for m in re.finditer(r'qs -c cedar ipc call (\w+) (\w+)', row.get('action', ''))]
        self.assertTrue(calls)
        for item_id, target, function in calls:
            self.assertIn(function, surface.get(target, set()), (item_id, target, function))
    def test_default_omarchy_menu_still_parses(self):
        path = Path('/usr/share/omarchy/default/omarchy/omarchy-menu.jsonc')
        if not path.exists(): self.skipTest('Omarchy not installed')
        items = json.loads(strip_jsonc(path.read_text()))
        for item_id in ['apps', 'setup.plugin.enable', 'style.font']: self.assertIn(item_id, items)
    def test_theme_bindings_are_unique_and_unbound_first(self):
        lua = (ROOT/'themes/hyprland.lua').read_text()
        self.assertIn('hl.unbind(key)', lua)
        keys = re.findall(r'^bind\("([^"]+)"', lua, re.M)
        self.assertEqual(len(keys), len(set(keys)), keys)
        for key in ['SUPER + SPACE', 'SUPER + ALT + P', 'SUPER + K']: self.assertIn(key, keys)
    def test_menu_model_is_the_omarchy_copy(self):
        ours = (ROOT/'components/MenuModel.js').read_text()
        theirs = Path('/usr/share/omarchy/shell/plugins/menu/MenuModel.js')
        if theirs.exists(): self.assertTrue(ours.endswith(theirs.read_text()))
        self.assertIn('function mergeAppRows', ours)


class Shim(unittest.TestCase):
    def run_shim(self, *args, qs_exit=0):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp); (tmp/'bin').mkdir(); (tmp/'omarchy/bin').mkdir(parents=True)
            log = tmp/'log'
            (tmp/'bin/qs').write_text(f'#!/bin/sh\necho "qs $*" >> {log}\nexit {qs_exit}\n'); (tmp/'bin/qs').chmod(0o755)
            (tmp/'omarchy/bin/omarchy-shell').write_text(f'#!/bin/sh\necho "real $*" >> {log}\n'); (tmp/'omarchy/bin/omarchy-shell').chmod(0o755)
            env = {**os.environ, 'PATH': f"{tmp/'bin'}:{os.environ['PATH']}", 'OMARCHY_PATH': str(tmp/'omarchy')}
            result = subprocess.run([str(ROOT/'scripts/shim/omarchy-shell'), *args], capture_output=True, text=True, env=env, timeout=10)
            return result, log.read_text() if log.exists() else ''
    def test_menu_toggle_routes_to_cedar(self):
        _, log = self.run_shim('shell', 'toggle', 'omarchy.menu', '{"menu":"setup.plugin"}')
        self.assertEqual(log.strip(), 'qs -c cedar ipc call menu toggle setup.plugin')
    def test_select_prompt_is_summoned_verbatim(self):
        payload = '{"mode":"select","prompt":"Pick","options":["a"],"selectionFile":"/tmp/s","doneFile":"/tmp/d"}'
        _, log = self.run_shim('shell', 'summon', 'omarchy.menu', payload)
        self.assertEqual(log.strip(), 'qs -c cedar ipc call menu summon ' + payload)
    def test_lock_and_hide_route_to_cedar(self):
        _, log = self.run_shim('lock', 'lock'); self.assertIn('lock lock', log)
        _, log = self.run_shim('shell', 'hide', 'omarchy.menu'); self.assertIn('shell close', log)
    def test_unknown_calls_forward_to_real_shell(self):
        _, log = self.run_shim('-q', 'omarchy.indicators', 'refresh')
        self.assertEqual(log.strip(), 'real -q omarchy.indicators refresh')
    def test_plugin_listing_answers_locally(self):
        result, log = self.run_shim('shell', 'listPlugins')
        self.assertEqual(log, '')
        self.assertIsInstance(json.loads(result.stdout), list)


class Plugins(unittest.TestCase):
    def fixture(self, tmp):
        first = tmp/'first'; third = tmp/'third'
        def manifest(path, data): path.parent.mkdir(parents=True, exist_ok=True); path.write_text(json.dumps(data))
        manifest(first/'menu/manifest.json', dict(id='omarchy.menu', name='Omarchy menu', kinds=['menu', 'bar-widget']))
        manifest(first/'panels/audio/manifest.json', dict(id='omarchy.audio', name='Audio', kinds=['bar-widget']))
        manifest(first/'bar/manifest.json', dict(id='omarchy.bar', name='Bar', kinds=['bar']))
        manifest(first/'bar/widgets/Spacer.manifest.json', dict(id='omarchy.spacer', name='Spacer', kinds=['bar-widget'], barWidget=dict(defaultSection='right')))
        manifest(first/'lock/manifest.json', dict(id='omarchy.lock', name='Lock', kinds=['service']))
        manifest(third/'me.keys/manifest.json', dict(id='me.keys', name='Keys', kinds=['menu', 'bar-widget'], omarchy=dict(clonedFrom='omarchy.menu')))
        manifest(third/'me.svc/manifest.json', dict(id='me.svc', name='Svc', kinds=['service']))
        config = {'version': 1, 'bar': {'layout': {'left': [{'id': 'omarchy.menu'}], 'center': [], 'right': [{'id': 'omarchy.audio'}]}}, 'plugins': []}
        return plugins.scan(first, third), config
    def test_listing_matches_shell_semantics(self):
        with tempfile.TemporaryDirectory() as tmp:
            found, config = self.fixture(Path(tmp))
            rows = {row['id']: row for row in plugins.listing(found, config)}
            self.assertEqual(len(rows), 7)
            self.assertTrue(rows['omarchy.bar']['enabled']); self.assertFalse(rows['omarchy.bar']['canDisable'])
            self.assertTrue(rows['omarchy.audio']['enabled']); self.assertFalse(rows['omarchy.spacer']['enabled'])
            self.assertTrue(rows['omarchy.lock']['enabled']); self.assertFalse(rows['me.svc']['enabled'])
            self.assertEqual(rows['me.keys']['clonedFrom'], 'omarchy.menu'); self.assertFalse(rows['me.keys']['firstParty'])
    def test_widget_toggle_edits_bar_layout(self):
        with tempfile.TemporaryDirectory() as tmp:
            found, config = self.fixture(Path(tmp))
            plugins.set_enabled('omarchy.spacer', True, {}, found, config)
            self.assertEqual(config['bar']['layout']['right'][-1], {'id': 'omarchy.spacer'})
            plugins.set_enabled('omarchy.audio', False, {}, found, config)
            self.assertEqual([e['id'] for e in config['bar']['layout']['right']], ['omarchy.spacer'])
            plugins.set_enabled('omarchy.spacer', True, {'section': 'left', 'before': 'omarchy.menu'}, found, config)
            self.assertEqual(config['bar']['layout']['right'], [{'id': 'omarchy.spacer'}])
    def test_first_party_service_disable_is_recorded(self):
        with tempfile.TemporaryDirectory() as tmp:
            found, config = self.fixture(Path(tmp))
            plugins.set_enabled('omarchy.lock', False, {}, found, config)
            self.assertEqual(config['disabledPlugins'], ['omarchy.lock'])
            plugins.set_enabled('omarchy.lock', True, {}, found, config)
            self.assertNotIn('disabledPlugins', config)
    def test_clone_replaces_source_and_restores_it(self):
        with tempfile.TemporaryDirectory() as tmp:
            found, config = self.fixture(Path(tmp))
            plugins.set_enabled('me.keys', True, {}, found, config)
            self.assertEqual(config['bar']['layout']['left'], [{'id': 'me.keys'}])
            self.assertEqual(config['disabledPlugins'], ['omarchy.menu']); self.assertEqual(config['cloneSourceRestores'], ['me.keys'])
            plugins.set_enabled('me.keys', False, {}, found, config)
            self.assertEqual(config['bar']['layout']['left'], [{'id': 'omarchy.menu'}])
            self.assertNotIn('disabledPlugins', config); self.assertNotIn('cloneSourceRestores', config)
    def test_third_party_service_uses_plugins_list(self):
        with tempfile.TemporaryDirectory() as tmp:
            found, config = self.fixture(Path(tmp))
            plugins.set_enabled('me.svc', True, {}, found, config)
            self.assertEqual(config['plugins'], [{'id': 'me.svc'}])
            plugins.set_enabled('me.svc', False, {}, found, config)
            self.assertEqual(config['plugins'], [])
            with self.assertRaises(KeyError): plugins.set_enabled('nope', True, {}, found, config)
    def test_cli_round_trip_writes_user_config(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp); self.fixture(tmp)
            omarchy = tmp/'omarchy'; (omarchy/'shell').mkdir(parents=True); (omarchy/'config/omarchy').mkdir(parents=True)
            (omarchy/'shell/plugins').symlink_to(tmp/'first')
            (omarchy/'config/omarchy/shell.json').write_text(json.dumps({'version': 1, 'bar': {'layout': {'left': [], 'center': [], 'right': []}}, 'plugins': []}))
            config_home = tmp/'config'; (config_home/'omarchy').mkdir(parents=True); (config_home/'omarchy/plugins').symlink_to(tmp/'third')
            env = {**os.environ, 'OMARCHY_PATH': str(omarchy), 'XDG_CONFIG_HOME': str(config_home)}
            def cli(*args): return subprocess.run(['python3', str(ROOT/'scripts/plugins.py'), *args], capture_output=True, text=True, env=env, timeout=10)
            self.assertIn('Enabled Spacer', cli('toggle', 'omarchy.spacer').stdout)
            saved = json.loads((config_home/'omarchy/shell.json').read_text())
            self.assertEqual(saved['bar']['layout']['right'], [{'id': 'omarchy.spacer'}])
            rows = cli('rows', 'menu').stdout.splitlines()
            self.assertIn('Spacer  omarchy.spacer\tomarchy.spacer\tomarchy.spacer', rows)
            self.assertEqual(cli('set', 'omarchy.spacer', 'false').stdout.strip(), 'ok')
            self.assertEqual(json.loads((config_home/'omarchy/shell.json').read_text())['bar']['layout']['right'], [])
            self.assertEqual(cli('toggle', 'omarchy.bar').returncode, 1)

if __name__ == '__main__': unittest.main()
