"""The CEDAR installer engine against scripted machines.

A FakeHost stands in for the computer: files, commands, processes, units
and packages are dictionaries, so detection, plan generation, dry runs,
backup manifests, resume and restore are tested without touching the
developer's home. The real distribution engine is not run here; the steps
that call it are covered by the lifecycle fixtures and offscreen checks.
"""
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from installer.engine import backup as backup_module  # noqa: E402
from installer.engine import facts as facts_module  # noqa: E402
from installer.engine import operations as ops  # noqa: E402
from installer.engine import plan as plan_module  # noqa: E402
from installer.engine.host import FakeHost  # noqa: E402
from installer.migration import intent, providers  # noqa: E402

HOME = '/users/station'
HYPR_LUA = '''
hl.monitor({ output = "DP-1", mode = "3440x1440@144", position = "0x0", scale = 1 })
hl.monitor({ output = "DP-2", mode = "2560x1440@144", position = "3440x0", scale = 1, transform = 1, vrr = 1 })
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })
hl.config({ input = { kb_layout = "us", kb_variant = "colemak", kb_options = "caps:escape" } })
'''
HYPR_CONF = '''
source = ~/.config/hypr/monitors.conf
input {
    kb_layout = de
    kb_options = grp:alt_shift_toggle
}
monitorv2 {
    output = HDMI-A-1
    mode = 1920x1080@60
    position = 0x0
    scale = 1
}
'''
MONITORS_CONF = 'monitor = eDP-1, 2560x1600@165, 1920x0, 1.6, transform, 0\nmonitor = , preferred, auto, 1\n'
LIVE = [{'name': 'DP-1', 'width': 3440, 'height': 1440, 'refreshRate': 143.97, 'x': 0, 'y': 0, 'scale': 1.0, 'transform': 0, 'availableModes': ['3440x1440@144.00Hz'], 'solitaryBlockedBy': [], 'vrr': False},
        {'name': 'DP-2', 'width': 2560, 'height': 1440, 'refreshRate': 143.97, 'x': 3440, 'y': 0, 'scale': 1.0, 'transform': 1, 'availableModes': ['2560x1440@144.00Hz'], 'solitaryBlockedBy': [], 'vrr': True}]


def arch_host(**overrides):
    files = {HOME + '/.config/hypr/hyprland.lua': HYPR_LUA, '/sys/class/drm/card0/device/vendor': '0x10de\n',
             '/usr/share/omarchy/shell/shell.qml': 'ShellRoot {}', ROOT / 'VERSION': (ROOT / 'VERSION').read_text(),
             ROOT / 'data/dependencies.json': (ROOT / 'data/dependencies.json').read_text()}
    dirs = ['/sys/module/nvidia', '/sys/module/snd', HOME + '/.config/omarchy', HOME + '/Pictures/Wallpapers', '/usr/share/omarchy']
    files[HOME + '/Pictures/Wallpapers/a.png'] = ''
    files[HOME + '/Pictures/Wallpapers/b.jpg'] = ''
    commands = {'hyprctl -j monitors': json.dumps(LIVE), 'hyprctl version': 'Hyprland 0.56.2 built from branch v0.56.2',
                'qs --version': 'quickshell 0.3.1', 'qs list --all -j': json.dumps([{'pid': 500, 'config_path': '/usr/share/omarchy/shell/shell.qml'}]),
                'systemctl show display-manager.service -p Id --value': 'sddm.service\n', 'systemctl is-active NetworkManager': 'active\n',
                'nmcli -t -f CONNECTIVITY general': 'full\n', 'python3': (0, '', ''), 'fc-match': 'Rajdhani', 'xdg-mime query default x-scheme-handler/http': 'zen.desktop\n',
                'pacman -Si': (0, 'Name: ok', '')}
    processes = [{'pid': 1, 'exe': '/usr/bin/Hyprland', 'argv': ['Hyprland']}, {'pid': 500, 'exe': '/usr/bin/qs', 'argv': ['qs', '-c', 'omarchy']},
                 {'pid': 600, 'exe': '/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1', 'argv': ['polkit-gnome-authentication-agent-1']}]
    which = ['hyprctl', 'qs', 'python3', 'systemctl', 'systemd-run', 'nmcli', 'pactl', 'wl-copy', 'wl-paste', 'powerprofilesctl', 'brightnessctl', 'xdg-open', 'gtk-launch', 'jq', 'gio',
             'journalctl', 'pkexec', 'cava', 'checkupdates', 'sensors', 'nvidia-smi', 'xrandr', 'mmcli', 'bash', 'openssl', 'nmtui', 'pgrep', 'ps', 'busctl', 'xdg-mime', 'hyprsunset', 'hypridle',
             'pacman', 'sudo', 'omarchy', 'fc-match']
    base = dict(home=HOME, environ={'TERMINAL': 'kitty', 'WAYLAND_DISPLAY': 'wayland-1', 'XDG_SESSION_TYPE': 'wayland'}, files=files, dirs=dirs, commands=commands,
                processes=processes, which=which, packages={'hyprland': '0.56.2', 'quickshell': '0.3.1', 'omarchy': '4.0.4'},
                release={'ID': 'omarchy', 'ID_LIKE': 'arch', 'PRETTY_NAME': 'Omarchy'})
    base.update(overrides)
    return FakeHost(**base)


