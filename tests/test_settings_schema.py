"""Schema integrity for Settings: keys, defaults, menu coverage, levels, validation and the service route."""
from pathlib import Path
import json
import re
import shutil
import subprocess
import unittest
import importlib.util
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[1]
SCHEMA=ROOT/'components/SettingsSchema.js'
_spec = importlib.util.spec_from_file_location('settings_dictation', ROOT/'scripts/dictation.py')
dictation = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(dictation)
def evaluate(expression):
    script=SCHEMA.read_text().replace('.pragma library','')+'\nconsole.log(JSON.stringify('+expression+'));'
    return json.loads(subprocess.run(['node','-e',script],capture_output=True,text=True,check=True,timeout=20).stdout)

@unittest.skipUnless(shutil.which('node'),'Node is needed to evaluate the schema')
class SchemaIntegrity(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.schema=evaluate('{pages:pages,fields:fields,menu:menu,extras:extras,levels:fields.map(function(f){return [f.key,levelOf(f)];}),'
                            'pageOf:{barOpacity:pageOf("barOpacity"),vrr:pageOf("vrr"),kb_layout:pageOf("kb_layout"),nothing:pageOf("nothing")},'
                            'menuOf:pages.map(function(p){return [p.id,menuOf(p.id)];}),'
                            'simpleCore:visibleFields("core","simple").length,advancedCore:visibleFields("core","advanced").length}')
        cls.config=(ROOT/'Config.qml').read_text()
    def test_field_keys_are_unique_and_have_config_defaults_and_are_saved(self):
        keys=[f['key'] for f in self.schema['fields']]
        self.assertEqual(len(keys),len(set(keys)))
        saved=re.search(r'const keys = \[(.*?)\];',self.config,re.S).group(1)
        for key in keys:
            self.assertRegex(self.config,r'property \w+ '+re.escape(key)+r'\s*:',key+' has no default in Config.qml')
            self.assertIn('"'+key+'"',saved,key+' is not written by savePreferences')
    def test_schema_defaults_match_config_and_validate(self):
        for field in self.schema['fields']:
            key = field['key']
            literal = re.search(r'property (?:bool|int|real|string) '+re.escape(key)+r'\s*:\s*([^\n]+)', self.config.split('JsonAdapter {', 1)[1]).group(1).strip()
            try: default = json.loads(literal)
            except ValueError: default = float(literal)
            self.assertEqual(field['defaultValue'], default, key)
        self.assertEqual(evaluate('fields.filter(function(f){return validate(f.key,f.defaultValue)!=="";}).map(function(f){return f.key;})'), [])
    def test_every_page_is_in_exactly_one_menu_category(self):
        ids=[p['id'] for p in self.schema['pages']]
        placed=[pid for m in self.schema['menu'] for pid in m['pages']]
        self.assertEqual(sorted(placed),sorted(ids))
        for m in self.schema['menu']:
            self.assertTrue(m['id'] and m['label'] and m['description'],m)
        self.assertTrue(all(category for _,category in self.schema['menuOf']))
    def test_fields_and_extras_point_at_existing_pages(self):
        ids={p['id'] for p in self.schema['pages']}
        for f in self.schema['fields']+self.schema['extras']:
            self.assertIn(f['page'],ids,f.get('key'))
    def test_levels_keep_everyday_rows_simple_and_fold_the_rest(self):
        levels=dict(self.schema['levels'])
        self.assertTrue(set(levels.values())<={'basic','advanced'})
        for f in self.schema['fields']:
            if f['group']=='Advanced':
                self.assertEqual(levels[f['key']],'advanced',f['key'])
        for key in ('reducedMotion','clock24','doNotDisturb','notificationsEnabled','wallpaperMode','performanceMode','idleLockSeconds','settingsLevel'):
            self.assertEqual(levels[key],'basic',key)
        for key in ('coreTemperatureLimit','latitude','gamingBlur'):
            self.assertEqual(levels[key],'advanced',key)
        self.assertLess(self.schema['simpleCore'],self.schema['advancedCore'])
        self.assertGreaterEqual(sum(1 for v in levels.values() if v=='basic'),30,'the Simple view keeps the everyday rows')
    def test_page_lookup_covers_fields_extras_and_input(self):
        self.assertEqual(self.schema['pageOf'],{'barOpacity':'bar','vrr':'displays','kb_layout':'input','nothing':''})
    def test_validate_enforces_types_ranges_and_choices(self):
        ok,bad=[],[]
        results=evaluate('[validate("clock24",true),validate("clock24","yes"),validate("barHeight",44),validate("barHeight",10),validate("barHeight",99),validate("barHeight","44"),'
                         'validate("dateStyle","iso"),validate("dateStyle","sideways"),validate("focusMinutes",25),validate("focusMinutes",30),validate("locationName","Ridge"),validate("locationName",4),'
                         'validate("settingsLevel","advanced"),validate("settingsLevel","expert"),validate("unknownKey",1)]')
        expected=['','x','','x','x','x','','x','','x','','x','','x','']
        for value,want in zip(results,expected):
            (ok if want=='' else bad).append(value)
        self.assertTrue(all(v=='' for v in ok),ok)
        self.assertTrue(all(v for v in bad),bad)
    def test_config_ipc_set_consults_the_schema(self):
        self.assertIn('SettingsSchema.validate(key, next)',self.config)

class ServiceRoute(unittest.TestCase):
    """Settings is a window owned by SettingsService; ShellState hands every route to it."""
    def test_shell_state_routes_settings_to_the_service(self):
        state=(ROOT/'ShellState.qml').read_text()
        self.assertEqual(state.count('SettingsService.route('),2)
        self.assertIn('SettingsService.route(settingsPage, settingsAnchor, true)',state)
        self.assertIn('SettingsService.route(settingsPage, settingsAnchor, false)',state)
    def test_services_watch_the_window_not_a_panel(self):
        for service,expr in (('Brightness','SettingsService.open && SettingsService.page === "power"'),
                             ('Network','SettingsService.open && SettingsService.page === "connections"'),
                             ('DefaultApps','SettingsService.open && ["apps","setup"].includes(SettingsService.page)')):
            text=(ROOT/'services'/f'{service}.qml').read_text()
            self.assertIn(expr,text,service)
            self.assertNotIn('ShellState.panel === "settings"',text,service)
    def test_ipc_methods_are_documented(self):
        shell=(ROOT/'shell.qml').read_text()
        block=shell.split('target: "settings"')[1].split('IpcHandler')[0]
        methods=set(re.findall(r'function (\w+)\(',block))
        self.assertEqual(methods,{'toggle','set','get','show','open','close','level','status','search'})
        row=[line for line in (ROOT/'docs/SECURITY.md').read_text().splitlines() if line.startswith('| `settings` |')][0]
        for name in methods:
            self.assertIn('`'+name+'`',row,name+' missing from docs/SECURITY.md')
    def test_service_is_registered_and_bundled(self):
        self.assertIn('singleton SettingsService 1.0 SettingsService.qml',(ROOT/'services/qmldir').read_text())
        bundle=[p for p in json.loads((ROOT/'data/plugins.json').read_text())['plugins'] if p['id']=='cedar.settings'][0]
        self.assertIn('services/SettingsService.qml',bundle['files'])
        self.assertIn('services/SettingsService.qml',bundle['releaseArtifacts'])
        self.assertIn('tests/test_settings_schema.py',bundle['tests'])
        self.assertIn('tests/check_settings_service.py',bundle['tests'])

class DictationSettings(unittest.TestCase):
    """No hardware: validate requests and inspect exact Voxtype argv with mocks."""
    def test_every_supported_key_renders_a_valid_value(self):
        for key, (kind, constraint) in dictation.KEYS.items():
            value = {'bool': True, 'model': 'base.en', 'device': 'default', 'text': 'auto'}.get(kind)
            if kind in ('int', 'float'): value = constraint[0]
            if kind == 'choice': value = constraint[0]
            with self.subTest(key=key):
                self.assertIsInstance(dictation.render(key, value), str)

    def test_wrong_types_nonfinite_and_out_of_range_values_are_rejected(self):
        invalid = {
            'whisper.translate': [None, 'false', 'yes', 0, 1, []],
            'audio.max_duration_secs': [True, '60', None, 5.5, 4, 3601, float('inf'), float('nan')],
            'vad.threshold': [False, '0.5', None, -0.001, 1.001, float('inf'), float('nan')],
            'whisper.language': [None, 42, 'english', 'en\n'],
            'whisper.model': [None, '-base', '../base', 'base\n'],
            'audio.device': [None, '-default', 'default\n'],
            'output.append_text': [None, 1, 'a\nb', 'x' * 81],
            'output.mode': [None, 'shell'],
        }
        for key, values in invalid.items():
            for value in values:
                with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                    dictation.render(key, value)

    def test_set_and_unset_restart_only_after_success(self):
        with patch.object(dictation, 'installed', return_value=True), \
             patch.object(dictation, 'run') as run, \
             patch.object(dictation, 'snapshot', return_value={'config': {}}):
            dictation.action({'action': 'set', 'key': 'whisper.translate', 'value': False})
            self.assertEqual(run.call_args_list[0].args[0], ['voxtype', 'config', 'set', 'whisper.translate', 'false'])
            self.assertEqual(run.call_args_list[1].args[0], ['systemctl', '--user', 'restart', 'voxtype'])
            run.reset_mock()
            dictation.action({'action': 'unset', 'key': 'audio.device'})
            self.assertEqual(run.call_args_list[0].args[0], ['voxtype', 'config', 'unset', 'audio.device'])
            self.assertEqual(run.call_count, 2)
            run.reset_mock(); run.side_effect = RuntimeError('rejected')
            with self.assertRaises(RuntimeError):
                dictation.action({'action': 'set', 'key': 'whisper.model', 'value': 'base'})
            self.assertEqual(run.call_count, 1)

    def test_invalid_requests_never_run_commands(self):
        with patch.object(dictation, 'installed', return_value=True), patch.object(dictation, 'run') as run:
            for req in ({'action': 'set', 'key': 'output.auto_submit', 'value': 'yes'},
                        {'action': 'unset', 'key': 'unknown'}, {'action': 'unknown'}):
                with self.assertRaises(ValueError): dictation.action(req)
            run.assert_not_called()

    def test_absent_voxtype_returns_complete_empty_snapshot(self):
        with patch.object(dictation, 'installed', return_value=False), patch.object(dictation, 'run') as run:
            data = dictation.action({'action': 'read'})
            self.assertFalse(data['installed']); self.assertFalse(data['daemon'])
            self.assertEqual(data['config'], {}); self.assertEqual(data['models'], [])
            run.assert_not_called()

    def test_download_uses_only_catalog_and_does_not_restart(self):
        catalog = [{'name': 'base.en', 'download': 'base.en', 'downloadable': True, 'installed': False}]
        with patch.object(dictation, 'installed', return_value=True), \
             patch.object(dictation, 'models', return_value=catalog), \
             patch.object(dictation, 'snapshot', return_value={}), patch.object(dictation, 'run') as run:
            with self.assertRaises(ValueError): dictation.action({'action': 'download', 'model': '../untrusted'})
            run.assert_not_called()
            dictation.action({'action': 'download', 'model': 'base.en'})
            self.assertEqual(run.call_args.args[0], ['voxtype', 'setup', '--download', '--model', 'base.en', '--quiet', '--no-post-install'])
            self.assertEqual(run.call_count, 1)

if __name__=='__main__':
    unittest.main()
