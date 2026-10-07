#!/usr/bin/env python3
"""List and edit what starts with the session: XDG autostart entries and their units.

One JSON request on stdin, one JSON reply on stdout. Entries are the standard
`autostart/*.desktop` files (user then system). On a systemd user session the
xdg-autostart generator runs each as `app-<name>@autostart.service`, so the
reply carries that unit's state. Hyprland `o.launch_on_start(...)` lines in the
user's autostart.lua are reported read-only; that file is the user's to edit.
"""
import json, os, re, shlex, subprocess, sys
from pathlib import Path
import distribution as storage

DESKTOP_SUFFIX = '.desktop'
SYSTEMD_TIMEOUT = 4


def config_home():
    return Path(os.environ.get('XDG_CONFIG_HOME') or Path.home() / '.config')


def user_dir():
    return config_home() / 'autostart'


def system_dirs():
    raw = os.environ.get('XDG_CONFIG_DIRS') or '/etc/xdg'
    return [Path(d) / 'autostart' for d in raw.split(':') if d]


def application_dirs():
    data_home = Path(os.environ.get('XDG_DATA_HOME') or Path.home() / '.local/share')
    raw = os.environ.get('XDG_DATA_DIRS') or '/usr/local/share:/usr/share'
    return [data_home / 'applications'] + [Path(d) / 'applications' for d in raw.split(':') if d]


def current_desktops():
    return [d for d in (os.environ.get('XDG_CURRENT_DESKTOP') or '').split(':') if d]


def valid_id(value):
    return isinstance(value, str) and value.endswith(DESKTOP_SUFFIX) and '/' not in value and not value.startswith('.') and len(value) > len(DESKTOP_SUFFIX)


def parse_desktop(path):
    """Read the [Desktop Entry] group; locale keys keep their raw form."""
    entry, group = {}, None
    try:
        text = path.read_text(encoding='utf-8', errors='replace')
    except OSError:
        return None
    for line in text.splitlines():
        s = line.strip()
        if not s or s.startswith('#'):
            continue
        if s.startswith('['):
            group = s
            continue
        if group != '[Desktop Entry]' or '=' not in s:
            continue
        key, value = s.split('=', 1)
        entry.setdefault(key.strip(), value.strip())
    return entry


def truthy(value):
    return str(value or '').strip().lower() == 'true'


def split_list(value):
    return [v for v in str(value or '').split(';') if v]


def exec_summary(command):
    # Field codes are launch-time placeholders; the generator strips them too.
    return re.sub(r'\s%[a-zA-Z%]', '', str(command or '')).strip()


def systemd_escape(names):
    if not names:
        return []
    try:
        out = subprocess.run(['systemd-escape', '--', *names], capture_output=True, text=True, timeout=SYSTEMD_TIMEOUT)
        lines = out.stdout.splitlines()
        if out.returncode == 0 and len(lines) == len(names):
            return lines
    except (OSError, subprocess.SubprocessError):
        pass
    return [re.sub(r'[^A-Za-z0-9:_.]', lambda m: '\\x%02x' % ord(m.group()), n) for n in names]


def unit_name(escaped):
    return 'app-' + escaped + '@autostart.service'


def unit_states(units):
    """ActiveState/SubState/Result/start time per unit, or {} when systemd is absent."""
    if not units:
        return {}
    try:
        out = subprocess.run(['systemctl', '--user', 'show', '--property=Id,LoadState,ActiveState,SubState,Result,ExecMainStartTimestamp,ExecMainPID', '--', *units],
                             capture_output=True, text=True, timeout=SYSTEMD_TIMEOUT)
    except (OSError, subprocess.SubprocessError):
        return {}
    if out.returncode != 0 and not out.stdout.strip():
        return {}
    states, block = {}, {}
    for line in out.stdout.splitlines() + ['']:
        if not line.strip():
            if block.get('Id'):
                states[block['Id']] = block
            block = {}
            continue
        key, _, value = line.partition('=')
        block[key] = value
    return states