class Intent(unittest.TestCase):
    def test_lua_monitors_and_keyboard(self):
        rows = intent.parse_monitors(HYPR_LUA, 'lua')
        self.assertEqual([r['output'] for r in rows], ['DP-1', 'DP-2', ''])
        self.assertEqual(rows[1]['transform'], '1'); self.assertEqual(rows[1]['vrr'], '1')
        monitors, notes = intent.to_cedar_monitors(rows, LIVE)
        self.assertEqual([m['name'] for m in monitors], ['DP-1', 'DP-2'])
        self.assertEqual(monitors[1], {'name': 'DP-2', 'mode': '2560x1440@144.00', 'x': 3440, 'y': 0, 'scale': 1.0, 'transform': 1, 'vrrPolicy': 1})
        self.assertTrue(any('wildcard' in n for n in notes))
        self.assertEqual(intent.parse_keyboard(HYPR_LUA, 'lua'), {'kb_layout': 'us', 'kb_variant': 'colemak', 'kb_options': 'caps:escape'})

    def test_modes_are_spelled_like_the_compositor_lists_them(self):
        live = {'width': 3440, 'height': 1440, 'refreshRate': 143.97, 'availableModes': ['3440x1440@143.97Hz', '3440x1440@60.00Hz', '2560x1440@60.00Hz']}
        self.assertEqual(intent.normalize_mode('3440x1440@144', live), '3440x1440@143.97')
        self.assertEqual(intent.normalize_mode('3440x1440@60', live), '3440x1440@60.00')
        self.assertEqual(intent.normalize_mode('3440x1440', live), '3440x1440@143.97')
        self.assertEqual(intent.normalize_mode('preferred', live), '3440x1440@143.97')
        self.assertEqual(intent.normalize_mode('1920x1080@60', live), '1920x1080@60.00')
        self.assertEqual(intent.normalize_mode('2560x1440@144', {}), '2560x1440@144.00')

    def test_conf_monitors_follow_includes_without_executing(self):
        host = FakeHost(home=HOME, files={HOME + '/.config/hypr/hyprland.conf': HYPR_CONF, HOME + '/.config/hypr/monitors.conf': MONITORS_CONF})
        result = intent.inspect_hyprland(host, Path(HOME + '/.config/hypr/hyprland.conf'))
        self.assertEqual(result['syntax'], 'conf')
        self.assertEqual(len(result['files']), 2)
        names = [r['output'] for r in result['monitorRules']]
        self.assertEqual(sorted(names), ['', 'HDMI-A-1', 'eDP-1'])
        self.assertEqual(result['keyboard'], {'kb_layout': 'de', 'kb_options': 'grp:alt_shift_toggle'})
        edp = next(m for m in result['monitors'] if m['name'] == 'eDP-1')
        self.assertEqual((edp['x'], edp['y'], edp['scale'], edp['transform']), (1920, 0, 1.6, 0))

    def test_dynamic_include_is_not_followed(self):
        host = FakeHost(home=HOME, files={HOME + '/.config/hypr/hyprland.conf': 'source = $(echo evil)\nsource = ~/.config/hypr/$UNKNOWN/x.conf\n'})
        files, unresolved = intent.walk(host, Path(HOME + '/.config/hypr/hyprland.conf'))
        self.assertEqual(len(files), 1); self.assertEqual(len(unresolved), 2)


