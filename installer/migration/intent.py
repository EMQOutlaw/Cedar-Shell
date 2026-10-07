"""Portable intent from an existing Hyprland setup: what the person wants kept.

Monitors, keyboard, preferred applications and the wallpaper library are read
from the compositor's own configuration (hyprlang `.conf` and Hyprland's Lua
`.lua`) and from the live compositor when available. Nothing here evaluates
configuration as code; includes are followed by name only, bounded, and a
dynamic expression stops the walk for that file. The result is CEDAR's own
monitor format (scripts/desktop.py state rows), not a copy of the old files.
"""
import os
from pathlib import Path
import re

MAX_FILES = 48
CONF_MONITOR = re.compile(r'^\s*monitor\s*=\s*(.+?)\s*$', re.M)
CONF_BLOCK = re.compile(r'^\s*monitorv2\s*\{(.*?)^\s*\}', re.M | re.S)
LUA_MONITOR = re.compile(r'hl\.monitor\s*\(\s*\{(.*?)\}\s*\)', re.S)
LUA_FIELD = re.compile(r'([A-Za-z_]+)\s*=\s*("([^"\\]*(?:\\.[^"\\]*)*)"|\'([^\']*)\'|[-A-Za-z0-9_.@x]+)')
CONF_SOURCE = re.compile(r'^\s*source\s*=\s*(.+?)\s*$', re.M)
LUA_INCLUDE = re.compile(r'hl\.(?:include|source|require)\s*\(\s*"([^"]+)"\s*\)')
KB_KEYS = ('kb_layout', 'kb_variant', 'kb_options', 'kb_model')


def expand(value, home, config_home):
    if any(token in value for token in ('`', '$(', '\0')):
        raise ValueError('dynamic expression')
    value = value.replace('$HOME', str(home)).replace('${HOME}', str(home))
    value = value.replace('$XDG_CONFIG_HOME', str(config_home)).replace('${XDG_CONFIG_HOME}', str(config_home))
    if '$' in value:
        raise ValueError('unresolved variable')
    if value.startswith('~/'):
        value = str(home) + value[1:]
    return value


def walk(host, main):
    """Yield (path, text) for the main file and the includes it names, bounded."""
    seen, queue, out = set(), [Path(main)], []
    unresolved = []
    while queue and len(out) < MAX_FILES:
        path = queue.pop(0)
        if str(path) in seen:
            continue
        seen.add(str(path))
        text = host.read(path)
        if text is None:
            unresolved.append(str(path)); continue
        out.append((path, text))
        pattern = LUA_INCLUDE if path.suffix == '.lua' else CONF_SOURCE
        for match in pattern.finditer(text):
            raw = match.group(1).strip()
            try:
                target = expand(raw, host.home, host.config_home())
            except ValueError:
                unresolved.append(raw); continue
            target_path = Path(target)
            if not target_path.is_absolute():
                target_path = path.parent / target_path
            if any(ch in target for ch in '*?['):
                for found in host.glob(target_path.parent, target_path.name):
                    queue.append(Path(found))
            else:
                queue.append(target_path)
    return out, unresolved


def _lua_fields(body):
    fields = {}
    for match in LUA_FIELD.finditer(body):
        key = match.group(1)
        value = match.group(3) if match.group(3) is not None else match.group(4) if match.group(4) is not None else match.group(2)
        fields[key] = value
    return fields


