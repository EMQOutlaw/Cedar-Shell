"""Fixture-only migration tests. No live desktop commands or provider signals."""
import copy
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
from types import SimpleNamespace
import contextlib

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from compatibility.support import d
from compatibility import detection, keybindings
from compatibility.engine import Engine, history, operation_lock
from installer.engine.host import FakeHost


class DetectionTests(unittest.TestCase):
    def host(self, **kw):
        return FakeHost(home='/fixture', environ={'HYPRLAND_INSTANCE_SIGNATURE': 'here'},
                        which=['qs', 'hyprctl'], commands={'hyprctl -j monitors': (0, '[{"name":"test"}]', ''),
                                                         'hyprctl -j binds': (0, '[]', '')}, **kw)

    def test_simultaneous_installed_is_not_active(self):
        host = self.host(dirs=['/fixture/.config/omarchy', '/fixture/.config/noctalia'], packages={'omarchy': '4', 'noctalia': '5'},
                         processes=[{'pid': 4, 'exe': '/bin/noctalia', 'argv': ['noctalia'], 'environment': {'HYPRLAND_INSTANCE_SIGNATURE': 'here'}}])
        result = detection.scan(host)
        states = {r['id']: r['states'] for r in result['matches']}
        self.assertTrue(states['omarchy']['installed'])
        self.assertFalse(states['omarchy']['active'])
        self.assertTrue(states['noctalia']['active'])
        self.assertEqual(result['activeShells'], ['noctalia'])

    def test_other_display_and_unknown_qs(self):
        host = self.host(processes=[{'pid': 2, 'exe': '/bin/waybar', 'argv': ['waybar'], 'environment': {'HYPRLAND_INSTANCE_SIGNATURE': 'elsewhere'}}])
        result = detection.scan(host, {'quickshellInstances': [{'pid': 5, 'config_path': '/fixture/custom/shell.qml'}]})
        self.assertEqual(result['activeShells'], [])
        self.assertEqual(result['unknown'][0]['session'], 'unknown')

    def test_unit_state_not_process_evidence(self):
        host = self.host(units={'dms.service': {'state': 'enabled', 'active': 'active'}})
        result = detection.scan(host)
        dms = next(r for r in result['matches'] if r['id'] == 'dms')
        self.assertTrue(dms['states']['autostarted'])
        self.assertTrue(dms['states']['managed'])
        self.assertFalse(dms['states']['active'])

    def test_missing_ipc_is_unknown(self):
        result = detection.scan(FakeHost(home='/fixture'))
        self.assertFalse(result['compositor']['active'])
        self.assertTrue(result['probeErrors'])

    def test_reviewed_profiles_and_quickshell_roles(self):
        cases = [('omarchy', '/usr/share/omarchy/shell/shell.qml'),
                 ('caelestia', '/usr/share/caelestia/shell.qml'),
                 ('end4', '/fixture/.config/quickshell/ii/shell.qml'),
                 ('dms', '/usr/share/quickshell/dms/shell.qml'),
                 ('noctalia', '/fixture/.config/quickshell/noctalia/shell.qml')]
        for expected, path in cases:
            with self.subTest(profile=expected):
                host = self.host(processes=[{'pid': 42, 'exe': '/bin/qs', 'argv': ['qs', '-p', path], 'environment': {'HYPRLAND_INSTANCE_SIGNATURE': 'here'}}])
                result = detection.scan(host, {'quickshellInstances': [{'pid': 42, 'config_path': path}]})
                self.assertIn(expected, result['activeShells'])
                self.assertEqual(result['unknown'], [])
        result = detection.scan(self.host(dirs=['/fixture/.config/hyde']))
        hyde = next(r for r in result['matches'] if r['id'] == 'hyde')
        self.assertTrue(hyde['states']['configured'])
        self.assertIsNone(hyde['adapter'])

    def test_plain_hyprland_and_waybar_are_distinct_matches(self):
        host = self.host(processes=[{'pid': i + 1, 'exe': '/bin/' + name, 'argv': [name], 'environment': {'HYPRLAND_INSTANCE_SIGNATURE': 'here'}} for i, name in enumerate(['Hyprland', 'waybar'])])
        result = detection.scan(host)
        self.assertEqual(result['activeShells'], ['waybar'])
        self.assertTrue(next(r for r in result['matches'] if r['id'] == 'plain-hyprland')['states']['active'])