def describe_state(info):
    if not info or info.get('LoadState') not in ('loaded',):
        return 'unknown', ''
    active, sub, result = info.get('ActiveState', ''), info.get('SubState', ''), info.get('Result', '')
    if active == 'active':
        return ('running' if sub == 'running' else 'active'), info.get('ExecMainStartTimestamp', '')
    if active == 'failed' or (result and result not in ('success', '')):
        return 'failed', info.get('ExecMainStartTimestamp', '')
    if active == 'activating':
        return 'starting', ''
    if info.get('ExecMainStartTimestamp'):
        return 'exited', info.get('ExecMainStartTimestamp', '')
    return 'inactive', ''


def find_application(app_id):
    for d in application_dirs():
        candidate = d / app_id
        if candidate.is_file():
            return candidate
        # Subdirectory entries use a dashed id: sub-name.desktop -> sub/name.desktop.
        if '-' in app_id:
            head, _, tail = app_id.partition('-')
            nested = d / head / tail
            if nested.is_file():
                return nested
    return None


def enabled_reason(entry, desktops):
    if truthy(entry.get('Hidden')):
        return 'hidden'
    if 'X-GNOME-Autostart-enabled' in entry and not truthy(entry.get('X-GNOME-Autostart-enabled')):
        return 'hidden'
    only, never = split_list(entry.get('OnlyShowIn')), split_list(entry.get('NotShowIn'))
    if only and not (set(only) & set(desktops)):
        return 'other-desktop'
    if never and (set(never) & set(desktops)):
        return 'other-desktop'
    try_exec = str(entry.get('TryExec') or '').strip()
    if try_exec:
        found = Path(try_exec).is_file() if try_exec.startswith('/') else any((Path(p) / try_exec).is_file() for p in os.environ.get('PATH', '').split(':') if p)
        if not found:
            return 'missing'
    return ''


def collect():
    desktops = current_desktops()
    seen, rows = {}, []
    user = user_dir()
    for path in sorted(user.glob('*' + DESKTOP_SUFFIX)) if user.is_dir() else []:
        entry = parse_desktop(path)
        if entry is None:
            continue
        seen[path.name] = {'id': path.name, 'path': str(path), 'entry': entry, 'source': 'cedar' if truthy(entry.get('X-CEDAR-Startup')) else 'user', 'system': None}
    for d in system_dirs():
        if not d.is_dir():
            continue
        for path in sorted(d.glob('*' + DESKTOP_SUFFIX)):
            if path.name in seen:
                if seen[path.name]['system'] is None:
                    seen[path.name]['system'] = str(path)
                    seen[path.name]['systemEntry'] = parse_desktop(path) or {}
                continue
            entry = parse_desktop(path)
            if entry is None:
                continue
            seen[path.name] = {'id': path.name, 'path': str(path), 'entry': entry, 'source': 'system', 'system': str(path)}
    for item in seen.values():
        entry = item['entry']
        shown = entry if entry.get('Name') or item['source'] == 'system' else item.get('systemEntry') or entry
        reason = enabled_reason(entry, desktops)
        item['row'] = {
            'id': item['id'],
            'name': (shown.get('Name') or item['id'][:-len(DESKTOP_SUFFIX)]).strip(),
            'comment': (shown.get('Comment') or '').strip(),
            'icon': (shown.get('Icon') or '').strip(),
            'exec': exec_summary(shown.get('Exec')),
            'source': item['source'],
            'overrides': bool(item['system']) and item['source'] != 'system',
            'removable': item['source'] != 'system',
            'enabled': reason == '',
            'reason': reason,
            'kind': 'command' if item['source'] == 'cedar' and truthy(entry.get('X-CEDAR-Command')) else 'app',
        }
        rows.append(item)
    names = [r['id'][:-len(DESKTOP_SUFFIX)] for r in rows]
    units = [unit_name(e) for e in systemd_escape(names)]
    states = unit_states(units)
    for item, unit in zip(rows, units):
        state, since = describe_state(states.get(unit))
        item['row'].update({'unit': unit, 'state': state, 'since': since})
    rows.sort(key=lambda r: (not r['row']['enabled'], r['row']['name'].casefold()))
    return [r['row'] for r in rows]


