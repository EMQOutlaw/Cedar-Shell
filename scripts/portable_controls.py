"""Approved launcher/Trailwatch integration; no edits to upstream-owned files."""
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import time
import distribution as d
import portable_providers as p


def command(action):
    value = shlex.join([sys.executable, str(d.paths()['data'] / 'recovery/portable_session.py'), action])
    if any(c in value for c in ('\n', '\r', '$', '`', '#', ',')):
        raise d.Refused('The integration path needs manual review before writing compositor commands.')
    return value


def keys(binding):
    mask = binding.get('modmask', 0)
    if type(mask) is not int or mask & ~77:
        raise d.Refused('A launcher/lock shortcut uses unsupported modifiers; existing bindings preserved.')
    key = binding.get('key') or ('code:' + str(binding.get('keycode', '')))
    if not re.fullmatch(r'(?:[A-Za-z0-9_]+|code:[0-9]+)', key):
        raise d.Refused('A launcher/lock shortcut needs manual review; existing bindings preserved.')
    mods = [name for bit, name in ((64, 'SUPER'), (4, 'CTRL'), (8, 'ALT'), (1, 'SHIFT')) if mask & bit]
    return mods, key


def destination(binding):
    if binding.get('dispatcher') not in ('exec', 'execr'):
        return None
    try: argv = shlex.split(binding.get('arg', ''))
    except ValueError: return None
    if not argv: return None
    exe, args = Path(argv[0]).name, argv[1:]
    if exe == 'noctalia':
        if args in (['msg', 'launcher', 'toggle'], ['msg', 'launcher', 'show'], ['msg', 'launcher']): return 'launcher'
        if args == ['msg', 'session', 'lock']: return 'lock'
    if exe in ('wofi', 'rofi') and args in (['--show', 'drun'], ['-show', 'drun'], ['-show', 'combi']): return 'launcher'
    if exe == 'fuzzel' and not args: return 'launcher'
    if exe in ('hyprlock', 'swaylock') and not args: return 'lock'
    return None


def shortcut_plan(launcher, trailwatch):
    live = p.json_response(d.command(['hyprctl', '-j', 'binds']), list, 'Hyprland shortcuts')
    if any(not isinstance(b, dict) for b in live): raise d.Refused('Invalid Hyprland shortcut records.')
    chosen = []
    for kind, wanted, fallback in (('launcher', launcher, ['space', 'D']), ('lock', trailwatch, ['L'])):
        if not wanted: continue
        matches = [b for b in live if destination(b) == kind]
        for b in matches:
            if b.get('submap') or any(b.get(flag) for flag in ('release', 'repeat', 'mouse', 'locked', 'longPress', 'catchAll', 'multiKey', 'non_consuming', 'transparent', 'ignore_mods')):
                raise d.Refused('A recognized shortcut has special behavior. Existing bindings preserved; use cedar '+kind+'.')
            mods, key = keys(b)
            same = [other for other in live if other.get('modmask', 0) == b.get('modmask', 0)
                    and str(other.get('key') or other.get('keycode')).lower() == str(b.get('key') or b.get('keycode')).lower()
                    and other.get('submap', '') == b.get('submap', '')]
            if len(same) != 1: raise d.Refused('A shared shortcut has multiple actions; no binding was overwritten.')
            chosen.append({'action': kind, 'mods': mods, 'key': key, 'previous': b['arg']})
        if not matches:
            for key in fallback:
                if not any(b.get('modmask') == 64 and str(b.get('key', '')).lower() == key.lower() for b in live):
                    chosen.append({'action': kind, 'mods': ['SUPER'], 'key': key, 'previous': 'unassigned'})
                    break
            else: raise d.Refused('No unoccupied default '+kind+' shortcut. Existing bindings preserved; configure a shortcut to cedar '+kind+'.')
    return chosen


def render_shortcuts(rows, suffix):
    lines = ['-- CEDAR controls' if suffix == '.lua' else '# CEDAR controls']
    for row in rows:
        mods, key = row['mods'], row['key']
        target = command(row['action'])
        if suffix == '.lua':
            combo = ' + '.join([*mods, key])
            lines += ['hl.unbind('+json.dumps(combo)+')',
                      'hl.bind('+json.dumps(combo)+', hl.dsp.exec_cmd('+json.dumps(target, ensure_ascii=False)+'), {description='+json.dumps('CEDAR '+row['action'])+'})']
        else:
            combo = ' '.join(mods)+', '+key
            lines += ['unbind = '+combo, 'bindd = '+combo+', CEDAR '+row['action']+', exec, '+target]
    return '\n'.join(lines)+'\n'