class Detection(unittest.TestCase):
    def test_omarchy_is_recognized_from_several_markers(self):
        host = arch_host()
        facts = facts_module.scan(host, ROOT)
        self.assertEqual(facts['environment']['id'], 'omarchy')
        self.assertGreaterEqual(len(facts['environment']['evidence']), 3)
        self.assertEqual(facts['environment']['adapter'], 'omarchy')
        self.assertEqual(facts['gpu'], {'vendor': 'NVIDIA', 'driver': 'nvidia'})
        self.assertEqual(facts['displayManager'], 'sddm'); self.assertEqual(facts['networkManager'], 'NetworkManager')
        self.assertEqual(facts['hyprlandVersion'], '0.56.2'); self.assertEqual(facts['quickshellVersion'], '0.3.1')
        self.assertEqual(facts['support']['status'], 'supported')
        self.assertEqual([m['name'] for m in facts['hyprland']['monitors']], ['DP-1', 'DP-2'])
        self.assertEqual(facts['apps']['terminal'], 'kitty'); self.assertEqual(facts['apps']['browser'], 'zen.desktop')
        self.assertEqual(facts['wallpapers'][0]['images'], 2)
        self.assertTrue(facts['polkitAgent'])

    def test_a_folder_name_alone_does_not_prove_an_environment(self):
        host = arch_host(dirs=['/sys/module/nvidia', HOME + '/.config/hyde'], files={HOME + '/.config/hypr/hyprland.conf': HYPR_CONF, ROOT / 'VERSION': '1', ROOT / 'data/dependencies.json': (ROOT / 'data/dependencies.json').read_text()},
                         processes=[{'pid': 1, 'exe': '/usr/bin/Hyprland', 'argv': ['Hyprland']}], commands={'hyprctl -j monitors': '[]'}, packages={}, release={'ID': 'arch', 'PRETTY_NAME': 'Arch Linux'})
        facts = facts_module.scan(host, ROOT)
        self.assertEqual(facts['environment']['id'], 'plain-hyprland')
        result = next(r for r in facts['environment']['results'] if r['id'] == 'hyde')
        self.assertFalse(result['detected']); self.assertEqual(result['score'], 1)

    def test_known_environments_by_markers(self):
        cases = {
            'hyde': dict(dirs=[HOME + '/.config/hyde'], files={HOME + '/.config/hypr/hyde.conf': ''}),
            'caelestia': dict(dirs=[HOME + '/.config/caelestia'], files={HOME + '/.local/state/caelestia/dots-state.json': '{}'}),
            'ryoku': dict(files={HOME + '/.local/state/ryoku/shell-install-state.json': '{}'}),
            'end4': dict(dirs=[HOME + '/.config/illogical-impulse'], files={HOME + '/.config/quickshell/ii/shell.qml': ''}),
            'ml4w': dict(dirs=[HOME + '/.config/ml4w', HOME + '/.config/hypr/conf'], files={HOME + '/.config/hypr/conf/ml4w.conf': ''}),
            'jakoolit': dict(dirs=[HOME + '/.config/hypr/UserConfigs', HOME + '/.config/hypr/UserScripts']),
            'noctalia': dict(processes=[{'pid': 1, 'exe': '/usr/bin/Hyprland', 'argv': ['Hyprland']}, {'pid': 2, 'exe': '/usr/bin/noctalia', 'argv': ['noctalia']}]),
            'waybar': dict(processes=[{'pid': 1, 'exe': '/usr/bin/Hyprland', 'argv': ['Hyprland']}, {'pid': 2, 'exe': '/usr/bin/waybar', 'argv': ['waybar']}], dirs=[HOME + '/.config/waybar']),
        }
        for expected, extra in cases.items():
            files = {HOME + '/.config/hypr/hyprland.conf': HYPR_CONF, ROOT / 'VERSION': '1', ROOT / 'data/dependencies.json': (ROOT / 'data/dependencies.json').read_text(), **extra.get('files', {})}
            host = arch_host(files=files, dirs=extra.get('dirs', []), processes=extra.get('processes', [{'pid': 1, 'exe': '/usr/bin/Hyprland', 'argv': ['Hyprland']}]),
                             commands={'hyprctl -j monitors': '[]'}, packages={}, release={'ID': 'arch', 'PRETTY_NAME': 'Arch Linux'})
            facts = facts_module.scan(host, ROOT)
            self.assertEqual(facts['environment']['id'], expected, expected)
            self.assertEqual(facts['environment']['handoff'] in ('validated', 'experimental'), expected in ('noctalia', 'waybar'), expected)

    def test_the_installer_window_is_not_an_existing_quickshell_desktop(self):
        from unittest.mock import patch
        sys.path.insert(0, str(ROOT / 'scripts'))
        import portable_providers as pp
        host = arch_host(processes=[{'pid': 1, 'exe': '/usr/bin/Hyprland', 'argv': ['Hyprland']}, {'pid': 9, 'exe': '/usr/bin/qs', 'argv': ['qs', '-p', '/users/station/.cache/cedar/installer/0.1.0/cedar-shell/installer.qml']}],
                         commands={**arch_host().commands, 'qs list --all -j': json.dumps([{'pid': 9, 'config_path': '/users/station/.cache/cedar/installer/0.1.0/cedar-shell/installer.qml'}])},
                         dirs=['/sys/module/nvidia', HOME + '/.config/quickshell'], packages={}, release={'ID': 'arch', 'PRETTY_NAME': 'Arch Linux'},
                         which=[w for w in arch_host().available if w != 'omarchy'],
                         files={k: v for k, v in arch_host().files.items() if 'omarchy' not in k})
        facts = facts_module.scan(host, ROOT)
        self.assertEqual(facts['quickshellInstances'], []); self.assertEqual(facts['environment']['id'], 'plain-hyprland')
        with patch.object(pp, 'compositor_locked', return_value=False), patch.object(pp, 'qs_instances', return_value=[{'pid': 9, 'config_path': '/users/station/.cache/cedar/installer/0.1.0/cedar-shell/installer.qml'}]), \
             patch.object(pp, 'processes', return_value=[]), patch.object(pp, 'notification_owner', return_value=None):
            self.assertEqual(pp.inspect(ROOT)['adapter'], 'hyprland')

    def test_soft_conflicts_are_paused_not_removed(self):
        host = arch_host(processes=[{'pid': 1, 'exe': '/usr/bin/Hyprland', 'argv': ['Hyprland']}, {'pid': 2, 'exe': '/usr/bin/waybar', 'argv': ['waybar']},
                                    {'pid': 3, 'exe': '/usr/bin/hypridle', 'argv': ['hypridle']}, {'pid': 4, 'exe': '/usr/bin/swww-daemon', 'argv': ['swww-daemon']}],
                         commands={'hyprctl -j monitors': '[]', 'qs list --all -j': 'No running instances.'})
        facts = facts_module.scan(host, ROOT)
        kinds = {row['component']: row['kind'] for row in facts['conflicts']}
        self.assertEqual(kinds['Waybar'], 'soft'); self.assertEqual(kinds['swww'], 'soft'); self.assertEqual(kinds['hypridle'], 'compatible')
        self.assertTrue(all('paused' in r['reason'] for r in facts['conflicts'] if r['kind'] == 'soft'))


