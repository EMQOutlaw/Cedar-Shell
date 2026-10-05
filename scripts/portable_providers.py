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


PROC = Path('/proc')
DESKTOP_PROCESSES = frozenset(('hyprland', 'qs', 'quickshell', 'noctalia',
    'waybar', 'mako', 'dunst', 'hyprlock', 'swaylock', 'hypridle', 'swayidle',
    'swww-daemon', 'awww-daemon', 'hyprpaper', 'swaybg'))


def process_stat(path):
    # comm may contain spaces and parentheses. starttime is stat field 22.
    text = os.fsdecode((path / 'stat').read_bytes())
    head, tail = text.rsplit(')', 1)
    fields = tail.split()
    ticks = fields[19]
    if not ticks.isdigit():
        raise ValueError('Invalid process start time')
    return head.split('(', 1)[1], fields[0], ticks


def read_process(pid, names=None):
    """Verify one provider; unrelated protected applications need no ptrace access.

    names is a discovery filter, never authority to signal a process. A signal
    target is checked again by exact PID/start/executable with no name filter.
    """
    path = PROC / str(int(pid))
    comm = None
    try:
        if path.stat().st_uid != os.getuid():
            return None
        comm, state, ticks = process_stat(path)
        if state in ('Z', 'X', 'x'):
            return None
        try:
            # readlink still identifies an executable replaced by a package
            # upgrade; resolving its now-deleted path would lose a live locker.
            raw_exe = os.readlink(path / 'exe')
        except PermissionError:
            if names is not None and comm.lower() not in names:
                return None
            raise
        deleted = raw_exe.endswith(' (deleted)')
        exe = raw_exe.removesuffix(' (deleted)')
        if not Path(exe).is_absolute():
            raise ValueError('Invalid executable path')
        if names is not None and Path(exe).name.lower() not in names:
            if comm.lower() in names:
                raise d.Refused('Desktop process identity is ambiguous (PID '+path.name+'). No provider will be changed.')
            return None
        argv = [os.fsdecode(arg) for arg in (path / 'cmdline').read_bytes().rstrip(b'\0').split(b'\0')]
        _, next_state, next_ticks = process_stat(path)
        if next_state in ('Z', 'X', 'x'):
            return None
        if next_ticks != ticks or not argv or not argv[0]:
            raise d.Refused('Desktop process changed during inspection (PID '+path.name+'). Retry when it has finished starting.')
        return {'pid': int(pid), 'exe': exe, 'argv': argv, 'start': ticks, 'deleted': deleted}
    except PermissionError as error:
        raise d.Refused('Cannot verify desktop process metadata (PID '+path.name+'). Desktop changes are deferred; cedar preview remains available. Do not run CEDAR as root or relax system permissions.') from error
    except FileNotFoundError as error:
        if names is None or comm is not None and comm.lower() in names:
            try:
                _, state, _ = process_stat(path)
                if state not in ('Z', 'X', 'x'):
                    raise d.Refused('Live desktop process metadata is unavailable (PID '+path.name+'); no provider will be changed.') from error
            except (FileNotFoundError, ProcessLookupError):
                pass
        return None
    except ProcessLookupError:
        return None
    except (OSError, ValueError, UnicodeError, IndexError) as error:
        raise d.Refused('Desktop process ownership could not be verified (PID '+path.name+'); no provider will be changed.') from error


def processes(names=None):
    selected = DESKTOP_PROCESSES if names is None else frozenset(n.lower() for n in names)
    return [row for path in PROC.glob('[0-9]*') if (row := read_process(int(path.name), selected)) is not None]


def process_environment(pid):
    allowed = {'HOME', 'XDG_CONFIG_HOME', 'XDG_DATA_HOME', 'XDG_STATE_HOME', 'XDG_CACHE_HOME',
               'NOCTALIA_CONFIG_HOME', 'NOCTALIA_STATE_HOME', 'NOCTALIA_CONFIG_DIR', 'NOCTALIA_SETTINGS_FILE'}
    raw = (Path('/proc') / str(pid) / 'environ').read_bytes().decode().split('\0')
    return {k: v for item in raw if '=' in item for k, v in [item.split('=', 1)] if k in allowed}


