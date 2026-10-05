"""Portable runtime and provider transactions; no live desktop is changed."""
import copy
import contextlib
import io
import json
import os
import platform
import select
import shutil
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

    def proc_fixture(self):
        directory = self.base/'proc'
        directory.mkdir(exist_ok=True)
        mount = patch.object(p, 'PROC', directory)
        mount.start(); self.addCleanup(mount.stop)
        return directory

    def proc_entry(self, root, pid, comm, exe=None, argv=None, state='S', start='456'):
        path = root/str(pid); path.mkdir()
        (path/'stat').write_text(str(pid)+' ('+comm+') '+' '.join([state]+['0']*18+[start])+'\n')
        if exe is not None: (path/'exe').symlink_to(exe)
        if argv is not None:
            (path/'cmdline').write_bytes(b'\0'.join(os.fsencode(arg) for arg in argv)+b'\0')
        return path

    def deny_exe(self, path):
        original = os.readlink
        def readlink(target, *args, **kwargs):
            if Path(target) == path/'exe': raise PermissionError('fixture protected executable')
            return original(target, *args, **kwargs)
        guard = patch.object(p.os, 'readlink', side_effect=readlink)
        guard.start(); self.addCleanup(guard.stop)

    def test_unrelated_protected_application_does_not_block_desktop_discovery(self):
        root = self.proc_fixture()
        other = self.proc_entry(root, 101, 'keyring-agent', '/fixture/keyring-agent')
        self.deny_exe(other)
        self.proc_entry(root, 102, 'Hyprland', '/fixture/Hyprland', ['Hyprland'])
        self.assertEqual([row['pid'] for row in p.processes()], [102])
        with patch.object(p, 'compositor_locked', return_value=False) as locked:
            d.ensure_unlocked()
        locked.assert_called_once()

    @unittest.skipUnless(sys.platform == 'linux', 'Linux proc permission behavior')
    def test_real_protected_child_without_changing_desktop_permissions(self):
        code = '''import ctypes,sys
libc=ctypes.CDLL(None)
assert libc.prctl(15,sys.argv[1].encode(),0,0,0)==0
assert libc.prctl(4,0,0,0,0)==0
print("READY",flush=True)
sys.stdin.buffer.read(1)
'''
        for name in ('cedar-fixture', 'hyprlock'):
            with self.subTest(name=name):
                child = subprocess.Popen([sys.executable, '-c', code, name], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                try:
                    self.assertTrue(select.select([child.stdout], [], [], 5)[0], 'Controlled child startup timed out')
                    self.assertEqual(child.stdout.readline().strip(), 'READY')
                    path = Path('/proc')/str(child.pid)
                    if path.stat().st_uid != os.getuid(): self.skipTest('Kernel hides protected process ownership')
                    try: os.readlink(path/'exe')
                    except PermissionError: pass
                    else: self.skipTest('Environment permits inspecting protected executables')
                    if name == 'hyprlock':
                        with self.assertRaisesRegex(d.Refused, 'Cannot verify desktop process metadata'):
                            p.read_process(child.pid, p.DESKTOP_PROCESSES)
                    else:
                        self.assertIsNone(p.read_process(child.pid, p.DESKTOP_PROCESSES))
                    self.assertIsNone(child.poll())  # it was neither terminated nor altered
                finally:
                    child.communicate('x', timeout=5)
                self.assertEqual(child.returncode, 0)

    def test_unrelated_unreadable_arguments_are_never_read(self):
        root = self.proc_fixture()
        self.proc_entry(root, 101, 'browser', '/fixture/browser')  # no cmdline file
        self.assertEqual(p.processes(), [])

    def test_unreadable_desktop_provider_still_refuses(self):
        root = self.proc_fixture()
        protected = self.proc_entry(root, 101, 'noctalia', '/fixture/noctalia')
        self.deny_exe(protected)
        with self.assertRaisesRegex(d.Refused, 'Cannot verify desktop process metadata'):
            p.processes()

    def test_install_lock_check_does_not_require_bar_executable_access(self):
        root = self.proc_fixture()
        protected = self.proc_entry(root, 101, 'waybar', '/fixture/waybar')
        self.deny_exe(protected)
        self.proc_entry(root, 102, 'Hyprland', '/fixture/Hyprland', ['Hyprland'])
        with patch.object(p, 'compositor_locked', return_value=False): d.ensure_unlocked()
        with self.assertRaises(d.Refused): p.processes()  # a real handoff still needs its exact identity

    def test_unreadable_compositor_cannot_be_treated_as_offline(self):
        root = self.proc_fixture()
        protected = self.proc_entry(root, 101, 'Hyprland', '/fixture/Hyprland')
        self.deny_exe(protected)
        with self.assertRaises(d.Refused): d.ensure_unlocked()
        with self.assertRaises(d.Refused): s.no_graphical_session()

    def test_unreadable_quickshell_blocks_release_switch(self):
        root = self.proc_fixture()
        protected = self.proc_entry(root, 101, 'qs', '/fixture/qs')
        self.deny_exe(protected)
        with self.assertRaises(d.Refused): d.release_in_use()

    def test_replaced_executable_remains_visible_for_lock_checks(self):
        root = self.proc_fixture()
        self.proc_entry(root, 101, 'Hyprland', '/fixture/Hyprland (deleted)', ['Hyprland'])
        rows = p.processes()
        self.assertEqual(rows[0]['exe'], '/fixture/Hyprland')
        self.assertTrue(rows[0]['deleted'])
        with patch.object(p, 'compositor_locked', return_value=True):
            with self.assertRaisesRegex(d.Refused, 'lock is active'): d.ensure_unlocked()
        with patch.object(p, 'compositor_locked', side_effect=d.Refused('Unknown lock state')):
            with self.assertRaisesRegex(d.Refused, 'Unknown lock state'): d.ensure_unlocked()

    def test_zombie_and_exited_processes_do_not_require_executable_access(self):
        root = self.proc_fixture()
        self.proc_entry(root, 101, 'Hyprland', state='Z')
        self.assertEqual(p.processes(), [])
        self.assertIsNone(p.read_process(102))

    def test_live_missing_executable_fails_closed(self):
        root = self.proc_fixture()
        self.proc_entry(root, 101, 'Hyprland', argv=['Hyprland'])
        with self.assertRaisesRegex(d.Refused, 'Live desktop process metadata'): p.processes()

    def test_executable_identity_wins_over_changed_process_title(self):
        root = self.proc_fixture()
        self.proc_entry(root, 101, 'changed (title)', '/fixture/Hyprland', ['Hyprland'], start='789')
        row = p.processes()[0]
        self.assertEqual(row['start'], '789')
        self.assertEqual(row['exe'], '/fixture/Hyprland')

    def test_non_utf8_arguments_are_preserved_without_hiding_provider(self):
        root = self.proc_fixture()
        self.proc_entry(root, 101, 'waybar', '/fixture/waybar', ['waybar', b'/fixture/\xff.json'])
        self.assertEqual(os.fsencode(p.processes()[0]['argv'][1]), b'/fixture/\xff.json')

    def test_signal_identity_checks_only_recorded_pid_and_detects_reuse(self):
        root = self.proc_fixture()
        self.proc_entry(root, 101, 'waybar', '/fixture/waybar', ['waybar'], start='789')
        row = p.read_process(101)
        with patch.object(p, 'processes', side_effect=AssertionError('Unrelated processes must not be inspected')):
            self.assertTrue(p.same_process(row))
            self.assertFalse(p.same_process({**row, 'start':'old'}))
            self.assertFalse(p.same_process({**row, 'exe':'/fixture/another'}))
        self.deny_exe(root/'101')
        with patch.object(p.signal, 'pidfd_send_signal') as signal:
            with self.assertRaises(d.Refused): p.pause(row)
        signal.assert_not_called()

    def test_current_symlink_launch_is_recognized_as_running_release(self):
        root = self.proc_fixture()
        release = d.paths()['data']/'releases/fixture'; release.mkdir(parents=True)
        current = d.paths()['data']/'current'; current.symlink_to(release)
        self.proc_entry(root, 101, 'qs', '/fixture/qs', ['qs', '-p', str(current/'shell.qml')])
        with patch.object(p, 'qs_instances', return_value=[{'pid':101,'config_path':str(current/'shell.qml')}]):
            self.assertTrue(d.release_in_use())
        with patch.object(p, 'qs_instances', side_effect=d.Refused('Unknown Quickshell state')):
            with self.assertRaises(d.Refused): d.release_in_use()

    def test_pending_cedar_lock_still_blocks_with_unrelated_protected_process(self):
        root = self.proc_fixture()
        other = self.proc_entry(root, 101, 'keyring-agent', '/fixture/keyring-agent')
        self.deny_exe(other)
        self.proc_entry(root, 102, 'Hyprland', '/fixture/Hyprland', ['Hyprland'])
        source = str(d.paths()['data']/'releases/fixture/shell.qml')
        self.proc_entry(root, 103, 'qs', '/fixture/qs', ['qs', '-p', source])
        with patch.object(p, 'compositor_locked', return_value=False), patch.object(p, 'qs_instances', return_value=[{'config_path':source}]), patch.object(p, 'qs_ipc', return_value='true'):
            with self.assertRaisesRegex(d.Refused, 'locking or locked'): d.ensure_unlocked()

    def test_upgrade_and_rollback_with_unrelated_protected_process(self):
        root = self.proc_fixture()
        other = self.proc_entry(root, 101, 'keyring-agent', '/fixture/keyring-agent')
        self.deny_exe(other)
        self.proc_entry(root, 102, 'Hyprland', '/fixture/Hyprland', ['Hyprland'])
        source = self.base/'next release'
        shutil.copytree(d.ROOT, source, ignore=shutil.ignore_patterns('.git', '__pycache__'))
        (source/'VERSION').write_text('0.1.0-dev.fixture\n')
        with patch.object(d, 'validate', return_value='Fixture validation'), patch.object(p, 'compositor_locked', return_value=False):
            d.install(d.ROOT, approved=True)
            before = d.installed()
            d.install(source, approved=True)
            self.assertNotEqual(d.installed(), before)
            self.assertEqual((d.installed()/'VERSION').read_text().strip(), '0.1.0-dev.fixture')
            d.recover_latest('install')
            self.assertEqual(d.installed(), before)

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
        with patch.object(d.os, 'getuid', return_value=1000), patch.object(sys.stdin, 'isatty', return_value=True), patch.object(d.shutil, 'which', return_value='/fixture/hyprctl'), patch.object(d, 'capabilities', return_value=[]), patch.object(d, 'package_plan', return_value={'packages':['quickshell'], 'distribution':'CachyOS'}), patch('builtins.input', return_value='n'), patch.object(d, 'install') as install, patch.object(d, 'install_packages') as packages:
            with self.assertRaisesRegex(d.Refused, 'Canceled'): setup.main([])
        install.assert_not_called(); packages.assert_not_called()

    def missing_font(self):
        return {'id':'JetBrainsMono Nerd Font', 'status':'Needs Setup', 'scope':'font', 'package':'ttf-jetbrains-mono-nerd'}

    def test_recommended_font_is_explicit_opt_in_not_a_dependency_blocker(self):
        with patch.object(d, 'capabilities', return_value=[self.missing_font()]), patch.object(d.shutil, 'which', return_value='/fixture/qs'), patch.object(d, 'validate_imports'):
            self.assertEqual(d.missing_packages(d.ROOT), [])
            self.assertEqual(d.missing_packages(d.ROOT, include_recommended=True), ['ttf-jetbrains-mono-nerd'])

    def test_feature_dependencies_remain_included_with_fonts_omitted(self):
        missing = [self.missing_font(), {'id':'gi.NM', 'status':'Needs Setup', 'package':'libnm'}, {'id':'wl-copy', 'status':'Needs Setup', 'package':'wl-clipboard'}]
        with patch.object(d, 'capabilities', return_value=missing), patch.object(d.shutil, 'which', return_value='/fixture/qs'), patch.object(d, 'validate_imports'):
            self.assertEqual(d.missing_packages(d.ROOT), ['libnm', 'wl-clipboard'])

    def package_fixture(self, packages=None, distro='cachyos', result=0):
        stack = contextlib.ExitStack()
        self.addCleanup(stack.close)
        stack.enter_context(patch.object(platform, 'freedesktop_os_release', return_value={'ID':distro, 'ID_LIKE':'arch'}))
        stack.enter_context(patch.object(platform, 'machine', return_value='x86_64'))
        stack.enter_context(patch.object(d, 'missing_packages', return_value=['quickshell'] if packages is None else packages))
        stack.enter_context(patch.object(d.shutil, 'which', return_value='/fixture/tool'))
        command = stack.enter_context(patch.object(d, 'command', return_value='Package is present in configured repository'))
        spawn = stack.enter_context(patch.object(d.subprocess, 'run', return_value=subprocess.CompletedProcess([], result)))
        return command, spawn

    def test_cachyos_package_install_uses_disclosed_packages_and_full_upgrade(self):
        command, spawn = self.package_fixture()
        plan = d.package_plan(d.ROOT)
        self.assertEqual(plan['distribution'], 'CachyOS')
        command.assert_called_once_with(['pacman', '-Si', 'quickshell'])
        spawn.assert_not_called()
        # Changes to capability detection cannot broaden an approved plan.
        with patch.object(d, 'missing_packages', side_effect=AssertionError('Unexpected second scan')):
            d.install_packages(plan, approve_upgrade=True)
        spawn.assert_called_once_with(['sudo', 'pacman', '-Syu', '--needed', 'quickshell'])
        records = list((d.paths()['state']/'transactions').glob('*/journal.json'))
        self.assertEqual(len(records), 1)
        self.assertEqual(d.read_json(records[0])['packages'][0]['result'], 'succeeded')

    def test_unknown_arch_derivative_is_not_guessed_from_id_like(self):
        command, spawn = self.package_fixture(distro='unreviewed-distro')
        with self.assertRaisesRegex(d.Refused, 'not reviewed'):
            d.package_plan(d.ROOT, True, True)
        command.assert_not_called(); spawn.assert_not_called()

    def test_package_setup_checks_architecture(self):
        command, spawn = self.package_fixture()
        with patch.object(platform, 'machine', return_value='aarch64'):
            with self.assertRaisesRegex(d.Refused, 'not reviewed'): d.package_plan(d.ROOT)
        command.assert_not_called(); spawn.assert_not_called()

    def test_no_missing_packages_needs_no_package_backend_or_approval(self):
        command, spawn = self.package_fixture(packages=[], distro='unreviewed-distro')
        plan = d.package_plan(d.ROOT, True, False)
        self.assertEqual(plan['operation'], 'None needed')
        command.assert_not_called(); spawn.assert_not_called()

    def test_package_install_requires_separate_upgrade_consent(self):
        _, spawn = self.package_fixture()
        with self.assertRaisesRegex(d.Refused, 'separate consent'): d.package_plan(d.ROOT, True, False)
        spawn.assert_not_called()
        self.assertFalse(d.paths()['state'].exists())

    def test_failed_package_operation_records_failure_and_stops(self):
        _, spawn = self.package_fixture(result=1)
        with self.assertRaisesRegex(d.Refused, 'failed/canceled'): d.package_plan(d.ROOT, True, True)
        spawn.assert_called_once()
        records = list((d.paths()['state']/'transactions').glob('*/journal.json'))
        self.assertEqual(len(records), 1)
        record = d.read_json(records[0])
        self.assertEqual(record['packages'][0]['result'], 'failed')
        self.assertNotEqual(record['stage'], 'commit')

    def test_busy_package_manager_is_never_bypassed(self):
        _, spawn = self.package_fixture()
        with patch.object(Path, 'exists', return_value=True), patch.object(d, 'command') as command:
            with self.assertRaisesRegex(d.Refused, 'busy'): d.check_package_plan({'backend':'pacman', 'packages':['quickshell']})
        command.assert_not_called(); spawn.assert_not_called()

    def test_wizard_reports_unavailable_repository_before_requesting_approval(self):
        import setup
        _, spawn = self.package_fixture()
        with patch.object(d.os, 'getuid', return_value=1000), patch.object(sys.stdin, 'isatty', return_value=True), patch.object(d, 'capabilities', return_value=[]), patch.object(d, 'command', side_effect=d.Refused('repository unavailable')), patch('builtins.input') as prompt, patch.object(d, 'install') as install:
            with self.assertRaisesRegex(d.Refused, 'could not be verified'): setup.main([])
        prompt.assert_not_called(); install.assert_not_called(); spawn.assert_not_called()

    def test_wizard_missing_font_continues_without_package_approval(self):
        import setup
        output = io.StringIO()
        with patch.object(d.os, 'getuid', return_value=1000), patch.object(sys.stdin, 'isatty', return_value=True), patch.object(d.shutil, 'which', return_value='/fixture/tool'), patch.object(d, 'capabilities', return_value=[self.missing_font()]), patch.object(d, 'validate_imports'), patch.object(d, 'package_host', side_effect=AssertionError('Unneeded package backend')), patch.object(d, 'plan_install', return_value={}), patch.object(d, 'approve') as approve, patch.object(d, 'install') as install, patch.object(d, 'install_packages') as packages, patch('builtins.input', return_value='1') as prompt, contextlib.redirect_stdout(output):
            setup.main([])
        install.assert_called_once_with(d.ROOT, approved=True)
        approve.assert_called_once_with({})
        packages.assert_not_called()
        prompt.assert_called_once_with('Choice [1]: ')
        self.assertIn('Using its readable fallback', output.getvalue())
        self.assertIn('only after installation succeeds', output.getvalue())

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

    def test_quickshell_empty_registry_text_and_json(self):
        import omarchy_session
        for output in ('No running instances.\n', '[]\n'):
            with self.subTest(output=output), patch.object(d, 'command', return_value=output) as command:
                self.assertEqual(p.qs_instances(), [])
                self.assertEqual(omarchy_session.instances(), [])
                command.assert_called_with(['qs', 'list', '--all', '-j'], timeout=5)

    @unittest.skipUnless(shutil.which('qs'), 'Quickshell unavailable; real empty-registry check not run')
    def test_real_quickshell_empty_registry(self):
        # Actual CLI, separate runtime registry; never reads or stops a host shell.
        runtime_dir = self.base / 'empty runtime'; runtime_dir.mkdir(mode=0o700)
        with patch.dict(os.environ, {'XDG_RUNTIME_DIR': str(runtime_dir)}):
            self.assertEqual(p.qs_instances(), [])

    def test_quickshell_malformed_inventory_never_means_empty(self):
        for output in ('', 'private-fixture-value', 'No running instances.\nerror', '{}', 'null',
                       '[null]', '[{}]', '[{"pid":true,"config_path":"/fixture/shell.qml"}]',
                       '[{"pid":12,"config_path":"relative.qml"}]'):
            with self.subTest(output=output), patch.object(d, 'command', return_value=output):
                with self.assertRaisesRegex(d.Refused, 'Quickshell instance discovery') as error:
                    p.qs_instances()
                self.assertNotIn('private-fixture-value', str(error.exception))
        with patch.object(d, 'command', side_effect=d.Refused('Command failed')):
            with self.assertRaisesRegex(d.Refused, 'Command failed'): p.qs_instances()

    def test_quickshell_valid_inventory_keeps_other_instances(self):
        rows = [{'pid': 432, 'config_path': '/fixture/a profile/shell.qml', 'instance_id': 'example'}]
        with patch.object(d, 'command', return_value=json.dumps(rows)):
            self.assertEqual(p.qs_instances(), rows)

    def test_doctor_distinguishes_empty_registry_from_failure(self):
        for output, expected in [('No running instances.\n', 'Ready'), ('private-fixture-value', 'Failed:')]:
            def command(argv, **kwargs):
                if argv == ['qs', 'list', '--all', '-j']: return output
                raise d.Refused('Fixture service unavailable')
            with patch.object(d.shutil, 'which', side_effect=lambda name: '/fixture/qs' if name == 'qs' else None), patch.object(d, 'command', side_effect=command):
                result = d.session_inventory()
            self.assertEqual(result['quickshell'], [])
            self.assertTrue(result['quickshellDiscovery'].startswith(expected))
            self.assertNotIn('private-fixture-value', json.dumps(result))

    def native_fixture(self):
        # Shapes from reviewed Noctalia 5.2.1 config_export/config_schema sources.
        # IPC is simulated; TOML parsing and on-disk transactions use real code.
        merged = '''# keep my notes
[bar]
order = ["default", "side.bar 雨"]
[bar.default]
enabled = true # main surface
thickness = 32
[bar.default.monitor."desk alias"]
match = "desc:Generic Display"
enabled = true
thickness = 36
[bar.'side.bar 雨']
'enabled' = true
position = "left"
[dock]
enabled = true
[dock.monitor."TEST-1"]
enabled = true
position = "bottom"
[notification]
enable_daemon = true
duration = 4000
[osd]
enabled = true
[lock]
custom = "preserve"
[idle]
lock_timeout = 600
[future]
unknown = "preserve"
'''
        full = merged.replace('monitor."desk alias"', 'monitor."desc:Generic Display"')
        target = self.base / 'state/noctalia/settings.toml'
        target.parent.mkdir(parents=True); target.write_text(merged); target.chmod(0o640)
        process = {'pid': 765, 'start': '123', 'exe': '/fixture/noctalia', 'argv': ['noctalia'], 'deleted': False}
        replies = {'full': full, 'merged': merged, 'version': 'noctalia v5.2.1 (5.2.1-1-dirty)',
                   'status': '{"locked":false,"barVisible":true}', 'qs': 'No running instances.\n'}
        def command(argv, **kwargs):
            if argv == ['qs', 'list', '--all', '-j']: return replies['qs']
            if argv == ['hyprctl', '-j', 'monitors']: return '[{"solitaryBlockedBy":[]}]'
            if argv == ['/fixture/noctalia', '--version']: return replies['version']
            if argv == ['/fixture/noctalia', 'msg', 'status']: return replies['status']
            raise AssertionError(argv)
        def export(argv, **kwargs):
            self.assertEqual(argv[:3], ['/fixture/noctalia', 'config', 'export'])
            self.assertEqual(kwargs['env']['XDG_STATE_HOME'], str(self.base / 'state'))
            return subprocess.CompletedProcess(argv, 0, replies[argv[3]], '')
        patches = [patch.object(p, 'processes', return_value=[process]),
                   patch.object(p, 'process_environment', return_value={'XDG_STATE_HOME': str(self.base / 'state')}),
                   patch.object(p, 'notification_owner', return_value=process['pid']),
                   patch.object(d, 'command', side_effect=command),
                   patch.object(p.subprocess, 'run', side_effect=export)]
        for item in patches:
            item.start(); self.addCleanup(item.stop)
        return target, replies

    def test_native_discovery_with_no_quickshell_preserves_real_export_structure(self):
        target, _ = self.native_fixture(); before = d.info(target)
        row = p.inspect(d.ROOT)
        self.assertEqual(row['adapter'], 'noctalia-v5')
        self.assertEqual(row['locker'], 'noctalia')
        self.assertEqual(row['paused'], [])
        expected = p.tomllib.loads(target.read_text())
        expected['bar']['default']['enabled'] = False
        expected['bar']['default']['monitor']['desk alias']['enabled'] = False
        expected['bar']['side.bar 雨']['enabled'] = False
        expected['dock']['enabled'] = False
        expected['dock']['monitor']['TEST-1']['enabled'] = False
        expected['notification']['enable_daemon'] = False
        expected['osd']['enabled'] = False
        self.assertEqual(p.tomllib.loads(row['settingsAfter']), expected)
        self.assertIn('# keep my notes', row['settingsAfter'])
        self.assertIn('enabled = false # main surface', row['settingsAfter'])
        self.assertNotIn('monitor."desc:Generic Display"', row['settingsAfter'])
        self.assertEqual(d.info(target), before)  # discovery is read-only

    def test_native_trial_declined_before_settings_or_process_changes(self):
        import omarchy_session
        target, _ = self.native_fixture(); before = d.info(target)
        with patch.object(d.shutil, 'which', return_value='/fixture/tool'), patch.object(omarchy_session, 'active', return_value=False), patch.object(s, 'active', return_value=False), patch.object(d, 'approve', side_effect=d.Refused('Canceled')), patch.object(s, 'spawn') as spawn, patch.object(s, 'authenticate') as authenticate:
            with self.assertRaisesRegex(d.Refused, 'Canceled'): s.trial(d.ROOT)
        spawn.assert_not_called(); authenticate.assert_not_called()
        self.assertEqual(d.info(target), before)
        self.assertFalse(s.record_path().exists())

    def test_native_overrides_restore_original_bytes_and_metadata(self):
        target, _ = self.native_fixture(); before = d.info(target)
        row = p.inspect(d.ROOT)
        row.update(self.row('noctalia-v5'))
        tx = self.journal(row, target)
        with patch.object(s, 'unlocked'):
            s.prepare(row)
        self.assertFalse(p.tomllib.loads(target.read_text())['bar']['default']['enabled'])
        d.restore_journal(tx.path)
        self.assertEqual(d.info(target), before)

    def test_native_unknown_responses_fail_before_settings_change(self):
        target, replies = self.native_fixture(); before = d.info(target)
        initial = copy.deepcopy(replies)
        for key, value, message in [('qs', '', 'Quickshell'), ('status', '', 'Noctalia status'),
                ('status', 'private-fixture-value', 'Noctalia status'), ('status', '[]', 'Noctalia status'),
                ('status', '{"locked":"false","barVisible":true}', 'lock and bar state'),
                ('status', '{"locked":true,"barVisible":true}', 'Noctalia is locked'),
                ('version', 'noctalia v5.2.2', 'outside the reviewed version'),
                ('full', 'private-fixture-value', 'configuration export'), ('full', '', 'bar configuration')]:
            with self.subTest(key=key, value=value):
                replies.update(initial); replies[key] = value
                with self.assertRaisesRegex(d.Refused, message) as error: p.inspect(d.ROOT)
                self.assertNotIn('private-fixture-value', str(error.exception))
                self.assertEqual(d.info(target), before)

    def test_native_bar_order_and_monitor_snapshot_must_be_consistent(self):
        target, replies = self.native_fixture(); before = d.info(target)
        full = replies['full']
        for bad in (full.replace('order = ["default", "side.bar 雨"]', 'order = ["missing"]'),
                    full.replace('order = ["default", "side.bar 雨"]', 'order = ["default", "default"]'),
                    full.replace('monitor."desc:Generic Display"', 'monitor."new display"').replace('match = "desc:Generic Display"', 'match = "new display"')):
            replies['full'] = bad
            with self.assertRaises(d.Refused): p.inspect(d.ROOT)
            self.assertEqual(d.info(target), before)

    def test_native_version_parser_checks_release_not_build_metadata(self):
        row = {'adapter': 'noctalia-v5', 'providerExe': '/fixture/noctalia'}
        for version in ('noctalia v5.2.1', 'noctalia 5.2.1', 'noctalia v5.2.1 (5.2.1-1-dirty)'):
            with patch.object(d, 'command', return_value=version): p.verify_noctalia(d.ROOT, row)
        for version in ('noctalia v5.2.10', 'noctalia v5.2.1-dev', 'noctalia v5.3.0 (5.2.1)',
                        'unrelated 5.2.1', 'noctalia v5.2.1\nerror'):
            with patch.object(d, 'command', return_value=version):
                with self.assertRaises(d.Refused): p.verify_noctalia(d.ROOT, row)

    def test_native_defaults_missing_state_and_quoted_monitor_keys(self):
        target, replies = self.native_fixture()
        target.unlink(); replies['merged'] = ''
        replies['full'] = '[bar]\norder = ["default"]\n[bar.default]\nenabled = true\n'
        row = p.inspect(d.ROOT)
        self.assertFalse(target.exists())
        self.assertFalse(p.tomllib.loads(row['settingsAfter'])['bar']['default']['enabled'])
        values = [(('bar', 'side.bar 雨', 'monitor', 'desc:Generic "Display"'), 'enabled', False)]
        text = p.toml_overrides('', values)
        self.assertFalse(p.tomllib.loads(text)['bar']['side.bar 雨']['monitor']['desc:Generic "Display"']['enabled'])
        self.assertEqual(p.toml_overrides(text, values), text)

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

    def test_native_state_without_final_newline_preserved(self):
        text = p.toml_overrides('[osd]\n# keep note', [('osd', 'enabled', False)])
        self.assertFalse(p.tomllib.loads(text)['osd']['enabled'])
        self.assertIn('# keep note', text)

    def test_invalid_compositor_response_never_means_unlocked_or_covered(self):
        for output in ('', '{}', '[null]', '[{"solitaryBlockedBy":"LOCK"}]', '[{"solitaryBlockedBy":[true]}]'):
            with self.subTest(output=output), patch.object(d, 'command', return_value=output):
                with self.assertRaises(d.Refused): p.compositor_locked()
                with self.assertRaises(d.Refused): p.compositor_covered()
        with patch.object(d, 'command', return_value='[]'):
            with self.assertRaises(d.Refused): p.compositor_locked()
            self.assertFalse(p.compositor_covered())

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

    def test_installed_cli_selects_portable_backend_without_running_omarchy(self):
        import omarchy_session
        with patch.object(s, 'active', return_value=False), patch.object(omarchy_session, 'active', return_value=False), patch.object(d.shutil, 'which', return_value='/fixture/qs'), patch.object(p, 'qs_instances', return_value=[]):
            self.assertIs(d.session_backend(), s)

    def test_wizard_unsupported_distro_stops_before_package_approval(self):
        import setup
        _, spawn = self.package_fixture(distro='unreviewed-distro')
        with patch.object(d.os, 'getuid', return_value=1000), patch.object(sys.stdin, 'isatty', return_value=True), patch.object(d, 'capabilities', return_value=[]), patch('builtins.input') as prompt, patch.object(d, 'install') as install:
            with self.assertRaisesRegex(d.Refused, 'not reviewed'): setup.main([])
        prompt.assert_not_called(); install.assert_not_called(); spawn.assert_not_called()

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