class Planning(unittest.TestCase):
    def setUp(self):
        self.host = arch_host()
        plan_module.set_check_host(self.host)
        self.facts = facts_module.scan(self.host, ROOT)

    def test_plan_lists_system_migration_and_cedar_and_is_deterministic(self):
        plan = plan_module.build(self.facts)
        self.assertEqual([op['id'] for op in plan['operations']], list(plan_module.OPERATIONS))
        self.assertTrue(any('2 monitors' in r for r in plan['migration']))
        self.assertTrue(any('keyboard' in r for r in plan['migration']))
        self.assertTrue(any('versioned copy' in r for r in plan['cedar']))
        self.assertTrue(plan['options']['session'])
        self.assertEqual(plan['digest'], plan_module.build(self.facts)['digest'])
        self.assertNotEqual(plan['digest'], plan_module.build(self.facts, {'session': False})['digest'])
        self.assertFalse(plan['blocked'])
        text = plan_module.render(plan)
        self.assertIn('MIGRATION', text); self.assertIn('Plan digest', text)

    def test_missing_dependencies_use_pacman_with_notes(self):
        host = arch_host(which=[w for w in arch_host().available if w != 'qs'])
        plan_module.set_check_host(host)
        facts = facts_module.scan(host, ROOT)
        plan = plan_module.build(facts)
        self.assertIn('quickshell', plan['packages']); self.assertEqual(plan['packageProvider'], 'pacman')
        self.assertEqual(plan['privilege'], 'pkexec')
        self.assertTrue(any('pacman -Syu' in n for n in plan['packageNotes']))
        self.assertTrue(any('Install dependencies' in r for r in plan['cedar']))

    def test_unsupported_distribution_with_missing_dependencies_needs_attention(self):
        host = arch_host(which=[w for w in arch_host().available if w not in ('qs', 'pacman')], release={'ID': 'fedora', 'PRETTY_NAME': 'Fedora 42'}, packages={})
        plan_module.set_check_host(host)
        facts = facts_module.scan(host, ROOT)
        self.assertEqual(facts['support']['status'], 'unsupported')
        plan = plan_module.build(facts)
        self.assertTrue(plan['blocked'])
        self.assertIn('unsupported', [a['id'] for a in plan['attention']])

    def test_safety_states_stop_the_plan(self):
        host = arch_host(free=100 * 1024 * 1024, commands={**arch_host().commands, 'hyprctl -j monitors': json.dumps([{**LIVE[0], 'solitaryBlockedBy': ['LOCK']}])})
        plan_module.set_check_host(host)
        facts = facts_module.scan(host, ROOT)
        plan = plan_module.build(facts)
        ids = {a['id'] for a in plan['attention']}
        self.assertIn('disk', ids); self.assertIn('locked', ids); self.assertTrue(plan['blocked'])

    def test_nvidia_secure_boot_without_driver_warns_but_does_not_block(self):
        host = arch_host(dirs=['/sys/module/snd', HOME + '/.config/omarchy', '/usr/share/omarchy'])
        host.files['/sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c'] = b'\x06\x00\x00\x00\x01'
        plan_module.set_check_host(host)
        facts = facts_module.scan(host, ROOT)
        self.assertEqual(facts['secureBoot'], 'enabled'); self.assertEqual(facts['gpu']['driver'], 'unknown')
        plan = plan_module.build(facts)
        row = next(a for a in plan['attention'] if a['id'] == 'nvidia')
        self.assertEqual(row['severity'], 'warn'); self.assertFalse(plan['blocked'])

    def test_existing_cedar_session_is_handed_back_then_re_entered(self):
        host = arch_host(files={**arch_host().files, HOME + '/.local/state/cedar/portable-session.json': json.dumps({'stage': 'kept'})})
        plan_module.set_check_host(host)
        facts = facts_module.scan(host, ROOT)
        self.assertEqual(facts['existingCedar']['session'], 'kept')
        plan = plan_module.build(facts)
        self.assertNotIn('session', [a['id'] for a in plan['attention']]); self.assertFalse(plan['blocked'])
        leave = next(op for op in plan['operations'] if op['id'] == 'leave')
        self.assertTrue(leave['enabled']); self.assertTrue(plan['options']['session'])
        self.assertTrue(any('Hand the desktop back' in r for r in plan['cedar']))
        quiet = plan_module.build(facts_module.scan(arch_host(), ROOT))
        self.assertFalse(next(op for op in quiet['operations'] if op['id'] == 'leave')['enabled'])

    def test_update_prefers_a_checkout_and_falls_back_to_the_bootstrap(self):
        sys.path.insert(0, str(ROOT / 'installer'))
        import cedar_install
        with tempfile.TemporaryDirectory(prefix='cedar update 雨 ') as temp:
            home = Path(temp)
            kind, target = cedar_install.update_plan(ROOT / 'installer' / '..', {'HOME': str(home)})
            self.assertEqual(kind, 'checkout'); self.assertEqual(target, ROOT)             # this source is a checkout
            release_copy = home / 'release'; (release_copy / 'installer/bootstrap').mkdir(parents=True)
            (release_copy / 'installer/bootstrap/install.sh').write_text('#!/bin/sh\n')
            kind, target = cedar_install.update_plan(release_copy, {'HOME': str(home)})
            self.assertEqual(kind, 'bootstrap'); self.assertEqual(target.name, 'install.sh')
            checkout = home / 'cedar-shell'; (checkout / '.git').mkdir(parents=True); (checkout / 'installer').mkdir()
            (checkout / 'installer/cedar_install.py').write_text('')
            kind, target = cedar_install.update_plan(release_copy, {'HOME': str(home)})
            self.assertEqual((kind, target), ('checkout', checkout.resolve()))

    def test_preview_only_environment_skips_session_honestly(self):
        host = arch_host(dirs=[HOME + '/.config/caelestia', '/sys/module/nvidia'], files={HOME + '/.local/state/caelestia/dots-state.json': '{}', HOME + '/.config/hypr/hyprland.conf': HYPR_CONF, ROOT / 'VERSION': '1', ROOT / 'data/dependencies.json': (ROOT / 'data/dependencies.json').read_text()},
                         processes=[{'pid': 1, 'exe': '/usr/bin/Hyprland', 'argv': ['Hyprland']}], commands={'hyprctl -j monitors': '[]', 'qs list --all -j': 'No running instances.'}, packages={}, release={'ID': 'cachyos', 'PRETTY_NAME': 'CachyOS'})
        plan_module.set_check_host(host)
        facts = facts_module.scan(host, ROOT)
        plan = plan_module.build(facts)
        self.assertEqual(facts['environment']['id'], 'caelestia'); self.assertFalse(plan['options']['session'])
        self.assertTrue(any('not validated yet' in r for r in plan['cedar']))
        self.assertFalse(next(op for op in plan['operations'] if op['id'] == 'session')['enabled'])


