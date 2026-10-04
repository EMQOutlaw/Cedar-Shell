"""Inspect and coordinate known Hyprland providers without replacing a locker.

Only narrow, versioned interfaces are accepted. No configuration is executed.
Private process details stay in the private recovery journal, never diagnostics.
"""
import copy
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import time
import tomllib
import distribution as d


def processes():
    rows = []
    for path in Path('/proc').glob('[0-9]*'):
        try:
            if path.stat().st_uid != os.getuid():
                continue
            exe = str((path / 'exe').resolve(strict=True))
            argv = (path / 'cmdline').read_bytes().decode().rstrip('\0').split('\0')
            if not argv or not argv[0]:
                continue
            # /proc stat's command can contain spaces and parentheses.
            ticks = (path / 'stat').read_text().rsplit(')', 1)[1].split()[19]
            rows.append({'pid': int(path.name), 'exe': exe, 'argv': argv, 'start': ticks})
        except PermissionError as error:
            raise d.Refused('Cannot inspect a same-user process; desktop handoff is deferred.') from error
        except (FileNotFoundError, ProcessLookupError):
            continue
        except (OSError, ValueError, UnicodeError, IndexError) as error:
            raise d.Refused('Process ownership could not be verified; no provider will be stopped.') from error
    return rows


def process_environment(pid):
    allowed = {'HOME', 'XDG_CONFIG_HOME', 'XDG_DATA_HOME', 'XDG_STATE_HOME', 'XDG_CACHE_HOME',
               'NOCTALIA_CONFIG_HOME', 'NOCTALIA_STATE_HOME', 'NOCTALIA_CONFIG_DIR', 'NOCTALIA_SETTINGS_FILE'}
    raw = (Path('/proc') / str(pid) / 'environ').read_bytes().decode().split('\0')
    return {k: v for item in raw if '=' in item for k, v in [item.split('=', 1)] if k in allowed}


def same_process(row):
    return any(p['pid'] == row['pid'] and p['start'] == row['start'] and p['exe'] == row['exe'] for p in processes())


def qs_instances():
    rows = json.loads(d.command(['qs', 'list', '--all', '-j'], timeout=5))
    if not isinstance(rows, list):
        raise d.Refused('Cannot read the Quickshell instance list.')
    return rows


def qs_ipc(source, *args):
    return d.command(['qs', 'ipc', '-p', str(source), 'call', *args], timeout=5).strip()


def compositor_locked():
    monitors = json.loads(d.command(['hyprctl', '-j', 'monitors'], timeout=3))
    if not isinstance(monitors, list) or not monitors:
        raise d.Refused('No readable Hyprland outputs. Start this command inside the Hyprland session.')
    if any(not isinstance(m.get('solitaryBlockedBy'), list) for m in monitors):
        raise d.Refused('This Hyprland version does not expose the reviewed lock indicator. Preview is available; activation is deferred.')
    return any('LOCK' in m['solitaryBlockedBy'] for m in monitors)


def compositor_covered():
    monitors = json.loads(d.command(['hyprctl', '-j', 'monitors'], timeout=3))
    return bool(monitors) and isinstance(monitors, list) and all('LOCK' in m.get('solitaryBlockedBy', []) for m in monitors)


def notification_owner():
    result = subprocess.run(['busctl', '--user', 'call', 'org.freedesktop.DBus', '/org/freedesktop/DBus',
                             'org.freedesktop.DBus', 'GetConnectionUnixProcessID', 's', 'org.freedesktop.Notifications'],
                            capture_output=True, text=True, timeout=5, env={**os.environ, 'LC_ALL': 'C'})
    if result.returncode:
        if 'does not exist' in result.stderr or 'has no owner' in result.stderr or 'NameHasNoOwner' in result.stderr:
            return None
        raise d.Refused('Cannot verify notification ownership. No provider was changed.')
    match = re.fullmatch(r'u\s+(\d+)\s*', result.stdout)
    if not match:
        raise d.Refused('Unexpected notification ownership response.')
    return int(match.group(1))


def safe_target(path):
    if not path.is_absolute() or path.is_symlink() or any(p.is_symlink() for p in path.parents):
        raise d.Refused('Managed/symlinked desktop settings need their configuration manager. No target will be followed.')
    if path.exists() and (not path.is_file() or path.stat().st_uid != os.getuid()):
        raise d.Refused('Desktop settings are not an ordinary file owned by this user.')
    if path.exists() and path.stat().st_size > 2 * 1024 * 1024:
        raise d.Refused('Desktop settings exceed the reviewed size limit.')


