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
session = module('cedar_session', 'scripts/cedar_session.py')
plugins = module('plugins', 'scripts/plugins.py')

class Palette(unittest.TestCase):
    def test_text_on_worst_case_glass(self):
        colors = dict(re.findall(r'property color (\w+): (?:token\("\w+", )?"(#[0-9A-Fa-f]{6})"', (ROOT/'Theme.qml').read_text()))
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

class SessionLifecycle(unittest.TestCase):
    """CEDAR starts with Hyprland whatever the Omarchy theme; Omarchy's shell is a known overlap."""
    def exercise(self, action='start', fox=False, normal=True, ready=True, is_locked=False, omarchy_ready=True):
        calls=[]; running={'fox':fox,'normal':normal}
        def instances(sel):
            if '--all' in sel: return []
            return [{'pid':1,'config_path':'/users/station/.config/quickshell/cedar/shell.qml'}] if running['fox' if '-c' in sel else 'normal'] else []
        def run(args, **kwargs):
            calls.append(args)
            if args[:2]==['qs','kill']: running['fox' if ('-c' in args or '--pid' in args) else 'normal']=False
            if args[:3]==['systemctl','--user','stop']: running['fox']=False
            if args[0]=='systemd-run' and '--unit=cedar-shell' in args: running['fox']=True
            if args[0]=='systemd-run' and args[-1]=='omarchy-launch-shell': running['normal']=True
            if args[-2:]==['shell','ping']: return subprocess.CompletedProcess(args,0 if omarchy_ready else 1,'pong','')
            if args[-2:]==['shell','isLocked']: return subprocess.CompletedProcess(args,0 if running['fox'] and ready else 1,'false' if running['fox'] and ready else '','')
            return subprocess.CompletedProcess(args,0,'','')
        def wait_for(predicate, seconds, step=0.2): return predicate()
        with tempfile.TemporaryDirectory() as tmp, patch.object(session,'RUNTIME',Path(tmp)), patch.object(session,'LOG',Path(tmp)/'shell.log'), \
                patch.object(session,'selector',return_value=['-c','cedar']), patch.object(session,'omarchy_shell',return_value=Path('/usr/share/omarchy/shell')), \
                patch.object(session,'omarchy_locked',return_value=is_locked), patch.object(session,'instances',side_effect=instances), patch.object(session,'run',side_effect=run), \
                patch.object(session,'wait_for',side_effect=wait_for), patch.object(session,'supervisors',return_value=[]), \
                patch.object(session.shutil,'which',side_effect=lambda n: '/usr/bin/'+n), patch.dict(os.environ,{'WAYLAND_DISPLAY':'test'}):
            result=session.main([action])
        return result,calls,running
    def launches(self, calls): return [c for c in calls if c[0]=='systemd-run']
    def test_preview_exists_for_graphical_selector(self):
        self.assertTrue((ROOT/'themes/preview.png').is_file())
        self.assertTrue((ROOT/'themes/backgrounds/field-station.png').is_file())
    def test_hook_is_theme_independent(self):
        self.assertNotIn('theme.name', (ROOT/'scripts/theme-sync.py').read_text())
        self.assertNotIn('theme', (ROOT/'scripts/cedar_session.py').read_text().split('def ')[1:][0])
    def test_start_retires_omarchy_then_starts_cedar(self):
        result,calls,running=self.exercise()
        self.assertEqual(result,0); self.assertEqual(running,{'fox':True,'normal':False})
        self.assertLess(next(i for i,c in enumerate(calls) if c[-2:]==['shell','ping']), next(i for i,c in enumerate(calls) if c[0]=='systemd-run'))
        launch=self.launches(calls)[0]
        self.assertIn('--unit=cedar-shell',launch); self.assertEqual(launch[-4:],['qs','-n','-c','cedar'])
        self.assertIn('--setenv=WAYLAND_DISPLAY=test',launch)
    def test_start_without_omarchy_needs_only_hyprland(self):
        with patch.object(session,'omarchy_shell',return_value=None):
            result,calls,running=self.exercise(normal=False)
        self.assertEqual(result,0); self.assertTrue(running['fox'])
    def test_repeat_start_is_idempotent(self):
        result,calls,_=self.exercise(fox=True,normal=False)
        self.assertEqual(result,0); self.assertEqual(self.launches(calls),[])
    def test_existing_cedar_removes_overlapping_omarchy_shell(self):
        result,calls,running=self.exercise(fox=True,normal=True)
        self.assertEqual(result,0); self.assertEqual(running,{'fox':True,'normal':False}); self.assertEqual(self.launches(calls),[])
    def test_loading_omarchy_shell_is_never_killed(self):
        result,calls,running=self.exercise(fox=True,normal=True,omarchy_ready=False)
        self.assertTrue(running['normal']); self.assertFalse(any(c[:2]==['qs','kill'] for c in calls))
    def test_inherited_shim_environment_never_reaches_probes_or_shell(self):
        # Field Station runs the updater in a scope that keeps the 1.5 shell's environment:
        # its release shim first on PATH and CEDAR_SHELL_PATH pointing at that release.
        inherited={'CEDAR_SHELL_PATH':'/users/station/.local/share/cedar/releases/1.5-old/shell.qml','CEDAR_QS_BIN':'/usr/bin/qs',
                   'PATH':'/users/station/.local/share/cedar/releases/1.5-old/scripts/shim:/usr/bin:/usr/local/bin','LC_ALL':'C'}
        with patch.dict(os.environ,inherited):
            result,calls,running=self.exercise()
        self.assertEqual(result,0); self.assertEqual(running,{'fox':True,'normal':False})
        scrubbed=session.scrub_environment(dict(inherited))
        self.assertNotIn('CEDAR_SHELL_PATH',scrubbed); self.assertNotIn('CEDAR_QS_BIN',scrubbed); self.assertNotIn('LC_ALL',scrubbed)
        self.assertEqual(scrubbed['PATH'],'/usr/bin:/usr/local/bin','the shim is no longer in front of qs')
        launch=self.launches(calls)[0]
        self.assertIn('--setenv=PATH=/usr/bin:/usr/local/bin',launch)
        self.assertFalse(any(e.startswith(('--setenv=CEDAR_SHELL_PATH','--setenv=LC_ALL')) for e in launch))
    def test_scrub_keeps_an_ordinary_environment(self):
        env={'PATH':'/usr/bin:/users/station/.local/bin','LC_ALL':'en_US.UTF-8','LANG':'en_US.UTF-8','WAYLAND_DISPLAY':'wayland-1'}
        self.assertEqual(session.scrub_environment(dict(env)),env)
    def test_guard_never_launches_a_missing_shell(self):
        for fox,normal in [(False,True),(True,False)]:
            result,calls,_=self.exercise('reconcile',fox=fox,normal=normal)
            self.assertEqual(result,0); self.assertEqual(self.launches(calls),[])
            self.assertFalse(any(c[:2]==['qs','kill'] for c in calls))
    def test_guard_keeps_lock_safety_when_deferring(self):
        result,calls,running=self.exercise('reconcile',fox=True,normal=True,is_locked=True)
        self.assertEqual(result,75); self.assertTrue(running['normal'])
    def test_failed_start_gives_omarchy_back(self):
        result,calls,running=self.exercise(ready=False)
        self.assertEqual(result,1)
        self.assertTrue(any(c[0]=='systemd-run' and c[-1]=='omarchy-launch-shell' for c in calls))
    def test_restart_refuses_while_locked(self):
        with self.assertRaises(SystemExit):
            self.exercise('restart',fox=True,normal=False,ready=False)
    def test_restart_stops_then_starts(self):
        result,calls,running=self.exercise('restart',fox=True,normal=False)
        self.assertEqual(result,0); self.assertTrue(running['fox'])
        self.assertLess(calls.index(['systemctl','--user','stop','cedar-shell.service']), next(i for i,c in enumerate(calls) if c[0]=='systemd-run'))
    def test_restart_with_nothing_running_starts(self):
        result,calls,running=self.exercise('restart',fox=False,normal=False)
        self.assertEqual(result,0); self.assertTrue(running['fox']); self.assertNotIn(['systemctl','--user','stop','cedar-shell.service'],calls)
    def test_cedar_is_recognised_by_profile_or_release_store_whatever_launched_it(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp=Path(tmp); config=tmp/'config'; data=tmp/'data'
            release=data/'cedar/releases/1.9-abc'; release.mkdir(parents=True); (release/'shell.qml').write_text('')
            (data/'cedar/current').symlink_to(release)
            checkout=tmp/'checkout'; checkout.mkdir(); (checkout/'shell.qml').write_text('')
            (config/'quickshell').mkdir(parents=True); (config/'quickshell/cedar').symlink_to(checkout)
            with patch.object(session,'CONFIG',config), patch.object(session,'DATA',data):
                self.assertTrue(session.is_cedar(config/'quickshell/cedar/shell.qml'))
                self.assertTrue(session.is_cedar(checkout/'shell.qml'), 'what the profile points at')
                self.assertTrue(session.is_cedar(release/'shell.qml'), 'an installed release')
                self.assertTrue(session.is_cedar(data/'cedar/current/shell.qml'))
                self.assertFalse(session.is_cedar('/usr/share/omarchy/shell/shell.qml'))
                self.assertFalse(session.is_cedar(release/'installer.qml'))
            rows={'-c':[{'pid':1,'config_path':str(config/'quickshell/cedar/shell.qml')}],
                  '--all':[{'pid':1,'config_path':str(config/'quickshell/cedar/shell.qml')},{'pid':2,'config_path':str(release/'shell.qml')},{'pid':3,'config_path':'/usr/share/omarchy/shell/shell.qml'}]}
            with patch.object(session,'CONFIG',config), patch.object(session,'DATA',data), patch.object(session,'selector',return_value=['-c','cedar']), \
                    patch.object(session,'instances',side_effect=lambda sel: rows['--all' if '--all' in sel else '-c']):
                self.assertEqual(sorted(r['pid'] for r in session.cedar_instances()),[1,2])

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
        items = json.loads(strip_jsonc((ROOT/'integrations/omarchy/menu-overlay.jsonc').read_text()))
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
        lua = (ROOT/'integrations/omarchy/hyprland.lua').read_text()
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
    def test_save_keeps_a_dotfile_link_and_its_mode(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp); dotfiles = tmp/'dotfiles/shell.json'; dotfiles.parent.mkdir()
            dotfiles.write_text('{}'); dotfiles.chmod(0o640)
            link = tmp/'config/omarchy/shell.json'; link.parent.mkdir(parents=True); link.symlink_to(dotfiles)
            plugins.save_config({'version': 1}, link)
            self.assertTrue(link.is_symlink())
            self.assertEqual(json.loads(dotfiles.read_text()), {'version': 1})
            self.assertEqual(dotfiles.stat().st_mode & 0o777, 0o640)
            self.assertEqual(sorted(p.name for p in dotfiles.parent.iterdir()), ['shell.json'])
            self.assertEqual(sorted(p.name for p in link.parent.iterdir()), ['shell.json'])

if __name__ == '__main__': unittest.main()