class BindingTests(unittest.TestCase):
    def test_conflicts_preserved_and_reassigned(self):
        live = [{'modmask': 64, 'key': 'space', 'dispatcher': 'exec', 'arg': 'old-launcher'}]
        report = keybindings.plan(live)
        self.assertEqual(report['rows'][0]['disposition'], 'Preserve')
        report = keybindings.plan(live, {'launcher': 'SUPER + ALT + L'})
        self.assertEqual(report['rows'][0]['disposition'], 'Add')
        for suffix in ('.lua', '.conf'):
            rendered = keybindings.render(report, suffix, Path('/source'))
            self.assertNotIn('unbind', rendered)
            self.assertIn('CEDAR launcher', rendered)

    def test_clipboard_not_emulated(self):
        self.assertFalse(any(r['key'] in ('SUPER + C', 'SUPER + X', 'SUPER + V') for r in keybindings.defaults()))
        with self.assertRaises(d.Refused):
            keybindings.plan([], {'launcher': 'SUPER + C'})

    def test_duplicate_assignments_refused(self):
        with self.assertRaises(d.Refused):
            keybindings.plan([], {'launcher': 'SUPER + T'})

    def test_assignment_spacing_and_types(self):
        report = keybindings.plan([], {'launcher': 'SUPER+ALT+L'})
        self.assertIn('bindd = SUPER ALT, L,', keybindings.render(report, '.conf'))
        self.assertIn('direction="l"', keybindings.render(report, '.lua'))
        with self.assertRaises(d.Refused):
            keybindings.plan([], {'launcher': 4})


class Adapter:
    def __init__(self, root):
        self.root, self.row, self.calls = root, None, []
        self.fail = False
        self.partial = False
    def record(self): return self.row
    def inspect(self, root, options):
        return {'adapter': 'hyprland', 'paused': [], 'root': str(root)}, [{'kind': 'start-cedar', 'target': str(root)}]
    def activate(self, root, options, identity, snapshot):
        self.calls.append('activate')
        self.row = {'id': 'fixture-session', 'root': str(root), 'stage': 'trial', 'compatibilityMigration': identity}
        if self.partial: raise RuntimeError('partial startup failed')
    def keep(self, login=False, expected_login_digest=None): self.row['stage'] = 'kept'; self.row['login'] = login
    def validate(self):
        if self.fail: raise d.Refused('IPC health failed')
        return {'healthy': True}
    def check_restore(self): self.calls.append('check_restore')
    def restore(self):
        self.calls.append('restore')
        if self.row: self.row['stage'] = 'restored'
    def verify_restored(self, snapshot): self.calls.append('verify_restored')


class MigrationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name)
        env = {'HOME': str(self.home), 'XDG_STATE_HOME': str(self.home/'state'), 'XDG_CONFIG_HOME': str(self.home/'config'), 'XDG_DATA_HOME': str(self.home/'data')}
        self.addCleanup(patch.stopall); patch.dict(os.environ, env).start()
        self.source = self.home/'source'; (self.source/'data').mkdir(parents=True)
        (self.source/'shell.qml').write_text('// fixture')
        (self.source/'data/source-files.json').write_text('["shell.qml"]')
        self.main = self.home/'config/hypr/hyprland.conf'; self.main.parent.mkdir(parents=True)
        self.main.write_text('monitor = ,preferred,auto,1\n')
        self.original = self.main.read_bytes()
        self.host = FakeHost(home=self.home, environ=env, commands={'hyprctl reload': (0,'ok',''), 'hyprctl configerrors': (0,'','')})
        self.adapter = Adapter(self.source)
        self.evidence = dict(compositor={'active': True, 'session': 'fixture', 'locked': False, 'ambiguous': False, 'config': str(self.main)},
                             matches=[], activeShells=[], unknown=[], probeErrors=[], dependencies=[], writable=True,
                             disk={'free': 100000000}, startup={'complete': True, 'files': [], 'commands': [], 'unresolved': []}, units={}, bindings=[])
        self.engine = Engine(self.source, self.host, adapter_factory=lambda _: self.adapter, scan=lambda: copy.deepcopy(self.evidence))

    def apply(self, **options):
        plan = self.engine.preview(options)['plan']
        self.assertEqual(plan['blocked'], [])
        return self.engine.apply(plan['digest'], options)

    def test_preview_is_read_only(self):
        report = self.engine.preview({'bindings': True})
        self.assertFalse((self.home/'state').exists())
        self.assertEqual(self.main.read_bytes(), self.original)
        self.assertTrue(report['plan']['digest'])

    def test_commit_restore_permissions(self):
        self.main.chmod(0o640)
        result = self.apply(bindings=True)
        self.assertEqual(self.adapter.calls, ['activate'])
        self.assertNotEqual(self.main.read_bytes(), self.original)
        self.assertEqual(self.main.stat().st_mode & 0o777, 0o640)
        out = self.engine.rollback(result['id'])
        self.assertTrue(out['restorationVerified'])
        self.assertEqual(self.main.read_bytes(), self.original)
        self.assertIn('verify_restored', self.adapter.calls)
        self.assertFalse((self.home/'config/cedar/compatibility/bindings.conf').exists())

    def test_repeated_application_no_duplicate(self):
        options = {'bindings': True}; plan = self.engine.preview(options)['plan']
        self.engine.apply(plan['digest'], options)
        self.assertTrue(self.engine.apply(plan['digest'], options)['alreadyApplied'])
        self.assertEqual(self.main.read_text().count('source ='), 1)

    def test_stale_approval_and_changed_source(self):
        plan = self.engine.preview()['plan']
        (self.source/'shell.qml').write_text('// new')
        with self.assertRaisesRegex(d.Refused, 'stale'):
            self.engine.apply(plan['digest'])
        self.assertEqual(self.adapter.calls, [])

    def test_user_edits_block_entire_restore(self):
        result = self.apply(bindings=True)
        self.main.write_text(self.main.read_text() + '# user change\n')
        with self.assertRaisesRegex(d.Refused, 'Later user edit'):
            self.engine.rollback(result['id'])
        self.assertNotIn('restore', self.adapter.calls)
        self.assertEqual(history()[0]['stage'], 'recovery-required')

    def test_failed_health_rolls_back(self):
        self.adapter.fail = True
        with self.assertRaisesRegex(d.Refused, 'restoration verified'):
            self.apply(bindings=True)
        self.assertEqual(self.main.read_bytes(), self.original)
        self.assertEqual(history()[0]['stage'], 'restored')

    def test_partial_activation_rolls_back(self):
        self.adapter.partial = True
        with self.assertRaisesRegex(d.Refused, 'restoration verified'):
            self.apply(bindings=True)
        self.assertEqual(self.main.read_bytes(), self.original)

    def test_interrupted_unrelated_session_is_not_claimed(self):
        result = self.apply()
        self.adapter.row['compatibilityMigration'] = 'someone-else'
        with self.assertRaisesRegex(d.Refused, 'identity differs'):
            self.engine.rollback(result['id'])
        self.assertNotIn('restore', self.adapter.calls)

    def test_broken_symlink_and_missing_dependencies(self):
        self.main.unlink(); self.main.symlink_to(self.home/'missing')
        self.assertTrue(self.engine.preview({'bindings': True})['plan']['blocked'])
        self.evidence['dependencies'] = [{'command': 'qs', 'available': False}]
        self.assertIn('Missing dependencies', str(self.engine.preview()['plan']['blocked']))

    def test_permission_and_unknown_shell(self):
        self.evidence['writable'] = False
        self.evidence['unknown'] = [{'session': 'current'}]
        self.assertEqual(len(self.engine.preview()['plan']['blocked']), 2)

    def test_detected_unsupported_shell_never_activates(self):
        self.evidence['matches'] = [{'id': 'dms', 'name': 'DMS', 'adapter': None, 'compatibility': 'detected', 'states': {'active': True}}]
        report = self.engine.preview()['plan']
        self.assertIn('not reviewed', str(report['blocked']))
        with self.assertRaises(d.Refused): self.engine.apply(report['digest'])
        self.assertEqual(self.adapter.calls, [])

    def test_operation_lock(self):
        with operation_lock():
            with self.assertRaises(d.Refused):
                with operation_lock(): pass

    def test_duplicate_startup_and_unresolved_config(self):
        from startup_graph import inspect
        self.main.write_text('exec-once = waybar\nexec-once = waybar\nsource = missing.conf\n')
        graph = inspect(self.main, self.home/'config', self.home)
        self.assertEqual(len(graph['commands']), 2)
        self.assertFalse(graph['complete'])
        self.evidence['startup'] = graph
        self.assertTrue(self.engine.preview({'bindings': True})['plan']['blocked'])

    def test_process_interruption_recovers_from_durable_owner(self):
        activate = self.adapter.activate
        def crash(*args):
            activate(*args)
            raise SystemExit('simulated power loss before coordinator receives session ID')
        with patch.object(self.adapter, 'activate', side_effect=crash):
            with self.assertRaises(SystemExit):
                self.apply(bindings=True)
        self.assertEqual(history()[0]['stage'], 'activating')
        self.assertNotEqual(self.main.read_bytes(), self.original)
        result = self.engine.rollback()
        self.assertTrue(result['restorationVerified'])
        self.assertEqual(self.main.read_bytes(), self.original)

    def test_failed_restore_never_claims_success(self):
        result = self.apply(bindings=True)
        with patch.object(self.adapter, 'restore', side_effect=d.Refused('original provider unavailable')):
            with self.assertRaisesRegex(d.Refused, 'unavailable'):
                self.engine.rollback(result['id'])
        self.assertEqual(history()[0]['stage'], 'recovery-required')
        self.assertNotEqual(self.main.read_bytes(), self.original)
        self.assertTrue(self.engine.rollback(result['id'])['restorationVerified'])

    def test_service_mismatch_requires_verified_retry(self):
        self.evidence['units'] = {'waybar.service': {'active': 'active', 'state': 'enabled'}}
        self.host.units = copy.deepcopy(self.evidence['units'])
        snapshot = {'adapter': 'hyprland', 'paused': [{'unit': 'waybar.service'}]}
        with patch.object(self.adapter, 'inspect', return_value=(snapshot, [])):
            result = self.apply()
        self.host.units['waybar.service']['active'] = 'failed'
        with self.assertRaisesRegex(d.Refused, 'Service restoration differs'):
            self.engine.rollback(result['id'])
        self.assertEqual(history()[0]['stage'], 'recovery-required')
        self.host.units['waybar.service']['active'] = 'active'
        self.assertTrue(self.engine.rollback(result['id'])['restorationVerified'])

    def test_unknown_service_state_is_not_a_backup(self):
        with patch.object(self.adapter, 'inspect', return_value=({'adapter': 'hyprland', 'paused': [{'unit': 'waybar.service'}]}, [])):
            self.assertIn('service restoration state', str(self.engine.preview()['plan']['blocked']))

    def test_permission_failure_before_effects_keeps_original(self):
        with patch.object(d.Transaction, 'backup', side_effect=PermissionError('fixture permission denied')):
            with self.assertRaises(PermissionError):
                self.apply(bindings=True)
        self.assertEqual(self.main.read_bytes(), self.original)
        self.assertNotIn('activate', self.adapter.calls)
        self.assertTrue(self.engine.rollback()['restorationVerified'])

    def test_standalone_legacy_recovery_needs_no_selected_release(self):
        with patch.object(d, 'ROOT', self.source), patch.object(d, 'installed', side_effect=d.Refused('no current')), patch.object(d, 'session_active', return_value=False), patch.object(d, 'recover_latest') as recover:
            d.main(['restore'])
            recover.assert_called_once_with('install')
        result = self.apply()
        with patch.object(d, 'ROOT', self.source), patch.object(d, 'installed', side_effect=d.Refused('invalid current')), patch.object(d, 'recover_latest') as recover:
            with self.assertRaisesRegex(d.Refused, 'original source'):
                d.main(['restore'])
            recover.assert_not_called()