class Keybinds(unittest.TestCase):
    def test_default_follows_the_environment(self):
        host = arch_host()
        plan_module.set_check_host(host)
        self.assertFalse(plan_module.build(facts_module.scan(host, ROOT))['options']['keybinds'])   # Omarchy ships its own
        plain = arch_host(files={HOME + '/.config/hypr/hyprland.conf': HYPR_CONF, ROOT / 'VERSION': '1', ROOT / 'data/dependencies.json': (ROOT / 'data/dependencies.json').read_text()},
                          dirs=['/sys/module/nvidia'], processes=[{'pid': 1, 'exe': '/usr/bin/Hyprland', 'argv': ['Hyprland']}],
                          commands={'hyprctl -j monitors': '[]', 'qs list --all -j': 'No running instances.'}, packages={}, release={'ID': 'arch', 'PRETTY_NAME': 'Arch Linux'},
                          which=[w for w in arch_host().available if w != 'omarchy'])
        plan_module.set_check_host(plain)
        plan = plan_module.build(facts_module.scan(plain, ROOT))
        self.assertTrue(plan['options']['keybinds'])
        self.assertTrue(any('keybinds' in r for r in plan['cedar']))
        self.assertNotEqual(plan['digest'], plan_module.build(facts_module.scan(plain, ROOT), {'keybinds': False})['digest'])

    def test_both_syntaxes_bind_the_same_keys(self):
        import re
        lua = (ROOT / 'themes/keybinds.lua').read_text()
        conf = (ROOT / 'themes/keybinds.conf').read_text()
        def norm(mods, key):
            mods = sorted(m.upper() for m in mods if m)
            key = key.strip()
            aliases = {'backslash': 'BACKSLASH', 'comma': 'COMMA', 'minus': 'MINUS', 'equal': 'EQUAL', 'backspace': 'BACKSPACE', 'space': 'SPACE', 'tab': 'TAB', 'left': 'LEFT', 'right': 'RIGHT', 'up': 'UP', 'down': 'DOWN'}
            key = aliases.get(key.lower(), key)
            return ' '.join(mods + [key.upper() if len(key) == 1 else key])
        conf_keys = set()
        for m in re.finditer(r'^bind[a-z]*\s*=\s*([^,]*),\s*([^,]+),', conf, re.M):
            conf_keys.add(norm(m.group(1).split(), m.group(2)))
        lua_keys = set()
        for m in re.finditer(r'"((?:[A-Z_]+ \+ )+[A-Za-z0-9_:]+|XF86[A-Za-z]+|Print)"', lua):
            parts = [p.strip() for p in m.group(1).split('+')]
            lua_keys.add(norm(parts[:-1], parts[-1]))
        for i in range(1, 11):
            key = str(i % 10)
            lua_keys.update({norm(['SUPER'], key), norm(['SUPER', 'ALT'], key), norm(['CTRL', 'SUPER'], key), norm(['CTRL', 'SUPER', 'ALT'], key)})
        for d in ('left', 'right', 'up', 'down'):
            lua_keys.update({norm(['SUPER'], d), norm(['SUPER', 'SHIFT'], d)})
        missing_in_conf = sorted(k for k in lua_keys if k not in conf_keys)
        missing_in_lua = sorted(k for k in conf_keys if k not in lua_keys)
        self.assertEqual(missing_in_conf, [], 'in lua only'); self.assertEqual(missing_in_lua, [], 'in conf only')

    def test_desktop_loader_includes_the_copy_when_asked(self):
        sys.path.insert(0, str(ROOT / 'scripts'))
        import desktop
        self.assertIn('keybinds.lua', desktop.render_lua({'input': {}, 'monitors': [], 'bindings': [], 'keybinds': True}))
        self.assertNotIn('keybinds.lua', desktop.render_lua({'input': {}, 'monitors': [], 'bindings': []}))
        self.assertIn('source = ', desktop.render_conf({'input': {}, 'monitors': [], 'bindings': [], 'keybinds': True}))