def plan(row, launcher=False, trailwatch=False):
    if not launcher and not trailwatch: return
    main = p.main_config(); p.safe_target(main)
    folder = d.paths()['config']/'integration'
    bindings, login = folder/('controls'+main.suffix), folder/('login'+main.suffix)
    for path in (bindings, login):
        p.safe_target(path)
        if path.exists(): raise d.Refused('Existing CEDAR control integration needs restoration first.')
    original = main.read_text()
    if 'CEDAR CONTROLS START' in original: raise d.Refused('Existing CEDAR control block needs restoration first.')
    rows = shortcut_plan(launcher, trailwatch)
    if main.suffix == '.lua':
        block = '\n-- CEDAR CONTROLS START\n'
        for path in (bindings, login):
            block += 'do local p = '+json.dumps(str(path), ensure_ascii=False)+'; local f = io.open(p, "r"); if f then f:close(); dofile(p) end end\n'
        block += '-- CEDAR CONTROLS END\n'
    else:
        # An always-present login include is empty until separate login approval.
        for path in (bindings, login):
            if any(c in str(path) for c in ('\n', '\r', '#', '$', '*', '?', '[', ']')): raise d.Refused('Unsafe compositor include path.')
        block = '\n# CEDAR CONTROLS START\nsource = '+str(bindings)+'\nsource = '+str(login)+'\n# CEDAR CONTROLS END\n'
    row['controls'] = {'bindings': rows, 'main': str(main), 'mainAfter': original+block,
                       'before': {str(path): d.info(path) for path in (main, bindings, login)},
                       'file': str(bindings), 'content': render_shortcuts(rows, main.suffix), 'loginFile': str(login)}
    if trailwatch:
        if row['adapter'] != 'noctalia-v5':
            raise d.Refused('Automatic Trailwatch replacement currently supports native Noctalia 5.2.1. Other existing lockers are preserved.')
        executable = shutil.which('hypridle')
        if not executable: raise d.Refused('Trailwatch sleep integration needs hypridle. Run cedar dependencies, approve its package plan, then retry.')
        version = d.command([executable, '--version']).strip()
        if not re.search(r'\bv?0\.1\.7\b', version): raise d.Refused('Trailwatch sleep integration was reviewed with hypridle 0.1.7; this installed version needs review.')
        if any(Path(proc['exe']).name in ('hypridle', 'swayidle') for proc in p.processes()):
            raise d.Refused('Another idle daemon is already running. Its lock integration must be reviewed before adding Trailwatch sleep handling.')
        effective = p.noctalia_config(row)
        lock = effective.get('lockscreen', {})
        behaviors = effective.get('idle', {}).get('behavior')
        if lock.get('enabled') is not True or not isinstance(behaviors, dict):
            raise d.Refused('Noctalia lock/idle configuration needs review before replacing its locker.')
        overrides = [('lockscreen', 'enabled', False)]
        for name, behavior in behaviors.items():
            if not isinstance(behavior, dict): raise d.Refused('Invalid Noctalia idle behavior.')
            if behavior.get('locked_timeout', 0):
                raise d.Refused('Noctalia has a separate locked-state idle timeout. That timing needs review before replacing its locker; it has not been changed.')
            action = behavior.get('action')
            if action in ('lock', 'lock_and_suspend') or action == 'suspend' and behavior.get('lock_before_suspend', True):
                target = command('lock') + (' --suspend' if action != 'lock' else '')
                overrides += [(('idle', 'behavior', name), 'action', 'command'), (('idle', 'behavior', name), 'command', target)]
        row['trailwatch'] = {'surfaceSettings': row['settingsAfter'],
                            'settings': p.toml_overrides(row['settingsAfter'], overrides),
                            'hypridle': executable}
        row['locker'] = 'trailwatch'