class RuntimeTests(unittest.TestCase):
    def adapter(self):
        from compatibility.adapters import SessionAdapter
        adapter = SessionAdapter.__new__(SessionAdapter)
        adapter.name = 'portable'
        self.row = {'id': 'fixture', 'root': '/fixture', 'stage': 'kept'}
        self.running = True
        def ipc(row, *args):
            if args == ('shell', 'stop'):
                self.running = False
                return ''
            return json.dumps({'stage': 3, 'screenCount': 1})
        @contextlib.contextmanager
        def guard():
            yield
            self.assertEqual(self.row['stage'], 'starting')
            self.assertTrue(self.row['restartKept'])
            self.row['stage'] = 'kept'  # fake supervisor acknowledgment
        adapter.backend = SimpleNamespace(read_record=lambda: self.row, healthy=lambda row: {'pid': 42}, ipc=ipc,
                                          guard=guard, unlocked=lambda row: None, save=lambda row: None,
                                          cedar_rows=lambda row: [{'pid': 42}] if self.running else [])
        return adapter

    def command(self, argv):
        if argv == ['hyprctl', 'configerrors']: return ''
        if argv == ['hyprctl', '-j', 'layers']:
            return json.dumps({'monitor': {'levels': {'2': [{'namespace': 'cedar-bar', 'pid': 42}]}}})
        return 'target shell\ntarget menu\ntarget control\ntarget station'

    def test_runtime_requires_mapped_bar_and_control_interfaces(self):
        adapter = self.adapter()
        with patch.object(d, 'command', side_effect=self.command):
            self.assertTrue(adapter.validate()['healthy'])
        with patch.object(d, 'command', side_effect=lambda argv: '{}' if argv == ['hyprctl', '-j', 'layers'] else self.command(argv)):
            with self.assertRaisesRegex(d.Refused, 'bar surfaces'):
                adapter.validate()
        with patch.object(d, 'command', side_effect=lambda argv: '' if argv[0] == 'qs' else self.command(argv)):
            with self.assertRaisesRegex(d.Refused, 'interfaces'):
                adapter.validate()

    def test_restart_preserves_kept_state_and_uses_only_ipc(self):
        adapter = self.adapter()
        with patch.object(d, 'command', side_effect=self.command):
            self.assertTrue(adapter.restart()['healthy'])
        self.assertFalse(self.running)
        self.assertEqual(self.row['stage'], 'kept')

if __name__ == '__main__': unittest.main()