class CedarCommand(unittest.TestCase):
    def test_installer_subcommand_passes_options_through_untouched(self):
        from unittest.mock import patch
        sys.path.insert(0, str(ROOT / 'scripts'))
        import distribution as d
        calls = []
        def fake_exec(exe, argv):
            calls.append(argv); raise SystemExit(0)   # a real exec never returns
        with patch.object(d, 'installed', return_value=Path('/installed/release')), patch.object(d.os, 'execv', side_effect=fake_exec), patch.object(d.os, 'getuid', return_value=1000):
            with self.assertRaises(SystemExit): d.main(['installer', '--update', '--no-gui', '--yes'])
        self.assertEqual(calls[0][1:], ['/installed/release/installer/cedar_install.py', '--update', '--no-gui', '--yes'])


class LauncherShortcut(unittest.TestCase):
    def test_cedar_own_shortcuts_satisfy_the_launcher_request(self):
        from unittest.mock import patch
        sys.path.insert(0, str(ROOT / 'scripts'))
        import distribution as d
        import portable_controls as c
        self.assertEqual(c.destination({'dispatcher': 'exec', 'arg': 'qs ipc -p /users/station/.local/share/cedar/current/shell.qml call menu toggle apps'}), 'cedar-launcher')
        self.assertEqual(c.destination({'dispatcher': 'exec', 'arg': '/users/station/.local/bin/cedar launcher'}), 'cedar-launcher')
        self.assertEqual(c.destination({'dispatcher': 'exec', 'arg': 'qs ipc -p /x/shell.qml call lock lock'}), 'cedar-lock')
        self.assertIsNone(c.destination({'dispatcher': 'exec', 'arg': 'kitty'}))
        live = [{'dispatcher': 'exec', 'arg': 'qs ipc -p /x/shell.qml call menu toggle apps', 'modmask': 64, 'key': 'space'},
                {'dispatcher': 'togglespecialworkspace', 'arg': 'communication', 'modmask': 64, 'key': 'D'}]
        with patch.object(d, 'command', return_value=json.dumps(live)):
            self.assertEqual(c.shortcut_plan(True, False), [])          # already CEDAR's: nothing to redirect, no refusal
        occupied = [{'dispatcher': 'exec', 'arg': 'kitty', 'modmask': 64, 'key': 'space'}, {'dispatcher': 'exec', 'arg': 'firefox', 'modmask': 64, 'key': 'D'}]
        with patch.object(d, 'command', return_value=json.dumps(occupied)), self.assertRaises(d.Refused):
            c.shortcut_plan(True, False)                                   # somebody else's keys stay theirs