def same_process(row):
    current = read_process(row['pid'])
    return bool(current and all(current[key] == row[key] for key in ('pid', 'start', 'exe'))
                and current['deleted'] == row.get('deleted', False))


def json_response(text, expected_type, source):
    # Responses may contain private data. Name the failing interface, never
    # echo its contents or treat a parse failure as an empty/unlocked desktop.
    try:
        value = json.loads(text)
    except (ValueError, TypeError) as error:
        raise d.Refused(source + ' returned empty or invalid JSON. Desktop changes are deferred; check that provider before retrying cedar try.') from error
    if not isinstance(value, expected_type):
        raise d.Refused(source + ' returned an unexpected JSON structure. Desktop changes are deferred.')
    return value


def qs_instances():
    output = d.command(['qs', 'list', '--all', '-j'], timeout=5)
    # Quickshell 0.3.1 prints this sentence with exit 0 even in JSON mode.
    # Native Noctalia normally has no Quickshell instances at all.
    if output.strip() == 'No running instances.':
        return []
    rows = json_response(output, list, 'Quickshell instance discovery (qs list --all -j)')
    if any(not isinstance(row, dict) or type(row.get('pid')) is not int or row['pid'] <= 0
           or not isinstance(row.get('config_path'), str) or not Path(row['config_path']).is_absolute()
           for row in rows):
        raise d.Refused('Quickshell instance discovery returned invalid process or configuration details. Desktop changes are deferred.')
    return rows


def qs_ipc(source, *args):
    return d.command(['qs', 'ipc', '-p', str(source), 'call', *args], timeout=5).strip()


def compositor_monitors():
    monitors = json_response(d.command(['hyprctl', '-j', 'monitors'], timeout=3), list,
                             'Hyprland monitor discovery (hyprctl -j monitors)')
    if any(not isinstance(m, dict) or not isinstance(m.get('solitaryBlockedBy'), list)
           or any(not isinstance(flag, str) for flag in m['solitaryBlockedBy']) for m in monitors):
        raise d.Refused('This Hyprland version does not expose the reviewed lock indicator. Preview is available; activation is deferred.')
    return monitors


def compositor_locked():
    monitors = compositor_monitors()
    if not monitors:
        raise d.Refused('No readable Hyprland outputs. Start this command inside the Hyprland session.')
    return any('LOCK' in m['solitaryBlockedBy'] for m in monitors)


def compositor_covered():
    monitors = compositor_monitors()
    return bool(monitors) and all('LOCK' in m['solitaryBlockedBy'] for m in monitors)


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
    if row.get('provider', {}).get('deleted'):
        raise d.Refused('The running Noctalia executable was replaced by an update. Finish updating that desktop before trying CEDAR; its locker stays running.')
    rules = d.read_json(root / 'integrations/noctalia/adapter.json')
    if row['adapter'] == 'noctalia-v4':
        for name, checksum in rules['v4']['sourceHashes'].items():
            path = Path(row['providerSource']).parent / name
            if not path.is_file() or d.digest(path) != checksum:
                raise d.Refused('Noctalia v4 differs from the reviewed 4.7.7 API. Existing authentication is preserved; use preview.')
    elif row['adapter'] == 'noctalia-v5':
        version = d.command([row['providerExe'], '--version']).strip()
        # Parse the release field, not git-describe metadata in parentheses.
        # Packaged builds report e.g. noctalia v5.2.1 (5.2.1-1-dirty).
        match = re.fullmatch(r'noctalia v?(\d+\.\d+\.\d+)(?: \([^()\r\n]+\))?', version)
        if not match or match[1] != rules['v5']['version']:
            raise d.Refused('Native Noctalia is outside the reviewed version. Preview remains available; its services are preserved.')


def toml_response(text, source):
    try:
        return tomllib.loads(text)
    except tomllib.TOMLDecodeError as error:
        raise d.Refused(source + ' contains invalid TOML. Existing settings are preserved.') from error


def noctalia_config(row, mode='full'):
    env = process_environment(row['provider']['pid'])
    result = subprocess.run([row['providerExe'], 'config', 'export', mode], env={**os.environ, **env},
                            text=True, capture_output=True, timeout=8)
    if result.returncode: raise d.Refused('Noctalia configuration export failed; existing settings preserved.')
    return toml_response(result.stdout, 'Noctalia '+mode+' configuration')