def backup(row, tx):
    if not row.get('controls'): return
    for key in ('main', 'file', 'loginFile'):
        path = Path(row['controls'][key]); p.safe_target(path)
        if not d.same(d.info(path), row['controls']['before'][str(path)]):
            raise d.Refused('Compositor configuration changed after the plan. Later edits preserved; retry the reviewed trial.')
        tx.backup(path)
    if row.get('trailwatch'):
        path = d.paths()['state']/('sleep-'+row['id']+'.conf')
        p.safe_target(path)
        if path.exists(): raise d.Refused('An existing sleep-bridge configuration was not overwritten.')
        row['trailwatch']['bridgeConfig'] = str(path)
        tx.backup(path)


def apply(row, tx):
    if not row.get('controls'): return
    controls = row['controls']
    for key, content in (('file', controls['content']), ('loginFile', ''), ('main', controls['mainAfter'])):
        entry = next(e for e in tx.record['files'] if e['path'] == controls[key])
        if not entry.get('after'): tx.apply_file(entry, content.encode(), entry['before'].get('mode', 0o600))
    d.command(['hyprctl', 'reload'])
    if d.command(['hyprctl', 'configerrors']).strip() not in ('', 'ok', '[]'):
        raise d.Refused('Hyprland rejected the CEDAR shortcuts. The original configuration will be restored.')
    live = p.json_response(d.command(['hyprctl', '-j', 'binds']), list, 'Applied CEDAR shortcuts')
    for binding in controls['bindings']:
        mask = sum({'SUPER':64,'CTRL':4,'ALT':8,'SHIFT':1}[m] for m in binding['mods'])
        matches = [b for b in live if b.get('modmask') == mask and
                   (b.get('key') or 'code:'+str(b.get('keycode'))).lower() == binding['key'].lower() and not b.get('submap')]
        if len(matches) != 1 or matches[0].get('dispatcher') != 'exec' or matches[0].get('arg') != command(binding['action']):
            raise d.Refused('CEDAR shortcut did not replace the selected action. Restoring the previous configuration.')


def bridge_unit(row): return 'cedar-lock-sleep-'+row['id']+'-'+row['generation'][:8]


def bridge_ready(row):
    pid = d.command(['systemctl', '--user', 'show', bridge_unit(row), '--property=MainPID', '--value']).strip()
    if not pid.isdigit() or int(pid) <= 0: raise d.Refused('Trailwatch sleep bridge is not running.')
    process = p.read_process(int(pid), {'hypridle'})
    if not process or row['trailwatch']['bridgeConfig'] not in process['argv']:
        raise d.Refused('Trailwatch sleep bridge identity could not be verified.')
    result = p.json_response(d.command(['busctl', '--system', '--json=short', 'call', 'org.freedesktop.login1',
                                      '/org/freedesktop/login1', 'org.freedesktop.login1.Manager', 'ListInhibitors']), dict, 'Sleep inhibitors')
    if result.get('type') != 'a(ssssuu)' or not isinstance(result.get('data'), list) or len(result['data']) != 1 or not isinstance(result['data'][0], list):
        raise d.Refused('Sleep inhibitor response is not the reviewed format.')
    entries = result['data'][0]
    if not any(isinstance(e, list) and len(e) == 6 and 'sleep' in e[0].split(':') and e[3] == 'delay' and e[5] == int(pid) for e in entries):
        raise d.Refused('Waiting for Trailwatch sleep inhibition. The existing locker remains available.')
    return process


def start_bridge(row, tx):
    cfg = Path(row['trailwatch']['bridgeConfig'])
    p.safe_target(cfg)
    row['trailwatch']['bridgeConfig'] = str(cfg)
    value = command('lock')
    # No ScreenSaver ownership: Noctalia keeps its application idle inhibitors.
    content = 'general {\n    lock_cmd = '+value+'\n    inhibit_sleep = 3\n    ignore_dbus_inhibit = true\n'
    content += '    before_sleep_cmd = '+value+'\n}\n'
    entry = next(e for e in tx.record['files'] if e['path'] == str(cfg))
    if not entry.get('after'): tx.apply_file(entry, content.encode())
    elif not d.same(d.info(cfg), entry['after']): raise d.Refused('Sleep bridge settings changed; later edits preserved.')
    args = ['systemd-run', '--user', '--quiet', '--collect', '--unit='+bridge_unit(row),
            '--property=StandardOutput=null', '--property=StandardError=null']
    for key in ('WAYLAND_DISPLAY', 'HYPRLAND_INSTANCE_SIGNATURE', 'XDG_RUNTIME_DIR', 'DBUS_SESSION_BUS_ADDRESS', 'XDG_CONFIG_HOME', 'XDG_DATA_HOME', 'XDG_STATE_HOME', 'PATH'):
        if key in os.environ: args.append('--setenv='+key+'='+os.environ[key])
    d.command([*args, '--', row['trailwatch']['hypridle'], '-c', str(cfg)])