class LoginBlock(unittest.TestCase):
    def test_a_stale_block_is_replaced_not_refused(self):
        sys.path.insert(0, str(ROOT / 'scripts'))
        import distribution as d
        import portable_session as ps
        stale = 'monitor = , preferred, auto, 1\n\n# CEDAR LOGIN START\nexec-once = /old/portable_session.py login\n# CEDAR LOGIN END\nbind = SUPER, Q, exec, kitty\n'
        cleaned = ps.without_login_block(stale)
        self.assertNotIn('CEDAR LOGIN', cleaned); self.assertIn('bind = SUPER, Q, exec, kitty', cleaned); self.assertTrue(cleaned.startswith('monitor'))
        lua = 'hl.monitor({})\n-- CEDAR LOGIN START\nhl.on("hyprland.start", function() end)\n-- CEDAR LOGIN END\n'
        self.assertEqual(ps.without_login_block(lua), 'hl.monitor({})\n')
        self.assertEqual(ps.without_login_block('plain\n'), 'plain\n')
        with self.assertRaises(d.Refused): ps.without_login_block('# CEDAR LOGIN START\nexec-once = x\n')
        self.assertNotIn('CEDAR LOGIN', ps.without_login_block(stale + stale))   # two stale blocks: both go


class BackupAndRestore(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='cedar installer 雨 ')
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name) / 'home'; (self.home / '.config/hypr').mkdir(parents=True)
        self.config = self.home / '.config/hypr/hyprland.conf'; self.config.write_text('monitor = , preferred, auto, 1\n')

    def test_manifest_records_what_changed_and_restores_only_untouched_files(self):
        backup = backup_module.Backup(self.home / '.local/state/cedar/installations', self.home, '1.0', '1.0', stamp='2026-10-07T000000')
        backup.create({'id': 'omarchy'}, {'session': True}, services={'waybar.service': {'state': 'enabled'}}, packages={'hyprland': '1'})
        backup.add(self.config, 'startup entry')
        created = self.home / '.config/cedar/installation.json'
        backup.add(created, 'marker')
        self.config.write_text('monitor = , preferred, auto, 1\n# CEDAR LOGIN START\n'); backup.changed(self.config)
        created.parent.mkdir(parents=True); created.write_text('{}'); backup.changed(created)
        backup.record('packagesInstalled', 'quickshell'); backup.record('servicesDisabled', 'waybar.service'); backup.stage('runtime')
        manifest = json.loads((backup.root / 'manifest.json').read_text())
        for key in ('installerVersion', 'cedarVersion', 'timestamp', 'environment', 'files', 'filesChanged', 'filesCreated', 'servicesDisabled', 'servicesEnabled', 'packagesInstalled', 'packagesRemoved', 'options', 'stagesCompleted'):
            self.assertIn(key, manifest)
        self.assertEqual(manifest['filesChanged'], [str(self.config)]); self.assertEqual(manifest['filesCreated'], [str(created)])
        self.assertTrue((backup.root / 'restore.sh').stat().st_mode & 0o100)
        self.assertEqual(json.loads((backup.root / 'services.json').read_text())['waybar.service']['state'], 'enabled')
        # A later user edit is preserved and reported; the untouched file goes back.
        self.config.write_text('user edited after install\n')
        reloaded = backup_module.Backup.load(backup.root)
        report = reloaded.restore()
        self.assertEqual(report['conflicts'], [str(self.config)]); self.assertEqual(report['restored'], [str(created)])
        self.assertFalse(created.exists()); self.assertEqual(self.config.read_text(), 'user edited after install\n')
        self.config.write_text('monitor = , preferred, auto, 1\n# CEDAR LOGIN START\n')
        report = reloaded.restore()
        self.assertEqual(self.config.read_text(), 'monitor = , preferred, auto, 1\n')
        self.assertEqual(backup_module.Backup.latest(self.home / '.local/state/cedar/installations'), backup.root)