def main_config():
    config = d.xdg('CONFIG', '.config') / 'hypr'
    candidates = [config / name for name in ('hyprland.lua', 'hyprland.conf') if (config / name).is_file()]
    compositor = [p for p in processes() if Path(p['exe']).name.lower() == 'hyprland']
    if len(compositor) != 1:
        raise d.Refused('Cannot identify one compositor startup configuration.')
    argv = compositor[0]['argv']
    for index, arg in enumerate(argv):
        if arg in ('--config', '-c') and index + 1 < len(argv):
            candidates = [Path(argv[index + 1])]
        elif arg.startswith('--config='):
            candidates = [Path(arg.split('=', 1)[1])]
    if len(candidates) != 1 or not candidates[0].is_absolute() or candidates[0].suffix not in ('.conf', '.lua'):
        raise d.Refused('Main Hyprland config is ambiguous. Preview and session trial remain available; automatic config edits are deferred.')
    return candidates[0]


def verify_noctalia(root, row):
    rules = d.read_json(root / 'integrations/noctalia/adapter.json')
    if row['adapter'] == 'noctalia-v4':
        for name, checksum in rules['v4']['sourceHashes'].items():
            path = Path(row['providerSource']).parent / name
            if not path.is_file() or d.digest(path) != checksum:
                raise d.Refused('Noctalia v4 differs from the reviewed 4.7.7 API. Existing authentication is preserved; use preview.')
    elif row['adapter'] == 'noctalia-v5':
        version = d.command([row['providerExe'], '--version']).strip()
        if not re.search(r'\b' + re.escape(rules['v5']['version']) + r'(?![\w.-])', version):
            raise d.Refused('Native Noctalia is outside the reviewed version. Preview remains available; its services are preserved.')


def toml_overrides(text, values):
    """Edit simple boolean keys only, preserving comments and unrelated TOML.

    Reject dotted/inline spellings for these targets instead of guessing. Parse
    the complete before/after documents and prove that only approved keys differ.
    """
    before = tomllib.loads(text)
    expected = copy.deepcopy(before)
    lines = text.splitlines(keepends=True)
    for section, key, value in values:
        if not re.fullmatch(r'[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)*', section):
            raise d.Refused('Unsupported Noctalia table name.')
        dest = expected
        for part in section.split('.'):
            dest = dest.setdefault(part, {})
        if not isinstance(dest, dict):
            raise d.Refused('Unsupported Noctalia settings table.')
        dest[key] = value
        start = next((i for i, line in enumerate(lines) if re.fullmatch(r'\s*\[' + re.escape(section) + r'\]\s*(?:#.*)?\n?', line)), None)
        setting = key + ' = ' + ('true' if value else 'false') + '\n'
        if start is None:
            lines.extend(['\n[' + section + ']\n', setting])
            continue
        end = next((i for i in range(start + 1, len(lines)) if lines[i].lstrip().startswith('[')), len(lines))
        found = next((i for i in range(start + 1, end) if re.match(r'\s*' + re.escape(key) + r'\s*=', lines[i])), None)
        if found is None:
            lines.insert(end, setting)
        else:
            lines[found] = setting
    result = ''.join(lines)
    try:
        parsed = tomllib.loads(result)
    except tomllib.TOMLDecodeError as error:
        raise d.Refused('Noctalia uses an unsupported TOML spelling; existing settings preserved.') from error
    if parsed != expected:
        raise d.Refused('Noctalia settings could not be changed without affecting other keys.')
    return result


def noctalia_state(row):
    if row['adapter'] == 'noctalia-v4':
        data = json.loads(qs_ipc(row['providerSource'], 'state', 'all')).get('state', {})
        return {'locked': data.get('lockScreenActive'), 'barVisible': data.get('barVisible')}
    return json.loads(d.command([row['providerExe'], 'msg', 'status'], timeout=5))


def v4_settings(original):
    if not isinstance(original, dict) or original.get('settingsVersion') != 59:
        raise d.Refused('Noctalia settings have an unreviewed schema version.')
    changed = copy.deepcopy(original)
    for section in ('notifications', 'osd', 'dock'):
        changed.setdefault(section, {})['enabled'] = False
    changed.setdefault('bar', {})['displayMode'] = 'always_visible'
    for override in changed['bar'].get('screenOverrides', []):
        if isinstance(override, dict): override['displayMode'] = 'always_visible'
    return changed