def finish_lock_handoff(row, tx, save, ipc, unlocked):
    if not row.get('trailwatch'): return True
    state = p.json_response(ipc(row, 'shell', 'sessionInfo'), dict, 'CEDAR lock verification')
    watch = row['trailwatch']
    if not watch.get('lockTested'):
        count = state.get('securedUnlocks')
        if type(count) is not int: raise d.Refused('CEDAR cannot report a completed secure unlock. Existing locker retained.')
        if 'unlockBaseline' not in watch:
            watch['unlockBaseline'] = count
            watch['testRequestedAt'] = time.time(); save(row)
            ipc(row, 'lock', 'lock')
            return False
        if state.get('locked'): return False
        if count <= watch['unlockBaseline']:
            if time.time() - watch['testRequestedAt'] > 30:
                raise d.Refused('A secure unlock was not confirmed. The previous locker remains selected.')
            return False
        watch['lockTested'] = True
        row['readyDeadline'] = time.time()+30
        save(row)
    if not row['trailwatch'].get('bridgeStarted'):
        # Save the unit identity before launch; an interrupted launch is recoverable.
        row['trailwatch']['bridgeConfig'] = str(d.paths()['state']/('sleep-'+row['id']+'.conf'))
        row['trailwatch']['bridgeStarted'] = True; save(row)
        start_bridge(row, tx)
    bridge_ready(row)
    unlocked(row)
    entry = tx.record['files'][0]
    desired = row['trailwatch']['settings']
    row['settingsAfter'] = desired; save(row)
    if p.toml_response(Path(entry['path']).read_text(), 'Noctalia settings') != p.toml_response(desired, 'CEDAR handoff'):
        tx.replace_owned_file(entry, desired.encode(), entry['before'].get('mode', 0o600))
    current = p.noctalia_config(row)
    if current.get('lockscreen', {}).get('enabled') is not False:
        raise d.Refused('Waiting for Noctalia to apply the approved Trailwatch handoff.')
    row['trailwatch']['ready'] = True; save(row)
    return True


def restore_lock_handoff(row, tx, save, unlocked):
    if not row.get('trailwatch'): return
    entry = tx.record['files'][0]
    if entry.get('after'):
        desired = row['trailwatch']['surfaceSettings']
        row['settingsAfter'] = desired; save(row)
        if p.toml_response(Path(entry['path']).read_text(), 'Noctalia settings') != p.toml_response(desired, 'CEDAR handoff'):
            tx.replace_owned_file(entry, desired.encode(), entry['before'].get('mode', 0o600))
        current = p.noctalia_config(row)
        if current.get('lockscreen', {}).get('enabled') is not True:
            raise d.Refused('Waiting for the original Noctalia locker before stopping Trailwatch.')
    if row['trailwatch'].get('bridgeStarted'):
        unlocked(row)
        stop_bridge(row)
        row['trailwatch']['bridgeStarted'] = False; row['trailwatch']['ready'] = False; save(row)


def stop_bridge(row):
    loaded = subprocess.run(['systemctl', '--user', 'show', bridge_unit(row), '--property=LoadState', '--value'],
                            text=True, capture_output=True, timeout=8)
    if loaded.stdout.strip() == 'not-found': return
    if loaded.returncode or loaded.stdout.strip() != 'loaded':
        raise d.Refused('Cannot inspect the recorded sleep-bridge unit; no service was stopped.')
    pid = d.command(['systemctl', '--user', 'show', bridge_unit(row), '--property=MainPID', '--value']).strip()
    if not pid.isdigit(): raise d.Refused('Cannot inspect the recorded sleep bridge; no service was stopped.')
    if int(pid):
        process = p.read_process(int(pid), {'hypridle'})
        if not process or row['trailwatch']['bridgeConfig'] not in process['argv']:
            raise d.Refused('The sleep-bridge service changed ownership; no unrelated process was stopped.')
    d.command(['systemctl', '--user', 'stop', bridge_unit(row)])
