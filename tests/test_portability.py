"""Portable runtime and provider transactions; no live desktop is changed."""
import copy
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
import desktop_runtime as runtime
import portable_providers as p
import portable_session as s
import desktop


class Portable(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix='cedar standalone 雨 ')
        self.addCleanup(temp.cleanup)
        self.base = Path(temp.name)
        self.env = patch.dict(os.environ, {'HOME': str(self.base / 'home'), 'CEDAR_ADAPTER': 'hyprland',
            'CEDAR_OMARCHY_SESSION': '', 'CEDAR_BACKGROUND': 'cedar',
            **{'XDG_' + key + '_HOME': str(self.base / key.lower()) for key in ('CONFIG', 'DATA', 'STATE', 'CACHE')}})
        self.env.start()
        self.addCleanup(self.env.stop)
        instances = patch.object(s, 'cedar_rows', return_value=[])
        instances.start(); self.addCleanup(instances.stop)

    def row(self, adapter='hyprland'):
        return {'root': str(d.ROOT), 'id': 'fixture', 'generation': 'one', 'adapter': adapter,
                'stage': 'prepared', 'locker': 'trailwatch' if adapter == 'hyprland' else 'noctalia',
                'background': 'cedar', 'paused': [], 'pausedIntents': [], 'login': False,
                'statusFile': str(self.base / 'status.json')}

    def journal(self, row, target=None):
        tx = d.Transaction('portable-session')
        if target: tx.backup(target)
        row['journal'] = str(tx.path)
        return tx

    def test_missing_packages_never_install_another_desktop(self):
        with patch.object(d.shutil, 'which', return_value=None):
            packages = d.missing_packages(d.ROOT)
            caps = d.capabilities(d.ROOT)
        self.assertIn('quickshell', packages)
        self.assertFalse({'omarchy', 'noctalia', 'hyprland', 'nvidia-utils', 'networkmanager'} & set(packages))
        self.assertFalse(any('omarchy' in r['id'] for r in caps))

    def test_compatible_local_quickshell_is_not_replaced_by_package_checks(self):
        with patch.object(d, 'capabilities', return_value=[]), patch.object(d.shutil, 'which', return_value='/fixture/qs'), patch.object(d, 'validate_imports') as imports:
            self.assertEqual(d.missing_packages(d.ROOT), [])
        imports.assert_called_once_with(d.ROOT)

    def test_incompatible_installed_runtime_stops_package_plan(self):
        with patch.object(d, 'capabilities', return_value=[]), patch.object(d.shutil, 'which', return_value='/fixture/qs'), patch.object(d, 'validate_imports', side_effect=d.Refused('runtime mismatch')), patch.object(d, 'command') as command:
            with self.assertRaisesRegex(d.Refused, 'runtime mismatch'): d.package_plan(d.ROOT, True, True)
        command.assert_not_called()

    def test_wizard_root_and_canceled_package_plan_never_install(self):
        import setup
        with patch.object(d.os, 'getuid', return_value=0), patch.object(d, 'install') as install:
            with self.assertRaisesRegex(d.Refused, 'never root'): setup.main([])
        install.assert_not_called()
        with patch.object(d.os, 'getuid', return_value=1000), patch.object(sys.stdin, 'isatty', return_value=True), patch.object(d.shutil, 'which', return_value='/fixture/hyprctl'), patch.object(d, 'missing_packages', return_value=['quickshell']), patch('builtins.input', return_value='n'), patch.object(d, 'install') as install, patch.object(d, 'package_plan') as packages:
            with self.assertRaisesRegex(d.Refused, 'Canceled'): setup.main([])
        install.assert_not_called(); packages.assert_not_called()

    def test_desktop_wallpaper_preserves_unknown_preferences_offline(self):
        image = self.base / 'a wallpaper 雨.png'
        image.write_bytes(b'local fixture')
        d.write_json(runtime.config() / 'desktop.json', {'futureKey': {'keep': True}})
        with patch.object(runtime, 'run') as run:
            runtime.set_wallpaper(str(image))
            run.assert_not_called()
        self.assertEqual(runtime.desktop(), {'futureKey': {'keep': True}, 'wallpaper': str(image)})
        self.assertEqual(runtime.wallpapers()['selected'], str(image))
        self.assertFalse((self.base / 'state/omarchy').exists())

    def test_external_wallpaper_is_preserved(self):
        image = self.base / 'wall.png'; image.touch()
        with patch.dict(os.environ, {'CEDAR_BACKGROUND': 'external'}):
            with self.assertRaisesRegex(RuntimeError, 'existing desktop'):
                runtime.set_wallpaper(str(image))
        self.assertFalse((runtime.config() / 'desktop.json').exists())

    def test_custom_themes_are_data_not_code(self):
        d.write_json(runtime.config() / 'themes/night.json', {'name': 'Night', 'colors': {'green': '#00aa77'}})
        runtime.set_theme('night')
        self.assertEqual(d.read_json(runtime.config() / 'theme.json')['colors'], {'green': '#00aa77'})
        with self.assertRaises(ValueError): runtime.set_theme('../outside')
        with self.assertRaises(ValueError): runtime.validate_palette({'colors': {'green': 'https://remote/image'}})
        runtime.set_theme('cedar')
        self.assertEqual(d.read_json(runtime.config() / 'theme.json')['colors'], {})

    def test_editor_uses_actual_default(self):
        with patch.object(runtime, 'run', return_value='chosen.desktop'), patch.object(runtime.subprocess, 'Popen') as spawn:
            runtime.launch('editor')
            self.assertEqual(spawn.call_args.args[0], ['gtk-launch', 'chosen.desktop'])

    def test_menu_routes_every_action_to_real_ipc(self):
        menu = d.read_json(d.ROOT / 'menus/cedar-menu.jsonc')
        with patch.object(runtime, 'ipc') as call:
            for item in menu.values():
                if 'action' not in item: continue
                self.assertTrue(item['action'].startswith('cedar:'))
                runtime.main(item['action'][6:].split())
            self.assertGreater(call.call_count, 12)
        self.assertIn('apps', menu)
        self.assertNotIn('omarchy', json.dumps(menu).lower())

    def test_noctalia_v4_changes_only_approved_surfaces(self):
        original = {'settingsVersion': 59, 'bar': {'position': 'bottom', 'displayMode': 'auto_hide',
            'screenOverrides': [{'name': 'TEST-1', 'displayMode': 'auto_hide', 'widgets': ['Clock']}]},
            'lockScreen': {'custom': 'keep'}, 'idle': {'lockTimeout': 600}, 'future': {'unknown': True}}
        before = copy.deepcopy(original)
        changed = p.v4_settings(original)
        self.assertEqual(original, before)
        self.assertEqual(changed['idle'], original['idle'])
        self.assertEqual(changed['lockScreen'], original['lockScreen'])
        self.assertEqual(changed['future'], original['future'])
        self.assertFalse(changed['notifications']['enabled'])
        self.assertEqual(changed['bar']['screenOverrides'][0]['displayMode'], 'always_visible')
        with self.assertRaises(d.Refused): p.v4_settings({'settingsVersion': 100})

    def test_native_toml_preserves_comments_and_unknown_keys(self):
        original = '# user notes\n[notification]\nenable_daemon = true\ncustom = "keep"\n[lock]\nmethod = "system"\n'
        text = p.toml_overrides(original, [('notification', 'enable_daemon', False), ('bar.default', 'enabled', False)])
        data = p.tomllib.loads(text)
        self.assertIn('# user notes', text)
        self.assertEqual(data['notification']['custom'], 'keep')
        self.assertEqual(data['lock']['method'], 'system')
        self.assertFalse(data['bar']['default']['enabled'])
        self.assertEqual(p.toml_overrides(text, [('notification', 'enable_daemon', False), ('bar.default', 'enabled', False)]), text)

    def test_native_inline_table_refuses_without_damage(self):
        with self.assertRaises(d.Refused):
            p.toml_overrides('notification = { enable_daemon = true }\n', [('notification', 'enable_daemon', False)])

    def test_lock_unknown_and_partial_coverage_fail_closed(self):
        with patch.object(d, 'command', return_value='[{"name":"TEST"}]'):
            with self.assertRaises(d.Refused): p.compositor_locked()
        with patch.object(d, 'command', return_value='[{"solitaryBlockedBy":["LOCK"]},{"solitaryBlockedBy":[]}]'):
            self.assertTrue(p.compositor_locked())
            self.assertFalse(p.compositor_covered())

    def test_prepare_lock_check_precedes_writes(self):
        row = self.row(); tx = self.journal(row)
        with patch.object(p, 'locked', return_value=True), patch.object(p, 'pause') as pause:
            with self.assertRaises(d.Refused): s.prepare(row)
        pause.assert_not_called()
        self.assertEqual(d.read_json(tx.path)['stage'], 'inspect')

    def test_pending_cedar_lock_blocks_mutation_before_compositor_coverage(self):
        with patch.object(p, 'locked', return_value=False), patch.object(s, 'cedar_rows', return_value=[{'pid': 42}]), patch.object(s, 'ipc', return_value='true'):
            with self.assertRaisesRegex(d.Refused, 'locking or locked'): s.unlocked(self.row())

    def test_v4_bar_waits_for_settings_reload(self):
        row = self.row('noctalia-v4'); row['providerSource'] = '/fixture/shell.qml'
        with patch.object(p, 'qs_ipc', return_value='{"settings":{"notifications":{"enabled":true}}}') as ipc:
            with self.assertRaisesRegex(d.Refused, 'Waiting for Noctalia'): p.hide_bar(row)
            self.assertEqual(ipc.call_count, 1)

    def test_pause_intent_survives_failure(self):
        row = self.row(); row['paused'] = [{'pid': 123}]; self.journal(row)
        with patch.object(p, 'locked', return_value=False), patch.object(p, 'same_process', return_value=True), patch.object(p, 'pause', side_effect=OSError('interrupted')):
            with self.assertRaises(OSError): s.prepare(row)
        self.assertEqual(s.read_record()['pausedIntents'], [123])

    def test_provider_pid_reuse_never_gets_signaled(self):
        with patch.object(p, 'same_process', side_effect=[True, False]), patch.object(os, 'pidfd_open', return_value=9), patch.object(os, 'close'), patch.object(p.signal, 'pidfd_send_signal') as send:
            with self.assertRaises(d.Refused): p.pause({'pid': 123})
        send.assert_not_called()

    def test_restore_preserves_later_edit_before_stopping_cedar(self):
        row = self.row(); target = self.base / 'config.conf'; target.write_text('original')
        tx = self.journal(row, target); tx.apply_file(tx.record['files'][0], b'cedar')
        target.write_text('later user edit')
        with patch.object(s, 'no_graphical_session', return_value=False), patch.object(s, 'unlocked'), patch.object(s, 'ipc') as ipc:
            with self.assertRaises(d.Refused): s.restore(row)
            ipc.assert_not_called()
        self.assertEqual(target.read_text(), 'later user edit')

    def test_offline_restore_needs_no_qt_dbus_or_internet(self):
        row = self.row(); target = self.base / 'config'; target.write_text('original'); target.chmod(0o640)
        before = d.info(target); tx = self.journal(row, target); tx.apply_file(tx.record['files'][0], b'cedar')
        with patch.object(s, 'no_graphical_session', return_value=True), patch.object(s, 'ipc') as ipc, patch.object(p, 'resume') as resume:
            s.restore(row)
        ipc.assert_not_called(); resume.assert_not_called()
        self.assertEqual(d.info(target), before)
        self.assertEqual(s.read_record()['stage'], 'restored')

    def test_noctalia_serializer_whitespace_is_safe_but_user_edit_is_not(self):
        row = self.row('noctalia-v4'); path = self.base / 'settings.json'
        path.write_text('{"user":"original"}')
        row.update(providerSettings=str(path), settingsAfter='{"notifications":{"enabled":false}}')
        tx = self.journal(row, path); tx.apply_file(tx.record['files'][0], row['settingsAfter'].encode())
        path.write_text(json.dumps(json.loads(row['settingsAfter']), indent=4))
        s.normalize_provider_record(row)
        d.check_restore_journal(tx.path)
        path.write_text('{"notifications":{"enabled":true}}')
        with self.assertRaises(d.Refused): s.normalize_provider_record(row)

    def test_cedar_cannot_start_while_other_notification_owner_exists(self):
        row = self.row(); self.journal(row)
        with patch.object(s, 'unlocked'), patch.object(p, 'notification_owner', return_value=789), patch.object(subprocess, 'Popen') as spawn:
            with self.assertRaisesRegex(d.Refused, 'notification provider'): s.start_cedar(row)
        spawn.assert_not_called()

    def test_existing_locker_failure_does_not_unlock(self):
        row = self.row('noctalia-v5'); row['provider'] = {}
        with patch.object(p, 'compositor_locked', return_value=False), patch.object(p, 'same_process', return_value=False):
            with self.assertRaisesRegex(d.Refused, 'authentication host'): p.locked(row)

    def test_plain_hyprland_does_not_require_an_omarchy_binary(self):
        with patch.object(p, 'compositor_locked', return_value=False), patch.object(p, 'processes', return_value=[]), patch.object(p, 'qs_instances', return_value=[]), patch.object(p, 'notification_owner', return_value=None):
            row = p.inspect(d.ROOT)
        self.assertEqual(row['adapter'], 'hyprland')
        self.assertEqual(row['locker'], 'trailwatch')

    def test_running_unknown_quickshell_is_not_stopped(self):
        with patch.object(p, 'compositor_locked', return_value=False), patch.object(p, 'processes', return_value=[]), patch.object(p, 'qs_instances', return_value=[{'config_path': str(self.base/'shell.qml')}]), patch.object(p, 'pause') as pause:
            with self.assertRaises(d.Refused): p.inspect(d.ROOT)
        pause.assert_not_called()

    def test_conf_and_lua_settings_preserve_geometry_and_argv(self):
        state = {'input': {'kb_layout': 'us', 'touchpad:tap-to-click': True},
                 'bindings': [{'keys': 'SUPER + F8', 'command': 'my-editor "a file"', 'description': 'Editor'}],
                 'monitors': [{'name': 'TEST-1', 'mode': '1920x1080@60.00', 'x': -1920, 'y': 0, 'scale': 1, 'transform': 0}]}
        with patch.object(desktop, 'MAIN', self.base/'hyprland.conf'):
            text = desktop.render(state)
            self.assertIn('input:touchpad:tap-to-click = true', text)
            self.assertIn('monitor = TEST-1, 1920x1080@60.00, -1920x0, 1, transform, 0', text)
            self.assertIn('exec, my-editor "a file"', text)
            self.assertIn('generated.conf', desktop.loader(self.base/'paths with spaces 雨'))
            with self.assertRaises(ValueError): desktop.conf_value('value\nexec = evil')
        with patch.object(desktop, 'MAIN', self.base/'hyprland.lua'):
            self.assertIn('hl.config', desktop.render(state))
            self.assertIn('generated.lua', desktop.loader())

    def test_managed_startup_target_is_not_followed(self):
        path = self.base/'config'; outside = self.base/'outside'; outside.mkdir(); path.symlink_to(outside)
        with self.assertRaises(d.Refused): p.safe_target(path/'hyprland.conf')

    def test_failed_password_test_never_changes_integration(self):
        with patch.object(Path, 'is_file', return_value=True), patch.object(subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, '', '')):
            with self.assertRaisesRegex(d.Refused, 'Authentication test did not succeed'): s.authenticate(d.ROOT)
        self.assertFalse(record_exists := s.record_path().exists())

    def test_startup_is_owned_and_format_specific(self):
        helper = d.paths()['data'] / 'recovery/portable_session.py'
        for suffix in ('conf', 'lua'):
            path = self.base / ('hyprland.' + suffix)
            original = '# ordinary config\n' if suffix == 'conf' else '-- ordinary config\n'
            path.write_text(original)
            with patch.object(p, 'main_config', return_value=path):
                selected, content = s.startup_entry(self.row())
            self.assertEqual(selected, path)
            self.assertTrue(content.decode().startswith(original))
            self.assertIn(str(helper), content.decode())
            self.assertNotIn('omarchy', content.decode())
            self.assertIn('exec-once = ' if suffix == 'conf' else 'hl.on(', content.decode())
            self.assertEqual(path.read_text(), original)  # planning is read-only

    def test_login_does_not_forget_original_provider_when_absent(self):
        row = self.row()
        row.update(stage='kept', login=True, sessionSignature='previous',
                   paused=[{'pid':42, 'exe':'/fixture/waybar', 'argv':['waybar']}])
        row['pausedProviders'] = copy.deepcopy(row['paused'])
        s.save(row)
        with patch.dict(os.environ, {'HYPRLAND_INSTANCE_SIGNATURE':'new'}), patch.object(p, 'processes', return_value=[]), patch.object(s, 'spawn') as spawn:
            with self.assertRaises(d.Refused): s.login()
        spawn.assert_not_called()
        self.assertEqual(s.read_record()['pausedProviders'], row['pausedProviders'])
        self.assertEqual(s.read_record()['sessionSignature'], 'previous')

    def test_interrupted_pause_is_retried_only_for_original_identity(self):
        row = self.row(); row['paused'] = [{'pid':123}]; row['pausedIntents'] = [123]
        self.journal(row)
        with patch.object(p, 'locked', return_value=False), patch.object(p, 'same_process', return_value=True), patch.object(p, 'pause') as pause:
            s.prepare(row)
        pause.assert_called_once_with({'pid':123})
        self.assertEqual(s.read_record()['stage'], 'starting')

    def test_noctalia_version_gate_is_rechecked_at_login(self):
        row = self.row('noctalia-v5')
        row.update(stage='kept', login=True, sessionSignature='old')
        s.save(row)
        with patch.dict(os.environ, {'HYPRLAND_INSTANCE_SIGNATURE':'new'}), patch.object(p, 'verify_noctalia', side_effect=d.Refused('changed version')), patch.object(s, 'spawn') as spawn:
            with self.assertRaisesRegex(d.Refused, 'changed version'): s.login()
        spawn.assert_not_called()

    def test_full_supervised_noctalia_timeout_restores_original_settings(self):
        # Simulated IPC/processes; the on-disk transaction and supervisor are real.
        root = self.base / 'installed candidate'; root.mkdir()
        d.write_json(root / 'release-files.json', {})
        row = self.row('noctalia-v4'); row['root'] = str(root)
        target = self.base / 'noctalia/settings.json'; target.parent.mkdir()
        target.write_text('{"settingsVersion":59,"user":"preserved"}')
        target.chmod(0o640); before = d.info(target)
        row.update(providerSettings=str(target), settingsAfter='{"settingsVersion":59,"notifications":{"enabled":false},"user":"preserved"}',
                   providerSource=str(self.base/'noctalia/shell.qml'), providerExe='/fixture/qs', barWasVisible=True)
        self.journal(row, target); s.save(row)
        state = {'running':False, 'time':1000, 'loops':0, 'restoredBar':False}
        def ipc(_, *args):
            if args == ('shell', 'sessionInfo'):return json.dumps({'stage':3,'screenCount':1,'externalLock':True})
            if args == ('shell', 'isLocked'):return 'false'
            if args == ('shell', 'stop'):state['running']=False; return ''
            raise AssertionError(args)
        def tick(_):
            state['loops'] += 1
            if state['loops'] > 8: raise AssertionError('Supervisor did not restore')
            if s.read_record()['stage'] == 'trial': state['time'] += 130
        with patch.object(s, 'no_graphical_session', return_value=False), patch.object(p, 'locked', return_value=False), \
             patch.object(p, 'processes', return_value=[]), patch.object(p, 'main_config', side_effect=d.Refused('fixture')), \
             patch.object(p, 'hide_bar'), patch.object(p, 'restore_bar', side_effect=lambda _:state.update(restoredBar=True)), \
             patch.object(p, 'noctalia_state', return_value={'locked':False,'barVisible':False}), \
             patch.object(p, 'notification_owner', side_effect=lambda:991 if state['running'] else None), \
             patch.object(s, 'cedar_rows', side_effect=lambda _: [{'pid':991}] if state['running'] else []), \
             patch.object(s, 'ipc', side_effect=ipc), patch.object(s.subprocess, 'Popen', side_effect=lambda *a,**kw:state.update(running=True)), \
             patch.object(s.time, 'time', side_effect=lambda:state['time']), patch.object(s.time, 'sleep', side_effect=tick):
            s.supervise(row['id'], row['generation'])
        self.assertEqual(s.read_record()['stage'], 'restored')
        self.assertFalse(state['running']); self.assertTrue(state['restoredBar'])
        self.assertEqual(d.info(target), before)

    def test_portable_palette_does_not_change_startup_or_shortcuts(self):
        for name in ('hyprland.conf', 'hyprland.lua'):
            text = (d.ROOT/'themes'/name).read_text()
            for forbidden in ('omarchy', 'o.bind', 'unbind', 'exec-once', 'theme-sync'):
                self.assertNotIn(forbidden, text)



if __name__ == '__main__': unittest.main()
