"""Exercise public activation APIs through the real session state machine.

Only OS/desktop boundaries and time are simulated. Discovery, lock checks,
candidate lookup, IPC routing, transactions, approval, health checks, the
supervisor, Keep, login and restoration are production code. These fixtures
cannot establish native compositor or authentication correctness.
"""
import contextlib
import copy
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import distribution as d
import portable_providers as p
import portable_session as s
import portable_controls as controls
import setup


class YieldSupervisor(BaseException):
    """Pause between real supervisor iterations for the next user action."""


class DesktopFixture:
    def __init__(self, case, adapter='noctalia-v5', suffix='lua'):
        temporary = tempfile.TemporaryDirectory(prefix='cedar lifecycle 雨 ')
        case.addCleanup(temporary.cleanup)
        self.case, self.base, self.adapter = case, Path(temporary.name), adapter
        self.clock = 1000.0
        self.running = False
        self.locked = False
        self.qs_pending_lock = False
        self.host_available = True
        self.start_calls = []
        self.unit_calls = []
        self.approvals = []
        self.exports = []
        self.in_supervisor = False
        self.supervisor_pending = False
        self.pause_stages = {'trial', 'kept'}
        self.reload_error = ''
        self.launch_error = False
        self.external_lock = True
        self.secured_unlocks = 0
        self.test_unlock_in = 0
        self.bridge_running = False
        self.bridge_failed = False
        self.auth_failed = False
        self.suspended = False
        self.bindings = [{'modmask':64,'key':'space','dispatcher':'exec','arg':'noctalia msg launcher toggle'},
                         {'modmask':64,'key':'L','dispatcher':'exec','arg':'noctalia msg session lock'}]
        self.original_bindings = copy.deepcopy(self.bindings)
        self.session_signature = 'fixture-first-session'
        self.env = {'HOME': str(self.base/'home'), 'HYPRLAND_INSTANCE_SIGNATURE': self.session_signature,
                    'CEDAR_ADAPTER': 'hyprland', 'CEDAR_OMARCHY_SESSION': '',
                    **{'XDG_'+key+'_HOME': str(self.base/key.lower()) for key in ('CONFIG','DATA','STATE','CACHE')}}
        self.install_patch(patch.dict(os.environ, self.env))
        self.main_config = self.base/'config/hypr'/('hyprland.'+suffix)
        self.main_config.parent.mkdir(parents=True)
        self.main_config.write_text('-- existing startup and user configuration\n' if suffix == 'lua' else '# existing startup and user configuration\n')
        self.main_config.chmod(0o640)
        self.settings = self.base/'state/noctalia/settings.toml'
        self.settings.parent.mkdir(parents=True)
        self.original = '''# user preferences
[bar]
order = ["default"]
[bar.default]
enabled = true
[dock]
enabled = true
[osd]
enabled = true
[notification]
enable_daemon = true
[lock]
custom = "preserve"
[lockscreen]
enabled = true
lock_before_suspend = true
[idle]
lock_timeout = 600
[idle.behavior.lock]
enabled = true
timeout = 600
action = "lock"
[idle.behavior.sleep]
enabled = true
timeout = 1200
action = "lock_and_suspend"
[unknown]
keep = true
'''
        self.settings.write_text(self.original)
        self.settings.chmod(0o640)
        self.before_settings, self.before_startup = d.info(self.settings), d.info(self.main_config)
        if adapter == 'hyprland':
            (self.base/'config/hypr/hyprlock.conf').write_text('# existing locker\n')
        self.provider = {'pid': 701, 'start': '123', 'exe': '/fixture/noctalia', 'argv': ['noctalia'], 'deleted': False}
        self.compositor = {'pid': 702, 'start': '124', 'exe': '/fixture/Hyprland',
                           'argv': ['Hyprland', '--config', str(self.main_config)], 'deleted': False}
        self.install_patch(patch.object(p, 'processes', side_effect=self.processes))
        self.install_patch(patch.object(p, 'read_process', side_effect=self.read_process))
        self.install_patch(patch.object(p, 'process_environment', return_value=self.env))
        self.install_patch(patch.object(d.shutil, 'which', side_effect=lambda name: '/fixture/'+name))
        self.install_patch(patch.object(subprocess, 'run', side_effect=self.command))
        self.install_patch(patch.object(subprocess, 'Popen', side_effect=self.launch))
        self.install_patch(patch.object(d, 'validate', return_value='Fixture QML boundary; real QML validated separately.'))
        self.install_patch(patch.object(s.time, 'time', side_effect=lambda: self.clock))
        self.install_patch(patch.object(s.time, 'monotonic', side_effect=lambda: self.clock))
        self.install_patch(patch.object(s.time, 'sleep', side_effect=self.sleep))
        # Real installation gives public CLI commands their real installed() path.
        with contextlib.redirect_stdout(io.StringIO()):
            d.install(d.ROOT, approved=True)
        self.root = d.installed()

    def install_patch(self, item):
        item.start(); self.case.addCleanup(item.stop)

    def processes(self, names=None):
        rows = [self.compositor]
        if self.adapter == 'noctalia-v5' and self.host_available: rows.append(self.provider)
        if self.running:
            rows.append({'pid': 703, 'start': '125', 'exe': '/fixture/qs', 'argv': ['qs'], 'deleted': False})
        if self.bridge_running:
            rows.append({'pid':704,'start':'126','exe':'/fixture/hypridle','argv':['hypridle','-c',s.read_record()['trailwatch']['bridgeConfig']], 'deleted':False})
        return copy.deepcopy([row for row in rows if names is None or Path(row['exe']).name.lower() in names])

    def read_process(self, pid, names=None):
        return next((row for row in self.processes(names) if row['pid'] == pid), None)

    def native_state(self):
        values = p.tomllib.loads(self.settings.read_text())
        return {'locked': self.locked, 'barVisible': values['bar']['default']['enabled']}

    def command(self, argv, **kwargs):
        # Unknown commands are a test failure, never executed on the host.
        result, code, error = '', 0, ''
        if argv == ['qs', 'list', '--all', '-j']:
            result = json.dumps([{'pid': 703, 'config_path': str(self.root/'shell.qml')}]) if self.running else 'No running instances.\n'
        elif argv[:5] == ['qs', 'ipc', '-p', str(self.root/'shell.qml'), 'call']:
            if not self.running: raise AssertionError('IPC called before the candidate started')
            if argv[5:] == ['shell', 'isLocked']: result = 'true' if self.locked or self.qs_pending_lock else 'false'
            elif argv[5:] == ['shell', 'sessionInfo']:
                result = json.dumps({'stage': 3, 'screenCount': 1, 'externalLock': self.external_lock, 'locked': self.locked,
                                     'lockReady':True, 'lockSecure':self.locked, 'securedUnlocks':self.secured_unlocks})
            elif argv[5:] == ['lock', 'lock']:
                expected = not s.read_record().get('trailwatch', {}).get('ready', False)
                self.case.assertEqual(p.tomllib.loads(self.settings.read_text())['lockscreen']['enabled'], expected, 'Previous locker removed before secure-unlock test')
                self.locked = True; self.test_unlock_in = 2
            elif argv[5:] == ['launcher', 'toggle']:
                self.case.assertFalse(self.locked)
            elif argv[5:] == ['shell', 'stop']:
                assert not self.locked and not self.qs_pending_lock
                self.running = False
            else: raise AssertionError(argv)
        elif argv == ['hyprctl', '-j', 'monitors']:
            result = json.dumps([{'solitaryBlockedBy': ['LOCK'] if self.locked else []}])
        elif argv == ['hyprctl', '-j', 'binds']:
            result = json.dumps(self.bindings)
        elif argv == ['/fixture/hypridle', '--version']: result = 'hypridle v0.1.7'
        elif len(argv) == 3 and argv[:2] == ['qs','-p'] and argv[2].endswith('/auth-test.qml'):
            result = '' if self.auth_failed else 'CEDAR_AUTH_OK'
        elif argv[:3] == ['systemctl','--user','show'] and argv[3] == controls.bridge_unit(s.read_record()):
            result = ('loaded' if self.bridge_running else 'not-found') if '--property=LoadState' in argv else ('704' if self.bridge_running else '0')
        elif argv[:3] == ['systemctl','--user','stop']:
            self.case.assertFalse(self.locked)
            self.case.assertTrue(p.tomllib.loads(self.settings.read_text())['lockscreen']['enabled'])
            self.bridge_running = False
        elif argv == ['systemctl','suspend']:
            self.case.assertTrue(self.locked, 'Suspend before compositor lock coverage')
            self.suspended = True
        elif argv[:3] == ['busctl','--system','--json=short']:
            result = json.dumps({'type':'a(ssssuu)','data':[[['sleep','hypridle','lock before sleep','delay',os.getuid(),704]]] if self.bridge_running else [[]]})
        elif argv == ['/fixture/noctalia', '--version']: result = 'noctalia v5.2.1 (5.2.1-1-dirty)'
        elif argv == ['/fixture/noctalia', 'msg', 'status']: result = json.dumps(self.native_state())
        elif argv[:3] == ['/fixture/noctalia', 'config', 'export']:
            self.exports.append(argv[3]); result = self.settings.read_text()
        elif argv[:3] == ['busctl', '--user', 'call']:
            owner = 703 if self.running else (701 if self.adapter == 'noctalia-v5' and p.tomllib.loads(self.settings.read_text())['notification']['enable_daemon'] else None)
            if owner is None: code, error = 1, 'org.freedesktop.DBus.Error.NameHasNoOwner'
            else: result = 'u '+str(owner)
        elif argv[0] == 'systemd-run':
            if '/fixture/hypridle' in argv:
                self.bridge_running = not self.bridge_failed
                return subprocess.CompletedProcess(argv, 0, '', '')
            self.case.assertTrue(Path(argv[-4]).is_file(), 'Stable recovery helper missing')
            self.case.assertEqual(argv[-3], 'supervise')
            self.unit_calls.append(argv)
            self.supervisor_pending = True
        elif argv == ['hyprctl', 'reload']:
            row = s.read_record()
            if row and row.get('controls') and 'CEDAR CONTROLS START' in self.main_config.read_text():
                replacement = [{'modmask':sum({'SUPER':64,'SHIFT':1,'CTRL':4,'ALT':8}[m] for m in b['mods']), 'key':b['key'], 'dispatcher':'exec','arg':controls.command(b['action'])} for b in row['controls']['bindings']]
                self.bindings = [b for b in self.bindings if not any(b['modmask']==n['modmask'] and b['key'].lower()==n['key'].lower() for n in replacement)]+replacement
            else: self.bindings = copy.deepcopy(self.original_bindings)
            result = 'ok'
        elif argv == ['hyprctl', 'configerrors']: result = self.reload_error
        else: raise AssertionError('Unexpected external command: '+repr(argv))
        return subprocess.CompletedProcess(argv, code, result, error)

    def launch(self, argv, **kwargs):
        self.case.assertEqual(argv, ['qs', '-n', '-p', str(self.root/'shell.qml')])
        self.case.assertFalse(self.running, 'Duplicate CEDAR launch')
        self.case.assertFalse(self.locked, 'Launch while locked')
        if self.adapter == 'noctalia-v5': self.case.assertFalse(self.native_state()['barVisible'])
        self.external_lock = kwargs['env']['CEDAR_EXTERNAL_LOCK'] == '1'
        self.case.assertNotIn('CEDAR_OMARCHY_SESSION', kwargs['env'])
        self.start_calls.append((argv, kwargs['env']))
        self.running = not self.launch_error
        return type('FixtureProcess', (), {'pid': 703})()

    def cycle(self, pause_stages=None):
        self.in_supervisor = True
        self.pause_stages = {'trial', 'kept'} if pause_stages is None else pause_stages
        self.iterations = 0
        row = s.read_record()
        try:
            s.supervise(row['id'], row['generation'])
        except YieldSupervisor:
            pass
        finally:
            self.in_supervisor = False

    def sleep(self, seconds):
        self.clock += seconds
        if self.test_unlock_in:
            self.test_unlock_in -= 1
            if not self.test_unlock_in:
                self.locked = False; self.secured_unlocks += 1
        if self.in_supervisor:
            self.iterations += 1
            if self.iterations > 200: raise AssertionError('Supervisor did not reach the expected state')
            if s.read_record()['stage'] in self.pause_stages: raise YieldSupervisor()
        elif self.supervisor_pending:
            self.cycle()

    def start(self, *options):
        with contextlib.redirect_stdout(io.StringIO()): d.main(['try', '--approve-trial', *options])
        self.case.assertEqual(s.read_record()['stage'], 'trial')
        self.case.assertTrue(self.running)

    def keep(self, login=False):
        with contextlib.redirect_stdout(io.StringIO()):
            d.main(['activate', '--approve-login'] if login else ['keep'])

    def restore(self):
        with contextlib.redirect_stdout(io.StringIO()): d.main(['restore'])
        self.case.assertEqual(s.read_record()['stage'], 'restored')
        self.case.assertFalse(self.running)
        self.case.assertEqual(d.info(self.settings), self.before_settings)
        self.case.assertEqual(d.info(self.main_config), self.before_startup)