def parse_monitors(text, syntax):
    """Monitor rows in Hyprland's own vocabulary: output, mode, position, scale, transform, vrr, mirror."""
    rows = []
    if syntax == 'lua':
        for match in LUA_MONITOR.finditer(text):
            fields = _lua_fields(match.group(1))
            rows.append({'output': fields.get('output', ''), 'mode': fields.get('mode', 'preferred'),
                         'position': fields.get('position', 'auto'), 'scale': fields.get('scale', '1'),
                         'transform': fields.get('transform', '0'), 'vrr': fields.get('vrr'), 'mirror': fields.get('mirror')})
        return rows
    for match in CONF_MONITOR.finditer(text):
        parts = [p.strip() for p in match.group(1).split(',')]
        if len(parts) < 4:
            if len(parts) == 2 and parts[1] == 'disable':
                rows.append({'output': parts[0], 'mode': 'disable', 'position': 'auto', 'scale': '1', 'transform': '0', 'vrr': None, 'mirror': None})
            continue
        row = {'output': parts[0], 'mode': parts[1], 'position': parts[2], 'scale': parts[3], 'transform': '0', 'vrr': None, 'mirror': None}
        extra = parts[4:]
        while len(extra) >= 2:
            key, value = extra[0], extra[1]
            if key == 'transform': row['transform'] = value
            elif key == 'vrr': row['vrr'] = value
            elif key == 'mirror': row['mirror'] = value
            extra = extra[2:]
        rows.append(row)
    for match in CONF_BLOCK.finditer(text):
        fields = {}
        for line in match.group(1).splitlines():
            if '=' in line:
                key, value = line.split('=', 1)
                fields[key.strip()] = value.strip()
        rows.append({'output': fields.get('output', ''), 'mode': fields.get('mode', 'preferred'),
                     'position': fields.get('position', 'auto'), 'scale': fields.get('scale', '1'),
                     'transform': fields.get('transform', '0'), 'vrr': fields.get('vrr'), 'mirror': fields.get('mirror')})
    return rows


def parse_keyboard(text, syntax):
    found = {}
    for key in KB_KEYS:
        pattern = re.compile(key + r'\s*=\s*"([^"]*)"') if syntax == 'lua' else re.compile(r'^\s*' + key + r'\s*=\s*(.*?)\s*$', re.M)
        match = pattern.search(text)
        if match and match.group(1).strip():
            found[key] = match.group(1).strip()
    return found


def to_cedar_monitors(rows, live):
    """Translate Hyprland rows into CEDAR's desktop.json monitor rows.

    Wildcard rules (no output name) are not carried over: CEDAR keeps the
    compositor default for outputs it does not describe. `auto` positions
    are resolved from the live compositor when it reports that output.
    """
    by_name = {m.get('name'): m for m in live or [] if isinstance(m, dict)}
    result, notes = [], []
    for row in rows:
        name = row['output']
        if not name or name.startswith('desc:') and name not in by_name:
            if not name:
                notes.append('A wildcard monitor rule was left to the compositor default.')
            continue
        if row['mode'] == 'disable':
            notes.append(name + ' is disabled in your configuration; CEDAR keeps it disabled only if you confirm it in Settings.')
            continue
        live_row = by_name.get(name, {})
        if row['position'] in ('auto', '') or row['position'].startswith('auto'):
            x, y = int(live_row.get('x', 0) or 0), int(live_row.get('y', 0) or 0)
        else:
            try:
                x, y = (int(v) for v in row['position'].split('x'))
            except ValueError:
                x, y = 0, 0
        mode = row['mode']
        if mode in ('preferred', 'highres', 'highrr') and live_row.get('width'):
            mode = str(live_row['width']) + 'x' + str(live_row['height']) + '@' + str(round(float(live_row.get('refreshRate', 60)), 3)).rstrip('0').rstrip('.')
        try:
            scale = float(row['scale']) if row['scale'] not in ('auto', '') else float(live_row.get('scale', 1) or 1)
        except ValueError:
            scale = 1.0
        try:
            transform = int(row['transform'])
        except ValueError:
            transform = 0
        entry = {'name': name, 'mode': mode, 'x': x, 'y': y, 'scale': scale, 'transform': transform}
        if row.get('vrr') not in (None, ''):
            try:
                entry['vrrPolicy'] = int(row['vrr'])
            except ValueError:
                pass
        if row.get('mirror'):
            entry['mirror'] = row['mirror']
        result.append(entry)
    return result, notes


def live_monitors(host):
    code, out, _ = host.run(['hyprctl', '-j', 'monitors'], timeout=5)
    if code != 0:
        return []
    import json
    try:
        value = json.loads(out)
    except ValueError:
        return []
    return value if isinstance(value, list) else []