def inspect_noctalia(root, process, source=None):
    env = process_environment(process['pid'])
    home = Path(env.get('HOME') or Path.home())
    config = Path(env.get('XDG_CONFIG_HOME') or home / '.config')
    state = Path(env.get('XDG_STATE_HOME') or home / '.local/state')
    row = {'provider': process, 'providerExe': process['exe'], 'paused': [], 'locker': 'noctalia', 'background': 'external'}
    if source:
        row.update(adapter='noctalia-v4', providerSource=str(source))
        verify_noctalia(root, row)
        path = Path(env.get('NOCTALIA_SETTINGS_FILE') or Path(env.get('NOCTALIA_CONFIG_DIR') or config / 'noctalia') / 'settings.json')
        safe_target(path)
        original = d.read_json(path)
        changed = v4_settings(original)
        # hideBar on auto-hide bars merely peeks away. Make the temporary
        # display mode explicit so it also removes every pointer reveal area.
        row['settingsAfter'] = json.dumps(changed, indent=2) + '\n'
    else:
        row['adapter'] = 'noctalia-v5'
        verify_noctalia(root, row)
        path = Path(env.get('NOCTALIA_STATE_HOME') or state) / 'noctalia/settings.toml'
        safe_target(path)
        # Read using the running provider's own configured XDG locations.
        completed = subprocess.run([process['exe'], 'config', 'export', 'full'], env={**os.environ, **env},
                                   text=True, capture_output=True, timeout=8)
        if completed.returncode:
            raise d.Refused('Noctalia could not export its effective configuration.')
        effective = tomllib.loads(completed.stdout)
        bars = effective.get('bar', {})
        if not bars or any(not isinstance(value, dict) for value in bars.values()):
            raise d.Refused('Noctalia bar configuration has an unreviewed structure.')
        values = [('notification', 'enable_daemon', False), ('osd', 'enabled', False), ('dock', 'enabled', False)]
        values += [('bar.' + name, 'enabled', False) for name in bars]
        row['settingsAfter'] = toml_overrides(path.read_text() if path.exists() else '', values)
    row['providerSettings'] = str(path)
    status = noctalia_state(row)
    if type(status.get('locked')) is not bool or type(status.get('barVisible')) is not bool:
        raise d.Refused('Noctalia did not report its lock and bar state.')
    if status['locked']:
        raise d.Refused('Noctalia is locked. Unlock normally before trying CEDAR.')
    row['barWasVisible'] = status['barVisible']
    if notification_owner() not in (None, process['pid']):
        raise d.Refused('Another program owns notifications beside Noctalia. Its provider needs review before handoff.')
    return row


def inspect(root):
    if compositor_locked():
        raise d.Refused('Session locked; unlock normally before switching desktop surfaces.')
    all_processes = processes()
    instances = qs_instances()
    for entry in instances:
        source = Path(entry.get('config_path', '/unavailable'))
        if source.name in ('preview.qml', 'auth-test.qml'):
            continue
        if source.name == 'shell.qml' and (source.parent / 'Commons/Settings.qml').is_file() and (source.parent / 'Services/Control/IPCService.qml').is_file():
            proc = next((p for p in all_processes if p['pid'] == entry.get('pid')), None)
            if proc:
                if len([r for r in instances if Path(r.get('config_path', '')).name == 'shell.qml']) != 1:
                    raise d.Refused('Another Quickshell surface is running alongside Noctalia; preserve it until its role is reviewed.')
                return inspect_noctalia(root, proc, source)
        raise d.Refused('An existing Quickshell desktop is running. CEDAR will not stop an unidentified shell; use preview or the explicit supported adapter.')
    native = [p for p in all_processes if Path(p['exe']).name == 'noctalia']
    if len(native) == 1:
        return inspect_noctalia(root, native[0])
    if native:
        raise d.Refused('Multiple native Noctalia processes need review before switching.')
    row = {'adapter': 'hyprland', 'locker': 'trailwatch', 'paused': [], 'background': 'cedar'}
    owner = notification_owner()
    for process in all_processes:
        name = Path(process['exe']).name
        if name in ('swww-daemon', 'awww-daemon', 'hyprpaper', 'swaybg'):
            row['background'] = 'external'
        if name in ('waybar', 'mako', 'dunst'):
            row['paused'].append(process)
        if name in ('swaylock', 'hyprlock'):
            raise d.Refused('A locker is active. Wait until the session is unlocked.')
    if owner is not None and owner not in [p['pid'] for p in row['paused']]:
        raise d.Refused('Notification owner is not a reviewed standalone provider. Existing desktop preserved.')
    hypr_config = d.xdg('CONFIG', '.config') / 'hypr'
    if (hypr_config / 'hyprlock.conf').is_file() and __import__('shutil').which('hyprlock'):
        row['locker'] = 'hyprlock'
    if any(Path(p['exe']).name in ('hypridle', 'swayidle') for p in all_processes) and row['locker'] != 'hyprlock':
        raise d.Refused('Existing idle handling has an unidentified locker. CEDAR preserves it; configure the existing Hyprlock provider or use preview.')
    for process in row['paused']:
        # Prefer the owning user service so Restart= cannot race a direct stop.
        cgroups = (Path('/proc') / str(process['pid']) / 'cgroup').read_text()
        units = re.findall(r'/([^/\n]+\.service)(?:/|\n|$)', cgroups)
        units = [unit for unit in units if not unit.startswith('user@')]
        if units:
            unit = units[-1]
            main_pid = d.command(['systemctl', '--user', 'show', unit, '--property=MainPID', '--value']).strip()
            if main_pid == str(process['pid']):
                process['unit'] = unit
            elif main_pid not in [str(p['pid']) for p in all_processes if Path(p['exe']).name.lower() == 'hyprland']:
                raise d.Refused('A shared service owns a competing provider. CEDAR will not stop unrelated processes.')
        process['cwd'] = str((Path('/proc') / str(process['pid']) / 'cwd').resolve())
        process['environment'] = process_environment(process['pid'])
    return row