class PortableLifecycle(unittest.TestCase):
    def test_cedar_controls_secure_unlock_then_handoff_login_and_restore(self):
        world = DesktopFixture(self)
        world.start('--cedar-launcher', '--trailwatch')
        row = s.read_record()
        self.assertEqual(row['locker'], 'trailwatch')
        self.assertFalse(world.external_lock)
        self.assertTrue(row['trailwatch']['lockTested'])
        self.assertGreater(world.secured_unlocks, 0)
        self.assertTrue(world.bridge_running)
        values = p.tomllib.loads(world.settings.read_text())
        self.assertFalse(values['lockscreen']['enabled'])
        self.assertEqual(values['idle']['behavior']['lock']['timeout'], 600)
        self.assertEqual(values['idle']['behavior']['lock']['action'], 'command')
        self.assertTrue(values['idle']['behavior']['sleep']['command'].endswith('lock --suspend'))
        d.main(['launcher'])
        world.keep(); world.keep(login=True)
        self.assertIn('CEDAR LOGIN START', Path(row['controls']['loginFile']).read_text())
        world.restore()
        self.assertFalse(world.bridge_running)
        self.assertEqual(world.bindings, world.original_bindings)
        self.assertFalse(Path(row['controls']['file']).exists())
        self.assertFalse(Path(row['controls']['loginFile']).exists())

    def test_new_wizard_controls_choices_use_actual_production_handoff(self):
        world = DesktopFixture(self)
        answers = iter(['y', '3', 'y', 'y', 'y', 'y', 'y', 'y'])
        with patch.object(sys.stdin, 'isatty', return_value=True), patch.object(d, 'capabilities', return_value=[]), patch.object(d, 'package_plan', return_value={'packages': []}), patch('builtins.input', side_effect=lambda _: next(answers)), contextlib.redirect_stdout(io.StringIO()):
            setup.main([])
        self.assertTrue(s.read_record()['login'])
        self.assertEqual(s.read_record()['locker'], 'trailwatch')
        self.assertTrue(s.read_record()['trailwatch']['lockTested'])
        world.restore()

    def test_launcher_choice_alone_preserves_existing_authentication(self):
        world = DesktopFixture(self)
        world.start('--cedar-launcher')
        self.assertEqual(s.read_record()['locker'], 'noctalia')
        self.assertTrue(world.external_lock)
        self.assertFalse(world.bridge_running)
        self.assertTrue(p.tomllib.loads(world.settings.read_text())['lockscreen']['enabled'])
        self.assertIn(world.original_bindings[1], world.bindings)
        world.keep(); world.keep(login=True); world.restore()

    def test_pam_failure_keeps_all_existing_controls(self):
        world = DesktopFixture(self)
        world.auth_failed = True
        with self.assertRaisesRegex(d.Refused, 'Authentication test did not succeed'):
            world.start('--cedar-launcher', '--trailwatch')
        self.assertFalse(s.record_path().exists())
        self.assertFalse(world.running)
        self.assertFalse(world.bridge_running)
        self.assertEqual(d.info(world.settings), world.before_settings)
        self.assertEqual(d.info(world.main_config), world.before_startup)

    def test_failed_sleep_bridge_restores_without_disabling_original_locker(self):
        world = DesktopFixture(self)
        world.bridge_failed = True
        with self.assertRaisesRegex(d.Refused, 'sleep bridge is not running'):
            world.start('--cedar-launcher', '--trailwatch')
        self.assertEqual(s.read_record()['stage'], 'restored')
        self.assertFalse(world.running)
        self.assertEqual(d.info(world.settings), world.before_settings)
        self.assertEqual(d.info(world.main_config), world.before_startup)

    def test_conflicting_shortcut_does_not_silently_remove_another_action(self):
        world = DesktopFixture(self)
        world.bindings.append({'modmask':64,'key':'space','dispatcher':'exec','arg':'an-unrelated-action'})
        with self.assertRaisesRegex(d.Refused, 'multiple actions'):
            world.start('--cedar-launcher')
        self.assertFalse(s.record_path().exists())
        self.assertEqual(d.info(world.main_config), world.before_startup)

    def test_controls_plan_detects_later_main_file_edit_before_backup(self):
        world = DesktopFixture(self)
        original = d.approve
        def changed(*args, **kwargs):
            original(*args, **kwargs)
            world.main_config.write_text('-- later manual edit\n')
        with patch.object(d, 'approve', side_effect=changed):
            with self.assertRaisesRegex(d.Refused, 'changed after the plan'):
                world.start('--cedar-launcher')
        self.assertEqual(world.main_config.read_text(), '-- later manual edit\n')
        self.assertFalse(world.running)

    def test_controls_login_rejection_preserves_trial_binding_and_previous_auth(self):
        world = DesktopFixture(self)
        world.start('--cedar-launcher', '--trailwatch'); world.keep()
        world.reload_error = 'fixture rejects login hook'
        with self.assertRaisesRegex(d.Refused, 'rejected the startup entry'):
            world.keep(login=True)
        row = s.read_record()
        self.assertEqual(Path(row['controls']['loginFile']).read_text(), '')
        self.assertTrue(world.running)
        self.assertFalse(row['login'])
        world.reload_error = ''; world.restore()

    def test_public_lock_and_suspend_use_trailwatch_with_coverage(self):
        world = DesktopFixture(self)
        world.start('--cedar-launcher', '--trailwatch'); world.keep()
        d.main(['lock', '--suspend'])
        self.assertTrue(world.locked)
        self.assertTrue(world.suspended)
        with self.assertRaisesRegex(d.Refused, 'Session locked'): d.main(['launcher'])
        world.sleep(.1); world.sleep(.1)
        world.restore()

    def test_missing_sleep_coverage_never_requests_suspend(self):
        world = DesktopFixture(self)
        world.start('--trailwatch'); world.keep()
        with patch.object(p, 'compositor_covered', return_value=False):
            with self.assertRaisesRegex(d.Refused, 'coverage was not confirmed'):
                d.main(['lock', '--suspend'])
        self.assertFalse(world.suspended)
        world.restore()

    def test_next_login_restores_selected_launcher_and_trailwatch(self):
        world = DesktopFixture(self)
        world.start('--cedar-launcher', '--trailwatch'); world.keep(); world.keep(login=True)
        previous = s.read_record()
        world.running = world.bridge_running = False
        world.secured_unlocks = 0
        world.provider.update(pid=801, start='456')
        with patch.dict(os.environ, {'HYPRLAND_INSTANCE_SIGNATURE':'fixture-next-session'}):
            d.main(['session-login'])
        world.cycle()
        row = s.read_record()
        self.assertNotEqual(row['generation'], previous['generation'])
        self.assertTrue(world.bridge_running)
        self.assertEqual(row['stage'], 'kept')
        self.assertFalse(world.external_lock)
        self.assertFalse(p.tomllib.loads(world.settings.read_text())['lockscreen']['enabled'])
        world.restore()

    def test_approved_native_trial_keep_login_and_restore(self):
        world = DesktopFixture(self)
        world.start()
        self.assertEqual(world.exports, ['full', 'merged'])
        self.assertEqual(s.read_record()['root'], str(world.root))
        world.keep(); world.keep(login=True)
        row = s.read_record()
        self.assertTrue(row['login'])
        self.assertEqual(row['stage'], 'kept')
        self.assertIn('CEDAR LOGIN START', world.main_config.read_text())
        self.assertIn('hl.on("hyprland.start"', world.main_config.read_text())
        world.restore()

    def test_plain_hyprland_approved_trial_and_conf_startup(self):
        world = DesktopFixture(self, adapter='hyprland', suffix='conf')
        world.start(); world.keep(); world.keep(login=True)
        self.assertIn('exec-once = ', world.main_config.read_text())
        self.assertEqual(s.read_record()['locker'], 'hyprlock')
        self.assertEqual(world.exports, [])
        world.restore()

    def test_next_login_uses_new_provider_identity_then_restores(self):
        world = DesktopFixture(self)
        world.start(); world.keep(); world.keep(login=True)
        previous = s.read_record()
        world.running = False
        world.provider.update(pid=801, start='456')
        with patch.dict(os.environ, {'HYPRLAND_INSTANCE_SIGNATURE': 'fixture-next-session'}):
            d.main(['session-login'])
        world.cycle()
        current = s.read_record()
        self.assertNotEqual(current['generation'], previous['generation'])
        self.assertEqual(current['provider']['pid'], 801)
        self.assertEqual(current['stage'], 'kept')
        self.assertEqual(len(world.start_calls), 2)
        world.restore()

    def test_expired_native_trial_restores_settings_without_keep(self):
        world = DesktopFixture(self)
        world.start(); world.clock += 121
        world.cycle(pause_stages=set())
        self.assertFalse(world.running)
        self.assertEqual(s.read_record()['stage'], 'restored')
        self.assertEqual(d.info(world.settings), world.before_settings)

    def test_shell_start_failure_recovers_and_reports_the_actual_stage(self):
        world = DesktopFixture(self)
        world.launch_error = True
        with contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaisesRegex(d.Refused, 'Trial did not start: CEDAR is not running'):
                d.main(['try', '--approve-trial'])
        self.assertFalse(world.running)
        self.assertEqual(s.read_record()['stage'], 'restored')
        self.assertEqual(d.info(world.settings), world.before_settings)
        self.assertEqual(d.info(world.main_config), world.before_startup)

    def test_keep_rechecks_pending_lock_before_confirmation(self):
        world = DesktopFixture(self)
        world.start(); world.qs_pending_lock = True
        with self.assertRaisesRegex(d.Refused, 'CEDAR is locking or locked'): world.keep()
        self.assertEqual(s.read_record()['stage'], 'trial')
        self.assertTrue(world.running)
        world.qs_pending_lock = False
        world.restore()

    def test_repeated_keep_and_login_do_not_duplicate_startup(self):
        world = DesktopFixture(self)
        world.start(); world.keep(); world.keep(); world.keep(login=True)
        initial = world.main_config.read_bytes()
        world.keep(login=True)
        self.assertEqual(world.main_config.read_bytes(), initial)
        self.assertEqual(world.main_config.read_text().count('CEDAR LOGIN START'), 1)
        self.assertEqual(len(world.start_calls), 1)
        world.restore()

    def test_user_startup_edit_is_preserved_before_restore_stops_shell(self):
        world = DesktopFixture(self)
        world.start(); world.keep(); world.keep(login=True)
        world.main_config.write_text(world.main_config.read_text()+'\n-- later user change\n')
        with self.assertRaisesRegex(d.Refused, 'Later user edit preserved'): d.main(['restore'])
        self.assertTrue(world.running)
        self.assertIn('later user change', world.main_config.read_text())

    def test_approved_trial_checks_lock_before_any_provider_write(self):
        world = DesktopFixture(self)
        original_approve = d.approve
        def approve(*args, **kwargs):
            original_approve(*args, **kwargs)
            world.locked = True
        with patch.object(d, 'approve', side_effect=approve), contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaisesRegex(d.Refused, 'Session locked'): d.main(['try', '--approve-trial'])
        self.assertEqual(world.unit_calls, [])
        self.assertFalse(s.record_path().exists())
        self.assertEqual(d.info(world.settings), world.before_settings)

    def test_lock_defers_restore_until_unlocked(self):
        world = DesktopFixture(self)
        world.start(); world.locked = True
        with self.assertRaisesRegex(d.Refused, 'Session locked'): d.main(['restore'])
        self.assertTrue(world.running)
        self.assertFalse(world.native_state()['barVisible'])
        world.locked = False
        world.cycle(pause_stages=set())
        self.assertEqual(s.read_record()['stage'], 'restored')
        self.assertEqual(d.info(world.settings), world.before_settings)

    def test_later_user_edits_block_restore_before_stopping_cedar(self):
        world = DesktopFixture(self)
        world.start()
        world.settings.write_text(world.settings.read_text()+'\n[new_preference]\nkeep = true\n')
        with self.assertRaisesRegex(d.Refused, 'Later edits are preserved'): d.main(['restore'])
        self.assertTrue(world.running)
        self.assertIn('new_preference', world.settings.read_text())

    def test_startup_config_rejection_restores_only_owned_change(self):
        world = DesktopFixture(self)
        world.start(); world.keep()
        world.reload_error = 'fixture syntax rejection'
        with contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaisesRegex(d.Refused, 'rejected the startup entry'): world.keep(login=True)
        self.assertEqual(d.info(world.main_config), world.before_startup)
        self.assertFalse(s.read_record()['login'])
        self.assertTrue(world.running)
        world.reload_error = ''
        world.restore()

    def test_installer_choice_three_runs_trial_keep_and_login(self):
        world = DesktopFixture(self)
        # Only platform dependency probing is stubbed; installation and all
        # option-3 session actions run their real public implementations.
        answers = iter(['y', '3', 'n', 'n', 'y', 'y', 'y', 'y'])
        with patch.object(sys.stdin, 'isatty', return_value=True), patch.object(d, 'capabilities', return_value=[]), patch.object(d, 'package_plan', return_value={'packages': []}), patch('builtins.input', side_effect=lambda _: next(answers)), contextlib.redirect_stdout(io.StringIO()):
            setup.main([])
        self.assertTrue(s.read_record()['login'])
        self.assertEqual(s.read_record()['stage'], 'kept')
        self.assertEqual(len(world.start_calls), 1)
        world.restore()


if __name__ == '__main__': unittest.main()