def live_keyboard(host):
    import json
    found = {}
    for key in KB_KEYS:
        code, out, _ = host.run(['hyprctl', '-j', 'getoption', 'input:' + key], timeout=5)
        if code != 0:
            continue
        try:
            value = json.loads(out).get('str', '')
        except (ValueError, AttributeError):
            value = ''
        if value and value != '[[EMPTY]]':
            found[key] = value
    return found


def inspect_hyprland(host, main):
    """Monitors and keyboard intent from the configuration and the live compositor."""
    result = {'config': str(main) if main else '', 'syntax': '', 'files': [], 'unresolved': [], 'monitors': [], 'monitorRules': [],
              'keyboard': {}, 'notes': []}
    syntax = 'lua' if main and str(main).endswith('.lua') else 'conf'
    result['syntax'] = syntax
    rows, keyboard = [], {}
    if main:
        files, unresolved = walk(host, main)
        result['files'] = [str(p) for p, _ in files]
        result['unresolved'] = unresolved
        for _, text in files:
            rows.extend(parse_monitors(text, syntax))
            for key, value in parse_keyboard(text, syntax).items():
                keyboard.setdefault(key, value)
    live = live_monitors(host) if host.which('hyprctl') else []
    result['monitorRules'] = rows
    result['monitors'], result['notes'] = to_cedar_monitors(rows, live)
    result['liveFull'] = [m for m in live if isinstance(m, dict)]
    result['live'] = [{'name': m.get('name'), 'width': m.get('width'), 'height': m.get('height'), 'refreshRate': m.get('refreshRate'),
                       'x': m.get('x'), 'y': m.get('y'), 'scale': m.get('scale'), 'transform': m.get('transform')} for m in live if isinstance(m, dict)]
    if not result['monitors'] and result['live']:
        # No explicit rules: carry the live arrangement so CEDAR starts where the compositor is.
        result['monitors'] = [{'name': m['name'], 'mode': str(m['width']) + 'x' + str(m['height']) + '@' + str(round(float(m.get('refreshRate') or 60), 3)).rstrip('0').rstrip('.'),
                               'x': int(m.get('x') or 0), 'y': int(m.get('y') or 0), 'scale': float(m.get('scale') or 1), 'transform': int(m.get('transform') or 0)} for m in result['live']]
        result['notes'].append('No explicit monitor rules were found; the live arrangement was recorded instead.')
    result['keyboard'] = keyboard or (live_keyboard(host) if host.which('hyprctl') else {})
    return result


def preferred_apps(host):
    apps = {}
    for key, name in (('TERMINAL', 'terminal'), ('BROWSER', 'browser'), ('EDITOR', 'editor')):
        value = host.environ.get(key, '').strip()
        if value:
            apps[name] = value
    if host.which('xdg-mime'):
        for mime, name in (('x-scheme-handler/http', 'browser'), ('inode/directory', 'files'), ('text/plain', 'editor')):
            code, out, _ = host.run(['xdg-mime', 'query', 'default', mime], timeout=5)
            if code == 0 and out.strip():
                apps.setdefault(name, out.strip())
    return apps


WALLPAPER_DIRS = ('Pictures/Wallpapers', 'Pictures/wallpapers', 'Pictures/Backgrounds', '.config/hypr/wallpapers',
                  '.config/wallpapers', '.local/share/wallpapers', '.config/caelestia/wallpapers', '.config/hyde/wallpapers',
                  '.config/ml4w/wallpapers', '.config/omarchy/current/theme/backgrounds', 'wallpapers', 'Wallpapers')
IMAGE = ('.png', '.jpg', '.jpeg', '.webp', '.avif')


def wallpaper_library(host):
    found = []
    for rel in WALLPAPER_DIRS:
        path = host.home / rel
        if host.is_dir(path):
            count = sum(1 for name in host.listdir(path) if name.lower().endswith(IMAGE))
            if count:
                found.append({'path': str(path), 'images': count})
    return found