def hyprland_autostart():
    path = config_home() / 'hypr' / 'autostart.lua'
    found = []
    try:
        text = path.read_text(encoding='utf-8', errors='replace')
    except OSError:
        return {'path': '~/.config/hypr/autostart.lua', 'present': False, 'commands': []}
    for line in text.splitlines():
        s = line.strip()
        if not s or s.startswith('--'):
            continue
        m = re.match(r'o\.(launch_on_start|exec_on_start)\s*\(\s*(["\'])(.*?)\2\s*\)', s)
        if m:
            found.append({'kind': m.group(1), 'command': m.group(3)})
    return {'path': '~/.config/hypr/autostart.lua', 'present': True, 'commands': found}


def snapshot(message=''):
    data = {'entries': collect(), 'hyprland': hyprland_autostart(), 'desktop': ':'.join(current_desktops()), 'directory': '~/.config/autostart'}
    if message:
        data['message'] = message
    return data


def write_entry(path, lines):
    storage.atomic(path, ('\n'.join(lines) + '\n').encode(), mode=0o644)


def entry_for(app_id):
    if not valid_id(app_id):
        raise ValueError('Invalid startup entry id.')
    return next((row for row in collect() if row['id'] == app_id), None)


def add_app(app_id):
    if not valid_id(app_id):
        raise ValueError('Invalid desktop application ID.')
    source = find_application(app_id)
    if source is None:
        raise ValueError('That application is not installed, so it cannot start with the session.')
    entry = parse_desktop(source)
    if entry is None or entry.get('Type', 'Application') != 'Application':
        raise ValueError('That desktop entry is not a launchable application.')
    target = user_dir() / app_id
    lines = ['[Desktop Entry]']
    for key in ('Type', 'Name', 'GenericName', 'Comment', 'Icon', 'Exec', 'TryExec', 'Path', 'Terminal', 'StartupNotify', 'StartupWMClass', 'DBusActivatable'):
        if key in entry:
            lines.append(key + '=' + entry[key])
    if 'Type' not in entry:
        lines.insert(1, 'Type=Application')
    lines.append('X-CEDAR-Startup=true')
    lines.append('X-CEDAR-Source=' + str(source))
    write_entry(target, lines)
    return snapshot((entry.get('Name') or app_id) + ' will start with your next session.')


def slug(value):
    s = re.sub(r'[^a-z0-9]+', '-', value.lower()).strip('-')
    return s[:40] or 'command'


def add_command(name, command):
    command = str(command or '').strip()
    if not command:
        raise ValueError('Type a command to run at login.')
    if '\n' in command:
        raise ValueError('A startup command is a single line.')
    try:
        words = shlex.split(command)
    except ValueError as error:
        raise ValueError('That command has unbalanced quotes: ' + str(error)) from None
    if not words:
        raise ValueError('Type a command to run at login.')
    name = str(name or '').strip() or words[0].rsplit('/', 1)[-1]
    # Shell syntax runs through sh so pipes, &&, variables and redirects behave.
    needs_shell = any(ch in command for ch in '|&;<>$`*?~(){}')
    exec_line = 'sh -c ' + shlex.quote(command) if needs_shell else ' '.join(shlex.quote(w) for w in words)
    base = 'cedar-' + slug(name)
    target = user_dir() / (base + DESKTOP_SUFFIX)
    n = 2
    while target.exists():
        target = user_dir() / (base + '-' + str(n) + DESKTOP_SUFFIX)
        n += 1
    lines = ['[Desktop Entry]', 'Type=Application', 'Name=' + name.replace('\n', ' '), 'Comment=Startup command added in CEDAR',
             'Exec=' + exec_line, 'Icon=utilities-terminal', 'Terminal=false', 'StartupNotify=false', 'X-CEDAR-Startup=true', 'X-CEDAR-Command=true']
    write_entry(target, lines)
    return snapshot(name + ' will run at your next login.')