def locked(row):
    if compositor_locked():
        return True
    if row['locker'] == 'noctalia':
        if not same_process(row['provider']):
            raise d.Refused('The existing Noctalia authentication host is unavailable.')
        state = noctalia_state(row)
        if type(state.get('locked')) is not bool:
            raise d.Refused('Noctalia lock state is unavailable.')
        return state['locked']
    return False


def pause(process):
    if not same_process(process):
        raise d.Refused('A desktop provider changed since the plan. Run the trial again.')
    if process.get('unit'):
        d.command(['systemctl', '--user', 'stop', process['unit']])
    else:
        fd = os.pidfd_open(process['pid'])
        try:
            if not same_process(process):
                raise d.Refused('Provider identity changed.')
            signal.pidfd_send_signal(fd, signal.SIGTERM)
        finally:
            os.close(fd)


def resume(process):
    if same_process(process):
        return
    # A provider may have been restarted by its owner. Never add a duplicate.
    if any(p['exe'] == process['exe'] for p in processes()):
        return
    if process.get('unit'):
        d.command(['systemctl', '--user', 'start', process['unit']])
    else:
        subprocess.Popen([process['exe'], *process['argv'][1:]], cwd=process['cwd'], stdin=subprocess.DEVNULL,
                         env={**os.environ, **process.get('environment', {})},
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)


def hide_bar(row):
    if row['adapter'] == 'noctalia-v4':
        # Wait for its configuration watcher before hiding an auto-hide bar.
        # Otherwise a late reload could immediately bring the competing bar back.
        data = json.loads(qs_ipc(row['providerSource'], 'state', 'all')).get('settings', {})
        if any(data.get(key, {}).get('enabled') is not False for key in ('notifications', 'osd', 'dock')) or data.get('bar', {}).get('displayMode') != 'always_visible':
            raise d.Refused('Waiting for Noctalia to apply the approved surface settings.')
        qs_ipc(row['providerSource'], 'bar', 'hideBar')


def restore_bar(row):
    if row['adapter'] == 'noctalia-v4' and row.get('barWasVisible'):
        qs_ipc(row['providerSource'], 'bar', 'showBar')


def request_lock(row, suspend=False):
    if row['adapter'] == 'noctalia-v4':
        qs_ipc(row['providerSource'], 'lockScreen', 'lock')
    elif row['adapter'] == 'noctalia-v5':
        d.command([row['providerExe'], 'msg', 'session', 'lock'])
    elif row['locker'] == 'hyprlock':
        subprocess.Popen(['hyprlock'], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    else:
        raise d.Refused('Trailwatch owns this session; use its lock IPC.')
    if suspend:
        deadline = time.monotonic() + 12
        while time.monotonic() < deadline:
            if compositor_covered():
                d.command(['systemctl', 'suspend'])
                return
            time.sleep(.1)
        raise d.Refused('Lock coverage was not confirmed. Suspend canceled.')