class PrivateStore(unittest.TestCase):
    def test_store_folders_are_created_private_and_loose_ones_tightened(self):
        from installer.engine.server import private_tree
        import stat as stat_module
        with tempfile.TemporaryDirectory(prefix='cedar store 雨 ') as temp:
            root = Path(temp) / 'state/cedar'
            root.mkdir(parents=True)                      # an earlier interrupted run: default mode
            os.chmod(root, 0o755)
            (root / 'installer').mkdir(); os.chmod(root / 'installer', 0o775)
            tightened = private_tree(root, ('installer', 'installations'))
            for path in (root, root / 'installer', root / 'installations'):
                self.assertEqual(stat_module.S_IMODE(path.stat().st_mode), 0o700, path)
            self.assertEqual(sorted(Path(t).name for t in tightened), ['cedar', 'installer'])
            self.assertEqual(private_tree(root, ('installer',)), [])


class RunnerResume(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='cedar runner 雨 ')
        self.addCleanup(self.temp.cleanup)
        self.state = Path(self.temp.name) / 'state.json'
        self.events = []

    def operations(self, fail_at=None, calls=None):
        calls = calls if calls is not None else []
        def make(op_id):
            def run(ctx, op):
                calls.append(op_id)
                if op_id == fail_at:
                    raise RuntimeError('boom in ' + op_id)
                if op_id == 'migrate':
                    raise ops.Skip('nothing to import')
            return ops.Operation(op_id, op_id.title(), '', run, group='ready' if op_id in ('shell', 'migrate') else '')
        return [make(name) for name in plan_module.OPERATIONS]

    def test_failure_records_state_and_resume_skips_completed_steps(self):
        calls = []
        runner = ops.Runner(self.operations(fail_at='runtime', calls=calls), self.state, None, lambda e, d: self.events.append((e, d)), run_id='run1')
        with self.assertRaises(ops.Failed) as caught:
            runner.run(object())
        self.assertEqual(caught.exception.operation.id, 'runtime')
        self.assertEqual(calls, ['backup', 'leave', 'dependencies', 'runtime'])
        state = ops.load_state(self.state)
        described = ops.describe_state(state)
        self.assertEqual((described['completed'], described['total'], described['failed']), (3, 8, ['runtime']))
        calls2 = []
        runner2 = ops.Runner(self.operations(calls=calls2), self.state, None, lambda e, d: None, run_id='run1')
        runner2.restore_from(state)
        summary = runner2.run(object(), resume=True)
        self.assertEqual(calls2[:1], ['runtime']); self.assertNotIn('backup', calls2)
        self.assertEqual(summary['completed'], 8); self.assertEqual(summary['skipped'], ['migrate'])
        self.assertIsNone(ops.describe_state(ops.load_state(self.state)))

    def test_interrupted_running_step_runs_again(self):
        runner = ops.Runner(self.operations(), self.state, None, lambda e, d: None, run_id='run2')
        runner.run(object())
        state = ops.load_state(self.state)
        state['finished'] = False; state['operations'][4]['state'] = ops.RUNNING
        for row in state['operations'][5:]:
            row['state'] = ops.PENDING
        self.state.write_text(json.dumps(state))
        described = ops.describe_state(ops.load_state(self.state))
        self.assertEqual(described['interruptedAt'], 'shell'); self.assertEqual(described['completed'], 4)
        calls = []
        runner2 = ops.Runner(self.operations(calls=calls), self.state, None, lambda e, d: None, run_id='run2')
        runner2.restore_from(ops.load_state(self.state))
        runner2.run(object(), resume=True)
        self.assertEqual(sorted(calls), ['migrate', 'session', 'shell', 'verify'])

    def test_grouped_independent_steps_run_together(self):
        import threading, time
        seen = {}
        def make(op_id, group=''):
            def run(ctx, op):
                seen[op_id] = threading.current_thread().name; time.sleep(0.05)
            return ops.Operation(op_id, op_id, '', run, group=group)
        runner = ops.Runner([make('a'), make('b', 'g'), make('c', 'g'), make('d')], self.state, None, lambda e, d: None)
        runner.run(object())
        self.assertNotEqual(seen['b'], seen['c']); self.assertEqual(seen['a'], seen['d'])


class DryRunAndCli(unittest.TestCase):
    def test_dry_run_uses_the_same_plan_builder(self):
        import subprocess
        result = subprocess.run([sys.executable, str(ROOT / 'installer/cedar_install.py'), '--dry-run', '--no-gui', '--json'], capture_output=True, text=True, timeout=120,
                                env={**os.environ, 'HOME': tempfile.mkdtemp(prefix='cedar-dry-')})
        self.assertIn('Dry run: nothing was changed.', result.stdout)
        start = result.stdout.index('{\n  "facts"')
        payload = json.loads(result.stdout[start:result.stdout.rindex('}') + 1])
        self.assertEqual([op['id'] for op in payload['plan']['operations']], list(plan_module.OPERATIONS))
        self.assertIn('digest', payload['plan'])


if __name__ == '__main__':
    unittest.main()