def toml_overrides(text, values):
    """Edit selected boolean/string keys, preserving comments and unrelated TOML.

    Reject dotted/inline spellings for these targets instead of guessing. Parse
    the complete before/after documents and prove that only approved keys differ.
    """
    before = toml_response(text, 'Noctalia settings')
    expected = copy.deepcopy(before)
    lines = text.splitlines(keepends=True)
    for section, key, value in values:
        parts = tuple(section.split('.')) if isinstance(section, str) else section
        if not isinstance(parts, tuple) or not parts or any(not isinstance(part, str) or not part for part in parts):
            raise d.Refused('Unsupported Noctalia table name.')
        if not re.fullmatch(r'[A-Za-z0-9_-]+', key) or type(value) not in (bool, str):
            raise d.Refused('Unsupported Noctalia override.')
        section_name = '.'.join(part if re.fullmatch(r'[A-Za-z0-9_-]+', part) else json.dumps(part, ensure_ascii=False) for part in parts)
        header = {}
        for part in reversed(parts):
            header = {part: header}
        def is_section(line):
            if not line.lstrip().startswith('['):
                return False
            try:
                return tomllib.loads(line) == header
            except tomllib.TOMLDecodeError:
                return False
        dest = expected
        for part in parts:
            if not isinstance(dest, dict):
                raise d.Refused('Unsupported Noctalia settings table.')
            dest = dest.setdefault(part, {})
        if not isinstance(dest, dict):
            raise d.Refused('Unsupported Noctalia settings table.')
        dest[key] = value
        start = next((i for i, line in enumerate(lines) if is_section(line)), None)
        encoded = json.dumps(value, ensure_ascii=False)
        setting = key + ' = ' + encoded + '\n'
        if start is None:
            lines.extend(['\n[' + section_name + ']\n', setting])
            continue
        end = next((i for i in range(start + 1, len(lines)) if lines[i].lstrip().startswith('[')), len(lines))
        key_pattern = r'(?:' + re.escape(key) + '|"' + re.escape(key) + '"|\x27' + re.escape(key) + '\x27)'
        found = next((i for i in range(start + 1, end) if re.match(r'\s*' + key_pattern + r'\s*=', lines[i])), None)
        if found is None:
            if end and not lines[end - 1].endswith('\n'):
                lines[end - 1] += '\n'
            lines.insert(end, setting)
        else:
            # Simple quoted strings only; multiline/inline tables need review.
            scalar = r'(?:true|false|"(?:[^"\\\n]|\\.)*"|\x27[^\x27\n]*\x27)'
            match = re.fullmatch(r'(\s*' + key_pattern + r'\s*=\s*)'+scalar+r'([^\S\n]*(?:#[^\n]*)?)(\n?)', lines[found])
            if not match:
                raise d.Refused('Unsupported Noctalia scalar setting; existing settings preserved.')
            lines[found] = match[1] + encoded + match[2] + match[3]
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
        data = json_response(qs_ipc(row['providerSource'], 'state', 'all'), dict, 'Noctalia v4 state IPC').get('state', {})
        if not isinstance(data, dict):
            raise d.Refused('Noctalia v4 returned an invalid state object. Desktop changes are deferred.')
        return {'locked': data.get('lockScreenActive'), 'barVisible': data.get('barVisible')}
    return json_response(d.command([row['providerExe'], 'msg', 'status'], timeout=5), dict,
                         'Noctalia status (noctalia msg status)')