def set_enabled(app_id, enabled):
    row = entry_for(app_id)
    if row is None:
        raise ValueError('That startup entry no longer exists.')
    target = user_dir() / app_id
    if row['source'] == 'system':
        if enabled:
            return snapshot(row['name'] + ' is already on.')
        write_entry(target, ['[Desktop Entry]', 'Hidden=true', 'X-CEDAR-Startup=true'])
        return snapshot(row['name'] + ' will not start next session.')
    entry = parse_desktop(target) or {}
    override_only = set(entry) <= {'Hidden', 'X-CEDAR-Startup', 'X-GNOME-Autostart-enabled'}
    if enabled and override_only and row['overrides']:
        target.unlink(missing_ok=True)
        return snapshot(row['name'] + ' will start next session.')
    text = target.read_text(encoding='utf-8', errors='replace')
    lines = [l for l in text.splitlines() if not re.match(r'\s*(Hidden|X-GNOME-Autostart-enabled)\s*=', l)]
    if not enabled:
        at = next((i for i, l in enumerate(lines) if l.strip() == '[Desktop Entry]'), -1)
        lines.insert(at + 1, 'Hidden=true')
    write_entry(target, lines)
    return snapshot(row['name'] + (' will start next session.' if enabled else ' will not start next session.'))


def remove(app_id):
    row = entry_for(app_id)
    if row is None:
        raise ValueError('That startup entry no longer exists.')
    if not row['removable']:
        raise ValueError('System entries cannot be deleted here; turn them off instead.')
    (user_dir() / app_id).unlink(missing_ok=True)
    return snapshot(row['name'] + (' returns to its system default.' if row['overrides'] else ' removed from startup.'))


def run_now(app_id):
    row = entry_for(app_id)
    if row is None:
        raise ValueError('That startup entry no longer exists.')
    if not row['enabled']:
        raise ValueError('Turn ' + row['name'] + ' on before running it.')
    if row['state'] in ('running', 'active', 'starting'):
        return snapshot(row['name'] + ' is already running.')
    try:
        p = subprocess.run(['systemctl', '--user', 'start', '--no-block', '--', row['unit']], capture_output=True, text=True, timeout=SYSTEMD_TIMEOUT)
        if p.returncode == 0:
            return snapshot('Started ' + row['name'] + '.')
    except (OSError, subprocess.SubprocessError):
        pass
    # No generated unit (not a systemd session): launch the entry directly.
    source = user_dir() / app_id if (user_dir() / app_id).is_file() else next((d / app_id for d in system_dirs() if (d / app_id).is_file()), None)
    if source is None:
        raise RuntimeError('The entry could not be found to launch.')
    argv = ['gio', 'launch', str(source)]
    try:
        subprocess.Popen(argv, start_new_session=True, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except OSError as error:
        raise RuntimeError('Could not launch ' + row['name'] + ': ' + str(error)) from None
    return snapshot('Launched ' + row['name'] + '.')


def stop(app_id):
    row = entry_for(app_id)
    if row is None:
        raise ValueError('That startup entry no longer exists.')
    try:
        p = subprocess.run(['systemctl', '--user', 'stop', '--', row['unit']], capture_output=True, text=True, timeout=SYSTEMD_TIMEOUT)
    except (OSError, subprocess.SubprocessError) as error:
        raise RuntimeError('Could not stop ' + row['name'] + ': ' + str(error)) from None
    if p.returncode != 0:
        raise RuntimeError('Could not stop ' + row['name'] + '.')
    return snapshot('Stopped ' + row['name'] + '.')


def main(request):
    action = request.get('action', 'list')
    if action == 'list':
        return snapshot()
    if action == 'add_app':
        return add_app(request.get('id'))
    if action == 'add_command':
        return add_command(request.get('name'), request.get('command'))
    if action == 'set_enabled':
        return set_enabled(request.get('id'), bool(request.get('enabled')))
    if action == 'remove':
        return remove(request.get('id'))
    if action == 'run':
        return run_now(request.get('id'))
    if action == 'stop':
        return stop(request.get('id'))
    raise ValueError('Unknown startup action.')


if __name__ == '__main__':
    try:
        raw = sys.stdin.readline() if not sys.stdin.isatty() else ''
        request = json.loads(raw) if raw.strip() else {}
        if not isinstance(request, dict):
            raise ValueError('The request must be a JSON object.')
        print(json.dumps({'ok': True, 'data': main(request)}))
    except (ValueError, OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(json.dumps({'ok': False, 'error': str(error)}))