def v5_overrides(effective, merged):
    bars = effective.get('bar')
    if not isinstance(bars, dict) or not isinstance(bars.get('order'), list):
        raise d.Refused('Noctalia bar configuration has an unreviewed structure.')
    order = bars['order']
    if any(not isinstance(name, str) or not name or name == 'order' for name in order) or len(set(order)) != len(order) or set(order) != set(bars) - {'order'}:
        raise d.Refused('Noctalia bar order does not match its exported bars. Existing settings preserved.')
    values = [('notification', 'enable_daemon', False), ('osd', 'enabled', False), ('dock', 'enabled', False)]
    user_bars = merged.get('bar', {})
    if not isinstance(user_bars, dict):
        raise d.Refused('Noctalia merged bar configuration has an unreviewed structure.')
    for name in order:
        bar = bars[name]
        if not isinstance(bar, dict) or type(bar.get('enabled')) is not bool or not isinstance(bar.get('monitor', {}), dict):
            raise d.Refused('Noctalia bar configuration has an unreviewed structure.')
        values.append((('bar', name), 'enabled', False))
        for monitor, override in bar.get('monitor', {}).items():
            if not isinstance(override, dict) or type(override.get('enabled')) is not bool or override.get('match') != monitor:
                raise d.Refused('Noctalia monitor override has an unreviewed structure.')
        user_bar = user_bars.get(name, {})
        if not isinstance(user_bar, dict) or not isinstance(user_bar.get('monitor', {}), dict):
            raise d.Refused('Noctalia merged monitor configuration has an unreviewed structure.')
        matches = set()
        for monitor, override in user_bar.get('monitor', {}).items():
            if not isinstance(override, dict) or not isinstance(override.get('match', monitor), str):
                raise d.Refused('Noctalia merged monitor override has an unreviewed structure.')
            matches.add(override.get('match', monitor))
            # Full export renames monitor tables by match. The merged export
            # retains their real keys, which may be aliases. Override those keys
            # so an existing enabled=true cannot win ahead of a duplicate table.
            values.append((('bar', name, 'monitor', monitor), 'enabled', False))
        if matches != set(bar.get('monitor', {})):
            raise d.Refused('Noctalia monitor configuration changed during inspection. Retry before changing desktop surfaces.')
    dock = effective.get('dock', {})
    if not isinstance(dock, dict) or not isinstance(dock.get('monitor', {}), dict):
        raise d.Refused('Noctalia dock configuration has an unreviewed structure.')
    for monitor, override in dock.get('monitor', {}).items():
        if not isinstance(override, dict):
            raise d.Refused('Noctalia dock monitor override has an unreviewed structure.')
        values.append((('dock', 'monitor', monitor), 'enabled', False))
    return values


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
        exports = {}
        for mode in ('full', 'merged'):
            completed = subprocess.run([process['exe'], 'config', 'export', mode], env={**os.environ, **env},
                                       text=True, capture_output=True, timeout=8)
            if completed.returncode:
                raise d.Refused('Noctalia could not export its ' + mode + ' configuration. Existing settings preserved.')
            exports[mode] = toml_response(completed.stdout, 'Noctalia ' + mode + ' configuration export')
        values = v5_overrides(exports['full'], exports['merged'])
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
        if process.get('deleted'):
            raise d.Refused('A desktop provider executable was replaced by an update. Finish updating that desktop before trying CEDAR; no provider was stopped.')
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
    if row['adapter'].startswith('noctalia-'):
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
        data = json_response(qs_ipc(row['providerSource'], 'state', 'all'), dict, 'Noctalia v4 state IPC').get('settings', {})
        if any(data.get(key, {}).get('enabled') is not False for key in ('notifications', 'osd', 'dock')) or data.get('bar', {}).get('displayMode') != 'always_visible':
            raise d.Refused('Waiting for Noctalia to apply the approved surface settings.')
        qs_ipc(row['providerSource'], 'bar', 'hideBar')


def restore_bar(row):
    if row['adapter'] == 'noctalia-v4' and row.get('barWasVisible'):
        qs_ipc(row['providerSource'], 'bar', 'showBar')


def request_lock(row, suspend=False):
    if row['locker'] == 'trailwatch':
        qs_ipc(Path(row['root'])/'shell.qml', 'lock', 'lock')
    elif row['adapter'] == 'noctalia-v4':
        qs_ipc(row['providerSource'], 'lockScreen', 'lock')
    elif row['adapter'] == 'noctalia-v5':
        d.command([row['providerExe'], 'msg', 'session', 'lock'])
    elif row['locker'] == 'hyprlock':
        subprocess.Popen(['hyprlock'], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    else:
        raise d.Refused('Trailwatch owns this session; use its lock IPC.')
    if suspend or row['locker'] == 'trailwatch':
        deadline = time.monotonic() + 12
        while time.monotonic() < deadline:
            if compositor_covered():
                if suspend: d.command(['systemctl', 'suspend'])
                return
            time.sleep(.1)
        raise d.Refused('Lock coverage was not confirmed. Suspend was not requested by CEDAR.')
