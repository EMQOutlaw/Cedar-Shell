#!/usr/bin/env python3
"""CEDAR's small, transactional Hyprland settings backend (Lua configuration).

Only explicit Apply requests write configuration. User overrides are never edited.
Display changes are restored by an independent watchdog unless confirmed.
"""
import contextlib
import fcntl
import json
import math
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
import uuid

CONFIG = Path(os.environ.get('XDG_CONFIG_HOME', Path.home()/'.config'))
OWN = CONFIG/'cedar/hypr'
MAIN = Path(os.environ['CEDAR_HYPR_CONFIG']) if os.environ.get('CEDAR_HYPR_CONFIG') else (CONFIG/'hypr/hyprland.lua' if (CONFIG/'hypr/hyprland.lua').is_file() else CONFIG/'hypr/hyprland.conf')
INPUTS = {
    'kb_layout': ('str', None), 'kb_variant': ('str', None),
    'repeat_rate': ('int', (1, 100)), 'repeat_delay': ('int', (100, 2000)),
    'numlock_by_default': ('bool', None), 'sensitivity': ('float', (-1, 1)),
    'accel_profile': ('enum', ('flat', 'adaptive', '')),
    'natural_scroll': ('bool', None), 'touchpad:tap-to-click': ('bool', None),
    'touchpad:natural_scroll': ('bool', None), 'touchpad:disable_while_typing': ('bool', None),
    'touchpad:scroll_factor': ('float', (.1, 5)),
}

# Window-manager options Settings › Windows owns, mapped onto Hyprland option
# paths. Kinds: bool, int, float, enum, color (hex or gradient), css_int
# (CssGap rendered uniform), vec2x/vec2y (components of a Vec2 option).
WINDOWS = {
    'layout': ('general.layout', 'enum', ('dwindle', 'master', 'scrolling')),
    'gaps_in': ('general.gaps_in', 'css_int', (0, 50)),
    'gaps_out': ('general.gaps_out', 'css_int', (0, 100)),
    'gaps_workspaces': ('general.gaps_workspaces', 'css_int', (0, 100)),
    'border_size': ('general.border_size', 'int', (0, 20)),
    'resize_on_border': ('general.resize_on_border', 'bool', None),
    'extend_border_grab_area': ('general.extend_border_grab_area', 'int', (0, 50)),
    'hover_icon_on_border': ('general.hover_icon_on_border', 'bool', None),
    'no_focus_fallback': ('general.no_focus_fallback', 'bool', None),
    'resize_corner': ('general.resize_corner', 'int', (0, 4)),
    'snap_enabled': ('general.snap.enabled', 'bool', None),
    'allow_tearing': ('general.allow_tearing', 'bool', None),
    'rounding': ('decoration.rounding', 'int', (0, 24)),
    'rounding_power': ('decoration.rounding_power', 'float', (1.0, 10.0)),
    'active_opacity': ('decoration.active_opacity', 'float', (0.0, 1.0)),
    'inactive_opacity': ('decoration.inactive_opacity', 'float', (0.0, 1.0)),
    'fullscreen_opacity': ('decoration.fullscreen_opacity', 'float', (0.0, 1.0)),
    'dim_inactive': ('decoration.dim_inactive', 'bool', None),
    'dim_strength': ('decoration.dim_strength', 'float', (0.0, 1.0)),
    'dim_special': ('decoration.dim_special', 'float', (0.0, 1.0)),
    'dim_around': ('decoration.dim_around', 'float', (0.0, 1.0)),
    'dim_modal': ('decoration.dim_modal', 'bool', None),
    'blur_enabled': ('decoration.blur.enabled', 'bool', None),
    'blur_size': ('decoration.blur.size', 'int', (1, 30)),
    'blur_passes': ('decoration.blur.passes', 'int', (1, 8)),
    'blur_xray': ('decoration.blur.xray', 'bool', None),
    'blur_vibrancy': ('decoration.blur.vibrancy', 'float', (0.0, 1.0)),
    'blur_noise': ('decoration.blur.noise', 'float', (0.0, 1.0)),
    'blur_contrast': ('decoration.blur.contrast', 'float', (0.0, 2.0)),
    'blur_brightness': ('decoration.blur.brightness', 'float', (0.0, 2.0)),
    'blur_special': ('decoration.blur.special', 'bool', None),
    'blur_popups': ('decoration.blur.popups', 'bool', None),
    'blur_ignore_opacity': ('decoration.blur.ignore_opacity', 'bool', None),
    'blur_new_optimizations': ('decoration.blur.new_optimizations', 'bool', None),
    'blur_vibrancy_darkness': ('decoration.blur.vibrancy_darkness', 'float', (0.0, 3.0)),
    'shadow_enabled': ('decoration.shadow.enabled', 'bool', None),
    'shadow_range': ('decoration.shadow.range', 'int', (1, 100)),
    'shadow_offset_x': ('decoration.shadow.offset', 'vec2x', (-50, 50)),
    'shadow_offset_y': ('decoration.shadow.offset', 'vec2y', (-50, 50)),
    'shadow_render_power': ('decoration.shadow.render_power', 'int', (1, 4)),
    'shadow_sharp': ('decoration.shadow.sharp', 'bool', None),
    'shadow_scale': ('decoration.shadow.scale', 'float', (0.0, 1.0)),
    'shadow_color': ('decoration.shadow.color', 'color', None),
    'glow_enabled': ('decoration.glow.enabled', 'bool', None),
    'glow_range': ('decoration.glow.range', 'int', (1, 50)),
    'glow_render_power': ('decoration.glow.render_power', 'int', (1, 4)),
    'glow_color': ('decoration.glow.color', 'color', None),
    'col_active_border': ('general.col.active_border', 'color', None),
    'col_inactive_border': ('general.col.inactive_border', 'color', None),
    'animations_enabled': ('animations.enabled', 'bool', None),
}


def parse_color(value):
    """Canonical colour: ([AARRGGBB stops lowercase], angle). Accepts the forms
    Hyprland reads or reports: rgba(RRGGBBAA), rgba(r,g,b,a), 0xAARRGGBB, bare
    AARRGGBB, #RGB(A), and the getoption gradient string 'AARRGGBB … Ndeg'."""
    v = str(value).strip().lower()
    match = re.fullmatch(r'rgba\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*([\d.]+)\s*\)', v)
    if match:
        r, g, b = int(match.group(1)), int(match.group(2)), int(match.group(3))
        a = float(match.group(4))
        alpha = round(a * 255) if a <= 1 else round(a)
        if not all(0 <= c <= 255 for c in (r, g, b, alpha)):
            raise ValueError('Invalid colour: ' + str(value))
        return ([f'{alpha:02x}{r:02x}{g:02x}{b:02x}'], 0)
    match = re.fullmatch(r'rgba\(([0-9a-f]{8})\)', v)
    if match:
        # rgba() takes RRGGBBAA; the canonical stop is AARRGGBB.
        h = match.group(1)
        return ([h[6:8] + h[0:6]], 0)
    v = v.lstrip('#')
    if re.fullmatch(r'0x[0-9a-f]{8}', v):
        return ([v[2:]], 0)
    if re.fullmatch(r'[0-9a-f]{6}', v):
        return (['ff' + v], 0)
    match = re.fullmatch(r'((?:[0-9a-f]{8}\s*)+?)(\d+)deg', v)
    if match:
        return (match.group(1).split(), int(match.group(2)))
    if re.fullmatch(r'[0-9a-f]{8}', v):
        return ([v], 0)
    raise ValueError('Invalid colour: ' + str(value))


def norm_color(value):
    """Config-input form: solids as exact-byte 0xAARRGGBB (accepted by every
    colour option probed on the running compositor; rgba(r,g,b,a) loses alpha
    to float conversion); gradients as a {colors={0x…},angle=N} table."""
    stops, angle = parse_color(value)
    if len(stops) == 1 and angle == 0:
        # Exact-byte form, accepted by every colour option probed on the
        # running compositor; rgba(r,g,b,a) loses alpha to float conversion.
        return '0x' + stops[0]
    return {'colors': ['0x' + stop for stop in stops], 'angle': angle}


def validate_windows(values):
    output = {}
    for key, value in values.items():
        if key not in WINDOWS:
            raise ValueError('Unsupported window option: ' + key)
        kind, allowed = WINDOWS[key][1], WINDOWS[key][2]
        if kind == 'bool':
            if type(value) is not bool:
                raise ValueError(key + ' requires true or false.')
        elif kind in ('int', 'float', 'css_int', 'vec2x', 'vec2y'):
            value = float(value)
            if not math.isfinite(value) or not allowed[0] <= value <= allowed[1]:
                raise ValueError(key + ' is out of range.')
            if kind in ('int', 'css_int', 'vec2x', 'vec2y'):
                if not value.is_integer():
                    raise ValueError(key + ' must be an integer.')
                value = int(value)
        elif kind == 'enum':
            if value not in allowed:
                raise ValueError('Invalid ' + key)
        elif kind == 'color':
            value = norm_color(value)
        output[key] = value
    return output


def css_uniform(text):
    """'5' or '5 5 5 5' -> 5; anything else stays a string (per-side gaps)."""
    parts = str(text).split()
    try:
        numbers = [int(p) for p in parts]
    except ValueError:
        return text
    if numbers and all(n == numbers[0] for n in numbers):
        return numbers[0]
    return text


def windows_live():
    """Live values by CEDAR key. An option whose getoption reply lacks the
    expected field is an error, never a fabricated default."""
    values, errors = {}, {}
    def need(data, field):
        if field not in data:
            raise ValueError('getoption returned no ' + field)
        return data[field]
    for key, (path, kind, allowed) in WINDOWS.items():
        try:
            data = json.loads(command(['hyprctl', '-j', 'getoption', path]))
            if kind == 'bool':
                raw = data.get('bool', data.get('int'))
                if isinstance(raw, bool):
                    values[key] = raw
                elif isinstance(raw, int) and raw in (0, 1):
                    values[key] = bool(raw)
                else:
                    raise ValueError('getoption returned a malformed bool: ' + repr(raw))
            elif kind in ('int',):
                raw = need(data, 'int')
                if isinstance(raw, bool) or not isinstance(raw, int):
                    raise ValueError('getoption returned a malformed int: ' + repr(raw))
                values[key] = raw
            elif kind in ('float',):
                raw = data.get('float', data.get('int'))
                if isinstance(raw, bool) or not isinstance(raw, (int, float)):
                    raise ValueError('getoption returned a malformed float: ' + repr(raw))
                raw = float(raw)
                if raw != raw or raw in (float('inf'), float('-inf')):
                    raise ValueError('getoption returned a non-finite float')
                values[key] = raw
            elif kind == 'enum':
                values[key] = str(need(data, 'str'))
            elif kind == 'color':
                raw = data.get('gradient', data.get('str'))
                if raw is None:
                    raise ValueError('getoption returned no gradient')
                values[key] = str(raw)
            elif kind == 'css_int':
                raw = data.get('css', data.get('int'))
                if raw is None:
                    raise ValueError('getoption returned no css')
                values[key] = css_uniform(raw)
            elif kind in ('vec2x', 'vec2y'):
                vec = need(data, 'vec2')
                if not isinstance(vec, list) or len(vec) != 2:
                    raise ValueError('getoption returned a malformed vec2')
                values[key] = float(vec[0] if kind == 'vec2x' else vec[1])
        except Exception as e:
            errors[key] = str(e)
    return values, errors


def render_windows(state):
    windows = state.get('windows', {})
    if not windows:
        return []
    groups = {}
    for key, value in windows.items():
        path, kind, _ = WINDOWS[key]
        if kind in ('vec2x', 'vec2y'):
            continue  # merged below
        if kind == 'color' and isinstance(value, str):
            value = norm_color(value)  # idempotent; keeps hand-edited state valid too
        node = groups
        parts = path.split('.')
        for part in parts[:-1]:
            node = node.setdefault(part, {})
        node[parts[-1]] = value
    lines = ['hl.config(' + lua(groups) + ')'] if groups else []
    if 'shadow_offset_x' in windows or 'shadow_offset_y' in windows:
        # vec2 takes a positional {x, y} array (named keys are rejected). When
        # CEDAR owns only one axis, the companion is resolved from the live
        # config AT LOAD TIME — baking in a Python-time value would silently
        # override upstream changes to the unowned axis on every reload.
        if 'shadow_offset_x' in windows and 'shadow_offset_y' in windows:
            lines.append('hl.config({["decoration"]={["shadow"]={["offset"]=' + lua([windows['shadow_offset_x'], windows['shadow_offset_y']]) + '}}})')
        else:
            owned_x = 'shadow_offset_x' in windows
            literal = lua(windows['shadow_offset_x'] if owned_x else windows['shadow_offset_y'])
            pair = ('{' + literal + ', __cedar_off[2]}') if owned_x else ('{__cedar_off[1], ' + literal + '}')
            lines.append('do local __cedar_off = hl.get_config("decoration.shadow.offset") or {0, 0}; '
                         'hl.config({["decoration"]={["shadow"]={["offset"]=' + pair + '}}}) end')
    return lines


def verify_windows(values):
    live, live_errors = windows_live()
    for key, wanted in values.items():
        if key in live_errors or key not in live:
            raise ValueError(key + ' could not be verified against the running compositor; your previous settings were restored.')
        kind = WINDOWS[key][1]
        effective = live.get(key)
        if kind == 'float':
            matches = isinstance(effective, (int, float)) and math.isclose(effective, wanted, abs_tol=1e-3)
        elif kind == 'color':
            try:
                matches = parse_color(effective) == parse_color(
                    wanted if isinstance(wanted, str) else
                    ' '.join(stop[2:] for stop in wanted['colors']) + ' ' + str(wanted.get('angle', 0)) + 'deg')
            except ValueError:
                matches = False
        else:
            matches = effective == wanted
        if not matches:
            raise ValueError('A later override prevented ' + key + ' from applying. Your previous settings were restored; edit the user override first.')


def command(argv):
    result = subprocess.run(argv, text=True, capture_output=True, timeout=10, env={**os.environ, 'LC_ALL': 'C'})
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip() or f'{argv[0]} failed')
    return result.stdout.strip()

def hypr(query):
    return json.loads(command(['hyprctl', '-j', query]))

def atomic(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix='.'+path.name, dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as f:
            f.write(text); f.flush(); os.fsync(f.fileno())
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp): os.unlink(tmp)

def lua(value):
    if isinstance(value, bool): return 'true' if value else 'false'
    if isinstance(value, (int, float)):
        if not math.isfinite(value): raise ValueError('Numbers must be finite.')
        return str(value)
    if isinstance(value, str):
        # Lua decimal byte escapes avoid code injection and preserve UTF-8 exactly.
        return '"' + ''.join(chr(b) if 32 <= b < 127 and b not in (34, 92) else f'\\{b:03d}' for b in value.encode()) + '"'
    if isinstance(value, list): return '{' + ', '.join(lua(v) for v in value) + '}'
    if isinstance(value, dict): return '{' + ', '.join('['+lua(k)+']='+lua(v) for k,v in value.items()) + '}'
    raise ValueError('Unsupported Lua value')

def read_state():
    file = OWN/'settings.json'
    return json.loads(file.read_text()) if file.exists() else {'input': {}, 'monitors': [], 'bindings': []}

def combo(binding):
    mods = [name for bit, name in [(64, 'SUPER'), (4, 'CTRL'), (8, 'ALT'), (1, 'SHIFT')] if int(binding.get('modmask', 0)) & bit]
    key = binding.get('key') or ('code:'+str(binding['keycode']))
    return ' + '.join(mods+[str(key).upper()])

def validate_combo(value):
    parts = [p.strip().upper() for p in value.split('+')]
    if not parts or not re.fullmatch(r'(?:[A-Z0-9_]+|CODE:\d+)', parts[-1]):
        raise ValueError('Use a letter, keysym, function key, or code:number for the shortcut.')
    if any(m not in ('SUPER','CTRL','ALT','SHIFT') for m in parts[:-1]) or len(set(parts[:-1])) != len(parts[:-1]):
        raise ValueError('Invalid modifier combination.')
    return ' + '.join([m for m in ('SUPER','CTRL','ALT','SHIFT') if m in parts[:-1]] + [parts[-1]])

def validate_inputs(values):
    output = {}
    for key, value in values.items():
        if key not in INPUTS: raise ValueError('Unsupported input option: '+key)
        kind, allowed = INPUTS[key]
        if kind == 'bool':
            if type(value) is not bool: raise ValueError(key+' requires true or false.')
        elif kind in ('int', 'float'):
            value = float(value)
            if not math.isfinite(value) or not allowed[0] <= value <= allowed[1]: raise ValueError(key+' is out of range.')
            if kind == 'int':
                if not value.is_integer(): raise ValueError(key+' must be an integer.')
                value = int(value)
        elif kind == 'enum':
            if value not in allowed: raise ValueError('Invalid '+key)
        elif not isinstance(value, str) or not re.fullmatch(r'[a-zA-Z0-9_,() -]{0,120}', value):
            raise ValueError('Invalid keyboard layout or variant.')
        output[key] = value
    return output

def validate_monitors(values, current):
    existing = {m['name']:m for m in current if not m.get('disabled')}
    if {m['name'] for m in values} != set(existing) or len(values) != len(existing):
        raise ValueError('Outputs changed. Refresh before applying. All active outputs must remain enabled.')
    result = []
    for m in values:
        live = existing[m['name']]
        mode = m['mode']
        if not re.fullmatch(r'\d+x\d+@\d+(?:\.\d+)?(?:Hz)?', mode): raise ValueError('Invalid display mode.')
        current_mode = f"{live['width']}x{live['height']}@{live['refreshRate']:.2f}"
        valid = [x.removesuffix('Hz') for x in live.get('availableModes', [])] + [current_mode]
        if mode.removesuffix('Hz') not in valid: raise ValueError('Mode is not reported by this display: '+mode)
        scale = float(m['scale'])
        if not math.isfinite(scale) or not .5 <= scale <= 4: raise ValueError('Scale must be between 0.5 and 4.')
        x,y,rotation = int(m['x']),int(m['y']),int(m.get('transform',0))
        if not -32768 <= x <= 32768 or not -32768 <= y <= 32768 or rotation not in range(8): raise ValueError('Invalid position or rotation.')
        vrr={}
        if m.get('vrrPolicy',-2)!=-2:
            if 'vrr' not in live: raise ValueError('VRR is not reported by this display.')
            policy=m['vrrPolicy']
            if type(policy) is not int or policy not in (-1,0,1,2,3): raise ValueError('Invalid VRR policy.')
            vrr={'vrrPolicy':policy}
        mirror={'mirror':m['mirror']} if m.get('mirror') else {}
        result.append({**vrr,**mirror,'name': m['name'], 'mode': mode.removesuffix('Hz'), 'x': x, 'y': y, 'scale': scale, 'transform': rotation})
    sources={m['name'] for m in result if not m.get('mirror')}
    for m in result:
        if m.get('mirror') and (m['mirror'] == m['name'] or m['mirror'] not in sources):
            raise ValueError(m['name']+' can only mirror another connected display that is not itself mirroring.')
    if not sources: raise ValueError('At least one display must show its own desktop.')
    return result

PROFILE_NAME = re.compile(r'[\w .()\-]{1,40}')
MAX_PROFILES = 12

def save_profile(state, name, monitors, main_display=''):
    """Store a validated layout. Profiles are data only; loading one still uses the display trial."""
    name = str(name).strip()
    if not PROFILE_NAME.fullmatch(name): raise ValueError('Name the layout with up to 40 letters, numbers, spaces, dots, dashes or brackets.')
    rows = validate_monitors(monitors, hypr('monitors'))
    if main_display and main_display not in {m['name'] for m in rows}: raise ValueError('The main display must be part of the layout.')
    profiles = [p for p in state.get('displayProfiles', []) if p['name'] != name]
    if len(profiles) >= MAX_PROFILES: raise ValueError(f'Up to {MAX_PROFILES} layouts can be saved. Delete one first.')
    profiles.append({'name': name, 'monitors': rows, 'mainDisplay': main_display or '', 'saved': int(time.time())})
    state['displayProfiles'] = sorted(profiles, key=lambda p: p['name'].lower())
    return state

def write_state(state):
    from portable_providers import safe_target
    safe_target(OWN/'settings.json')
    atomic(OWN/'settings.json', json.dumps(state, indent=2))

def session_script():
    """CEDAR's own session launcher at a path that survives updates: the live
    profile when one exists, otherwise the installed release."""
    profile = CONFIG/'quickshell/cedar/scripts/cedar_session.py'
    if profile.is_file(): return profile
    data = Path(os.environ.get('XDG_DATA_HOME') or Path.home()/'.local/share')
    return data/'cedar/current/scripts/cedar_session.py'

def session_command():
    return shlex.join(['python3', str(session_script()), 'start'])

def render_lua(state):
    lines = ['-- Generated by CEDAR. Put personal overrides in user.lua.']
    if state.get('sessionStart', True):
        # CEDAR is the desktop: it starts with Hyprland, needing nothing else.
        lines.append('hl.on("hyprland.start", function() hl.exec_cmd('+lua(session_command())+') end)')
    inputs = {}
    for key, value in state.get('input',{}).items():
        if ':' in key:
            group, leaf = key.split(':',1); inputs.setdefault(group,{})[leaf] = value
        else: inputs[key] = value
    if inputs: lines.append('hl.config('+lua({'input': inputs})+')')
    lines.extend(render_windows(state))
    if state.get('mainDisplay'):
        output = state['mainDisplay']
        lines.append('hl.config('+lua({'cursor': {'default_monitor': output}})+')')
        # Xwayland has its own primary output. Apply it again on login, without
        # altering resolution, placement, workspace rules or focus on reload.
        startup = shlex.join(['xrandr', '--output', output, '--primary'])
        lines.append('hl.on("hyprland.start", function() hl.exec_cmd('+lua(startup)+') end)')
    for m in state.get('monitors',[]):
        monitor={'output':m['name'],'mode':m['mode'],'position':f"{m['x']}x{m['y']}",'scale':m['scale'],'transform':m['transform']}
        if 'vrrPolicy' in m: monitor['vrr']=m['vrrPolicy']
        if m.get('mirror'): monitor['mirror']=m['mirror']
        lines.append('hl.monitor('+lua(monitor)+')')
    if state.get('keybinds'):
        # CEDAR's keybind set, copied to the owned folder so it is the user's to edit.
        lines.append('do local f = io.open('+lua(str(OWN/'keybinds.lua'))+', "r") if f then f:close(); dofile('+lua(str(OWN/'keybinds.lua'))+') end end')
    for b in state.get('bindings',[]):
        for original in b.get('originals', [b['original']] if b.get('original') else []):
            lines.append('hl.unbind('+lua(original)+')')
        lines.append('hl.unbind('+lua(b['keys'])+')')
        lines.append('hl.bind('+lua(b['keys'])+', hl.dsp.exec_cmd('+lua(b['command'])+'), '+lua({'description': b['description']})+')')
    return '\n'.join(lines)+'\n'

def loader_lua(directory=None):
    return '\n-- CEDAR graphical settings (user overrides load last).\ndo\n  local dir = '+lua(str(directory if directory is not None else OWN))+'\n  for _, name in ipairs({"generated.lua", "user.lua"}) do\n    local path = dir .. "/" .. name\n    local f = io.open(path, "r")\n    if f then f:close(); dofile(path) end\n  end\nend\n'

def syntax():
    return 'lua' if MAIN.suffix == '.lua' else 'conf'

def generated():
    return OWN / ('generated.' + syntax())

def marker():
    return ('--' if syntax() == 'lua' else '#') + ' CEDAR graphical settings (user overrides load last).'

def conf_value(value):
    if isinstance(value, bool): return 'true' if value else 'false'
    text = str(value)
    if any(c in text for c in ('\n', '\r', '#')):
        raise ValueError('This value needs manual review before writing Hyprland conf syntax.')
    return text

def conf_combo(value):
    parts = validate_combo(value).split(' + ')
    key = parts[-1]
    if key.startswith('CODE:'): key = 'code:' + key[5:]
    return ' '.join(parts[:-1]) + ', ' + key

def render_conf(state):
    lines = ['# Generated by CEDAR. Put personal overrides in user.conf.']
    if state.get('sessionStart', True):
        lines.append('exec-once = ' + conf_value(session_command()))
    for key, value in state.get('input', {}).items():
        lines.append('input:' + key + ' = ' + conf_value(value))
    if state.get('mainDisplay'):
        output = conf_value(state['mainDisplay'])
        lines.append('cursor:default_monitor = ' + output)
        lines.append('exec-once = ' + shlex.join(['xrandr', '--output', output, '--primary']))
    for m in state.get('monitors', []):
        values = [m['name'], m['mode'], str(m['x'])+'x'+str(m['y']), m['scale'], 'transform', m['transform']]
        if 'vrrPolicy' in m: values += ['vrr', m['vrrPolicy']]
        if m.get('mirror'): values += ['mirror', m['mirror']]
        lines.append('monitor = ' + ', '.join(conf_value(v) for v in values))
    if state.get('keybinds'):
        lines.append('source = ' + conf_value(str(OWN/'keybinds.conf')))
    for binding in state.get('bindings', []):
        for key in binding.get('originals', [binding['original']] if binding.get('original') else []):
            lines.append('unbind = ' + conf_combo(key))
        lines.append('unbind = ' + conf_combo(binding['keys']))
        description = conf_value(binding['description']).replace(',', ' ')
        lines.append('bindd = ' + conf_combo(binding['keys']) + ', ' + description + ', exec, ' + conf_value(binding['command']))
    return '\n'.join(lines) + '\n'

def render(state):
    return render_lua(state) if syntax() == 'lua' else render_conf(state)

def loader(directory=None):
    if syntax() == 'lua': return loader_lua(directory)
    directory = Path(directory) if directory is not None else OWN
    paths = [str(directory/name) for name in ('generated.conf', 'user.conf')]
    if any(any(c in value for c in ('$', '#', '\r', '\n')) for value in paths):
        raise ValueError('This path requires a manually reviewed Hyprland source entry.')
    return '\n' + marker() + '\n' + ''.join('source = ' + value + '\n' for value in paths)

def reload_validate():
    command(['hyprctl','reload'])
    errors = command(['hyprctl','configerrors']).strip()
    if errors not in ('', 'ok', '[]'): raise RuntimeError(errors)

def backup(paths):
    result = {}
    for p in paths:
        if p.exists():
            with p.open(newline='') as handle:  # newline='' keeps \r\n intact (read_text(newline=…) needs 3.13)
                result[str(p)] = handle.read()
        else: result[str(p)] = None
    return result

def restore(files, main_before_relocation=None):
    for name, text in files.items():
        path = Path(name)
        if path == MAIN:
            current = ""
            if path.exists():
                try:
                    with path.open(newline='') as handle:
                        current = handle.read()
                except OSError:
                    current = ""  # a MAIN that vanished mid-trial: the rollback must still complete
            if not path.exists() or not current:
                pass  # nothing on disk to reconcile; the other files and the reload below still run
            if text is not None and marker() not in text:
                # Pre-CEDAR backup: MAIN comes back exactly as it was. If it
                # vanished mid-trial it is recreated; if it exists, only our
                # appended loader is removed (either newline form), byte-
                # preserving everything around it.
                if not path.exists():
                    atomic(path, text)
                else:
                    without = current
                    for variant in _loader_variants():
                        without = without.replace(variant, "")
                    atomic(path, without)
            elif text is not None and marker() in text and isinstance(main_before_relocation, dict):
                # This install moved the loader inside the trial; Revert undoes
                # that specific move while keeping every unrelated user edit:
                # the edits between the post-relocation file and what is on
                # disk now are replayed onto the pre-relocation ordering.
                # Unmappable histories leave MAIN untouched and are reported.
                undone = _undo_loader_move(main_before_relocation, current)
                if undone is not None:
                    atomic(path, undone)
                else:
                    _rollback_warning('hyprland.lua was edited in a way that cannot be mapped back onto the pre-Apply ordering; MAIN left as the user wrote it.')
            # else: leave MAIN untouched — concurrent user edits outrank us
        elif text is None: path.unlink(missing_ok=True)
        else: atomic(path, text)

def _loader_variants():
    """Our loader block as written, and as it lands in a CRLF file."""
    block = loader()
    return (block, block.replace('\n', '\r\n'))


def _rollback_warning(message):
    """A rollback note the user can actually find: the watchdog's stderr is
    DEVNULL, so warnings land in the shell log directory too."""
    print('CEDAR display rollback: ' + message, file=sys.stderr)
    try:
        log = OWN / 'backups' / 'rollback-warnings.log'
        log.parent.mkdir(parents=True, exist_ok=True)
        with log.open('a') as handle:
            handle.write(time.strftime('%Y-%m-%d %H:%M:%S ') + message + '\n')
    except OSError:
        pass


def _undo_loader_move(meta, current):
    """Replay the edits between the post-relocation file and what is on disk
    now onto the pre-relocation ordering. pre and post differ by exactly one
    known line move (the loader block), so every post line maps to its pre
    line; user edits are non-equal regions and are kept as written. Returns
    the restored text, or None when the history cannot be mapped (the caller
    keeps the user's file)."""
    pre = meta['pre']
    start, n = meta['insertLine'], meta['blockLines']
    pre_lines = pre.splitlines(keepends=True)
    if start + n > len(pre_lines):
        return None
    block_lines = pre_lines[start:start + n]
    post_lines = pre_lines[:start] + pre_lines[start + n:] + block_lines
    where = {}
    for j in range(len(post_lines)):
        if j < len(pre_lines) - n:
            where[j] = j if j < start else j + n  # before the block: same; after it: shifted by the block
        else:
            where[j] = start + (j - (len(post_lines) - n))  # the moved block lines
    cur_lines = current.splitlines(keepends=True)
    import difflib
    kept = set()          # pre line indices the user did not touch
    edits = []            # (insert-before-this-pre-index, user line)
    for op, i1, i2, j1, j2 in difflib.SequenceMatcher(None, post_lines, cur_lines, autojunk=False).get_opcodes():
        if op == 'equal':
            for j in range(i1, i2):
                s = where.get(j)
                if s is None:
                    return None
                kept.add(s)
        else:
            # an edit at this point in the post ordering lands at the same
            # relative spot in the pre ordering (after the last kept line)
            prev = None
            for j in range(i1 - 1, -1, -1):
                prev = where.get(j)
                if prev is not None:
                    break
            key = (prev + 1) if prev is not None else 0
            for j in range(j1, j2):
                line = cur_lines[j]
                if not line.endswith('\n'):
                    # an unterminated user line cannot be placed safely: after
                    # the replay it could sit before retained content. Leave
                    # MAIN untouched instead of concatenating lines.
                    return None
                edits.append((key, line))
    if not kept:
        return None  # nothing of the pre-relocation file survived: unmappable history
    out = []
    edits_by_key = {}
    for key, line in edits:
        edits_by_key.setdefault(key, []).append(line)
    for s in range(len(pre_lines)):
        for line in edits_by_key.pop(s, []):
            out.append(line)
        if s in kept:
            out.append(pre_lines[s])
    for key in sorted(edits_by_key):  # edits past the end of the file
        for line in edits_by_key[key]:
            out.append(line)
    restored = ''.join(out)
    # belt and braces: no unterminated line may end up before retained content
    if any(not line.endswith('\n') for line in restored.splitlines(keepends=True)[:-1]):
        return None
    return restored


def ensure_loader_last():
    """CEDAR's loader must be the LAST thing MAIN runs. A later-loading block
    that pins monitor rules (a display manager's generated file, seen live with
    hyprmoncfg 2026-11-01) otherwise overrides every resolution, scale and
    refresh change CEDAR applies — the trial passes, the screen never moves.

    ONLY display transactions may call this: the move changes which monitor
    rules win, so it belongs to the guarded trial/rollback flow, never to an
    unrelated settings write. Returns {'pre', 'insertLine', 'blockLines'}
    describing the exact move so restore() can undo it, or None when nothing
    moved. A hand-edited block is refused rather than duplicated; a MAIN that
    changes while the move is prepared is refused too."""
    with MAIN.open(newline='') as handle:
        text = handle.read()
    if marker() not in text:
        return None  # first install: the append happens inside install()'s backed-up try block
    for variant in _loader_variants():
        if text.endswith(variant):
            return None
    variant = next((v for v in _loader_variants() if v in text), None)
    if variant is None:
        raise RuntimeError('The CEDAR loader block in ' + str(MAIN) + ' has been edited since CEDAR wrote it. CEDAR refuses to add a second one; remove or restore that block manually, then apply again.')
    idx0 = text.index(variant)
    start = text[:idx0].count('\n')
    n = variant.count('\n')
    pre_lines = text.splitlines(keepends=True)
    moved = ''.join(pre_lines[:start] + pre_lines[start + n:] + pre_lines[start:start + n])
    with MAIN.open(newline='') as handle:
        reread = handle.read()
    if reread != text:
        raise RuntimeError('hyprland.lua changed while the display layout was being prepared. Nothing was moved — apply again from the Displays page.')
    atomic(MAIN, moved)
    return {'pre': text, 'insertLine': start, 'blockLines': n}


def install(state, display=False, verify=None):
    if not MAIN.exists(): raise RuntimeError('Hyprland configuration was not found. No files were changed.')
    if not os.environ.get('CEDAR_HYPR_CONFIG') and all((CONFIG/'hypr'/name).exists() for name in ('hyprland.conf', 'hyprland.lua')):
        raise RuntimeError('Both Hyprland config formats exist; the running main config must be identified before applying settings.')
    from portable_providers import safe_target
    for target in [MAIN, generated(), OWN/'settings.json', OWN/('user.'+syntax())]: safe_target(target)
    pre_move = None
    before = backup([OWN/'settings.json', generated(), MAIN])
    # Keep a human-readable recovery copy for every applied change.
    journal = OWN/'backups'/str(time.time_ns())
    atomic(journal.with_suffix('.json'), json.dumps(before, indent=2))
    token = uuid.uuid4().hex
    pending = {'token':token, 'deadline':time.time()+20, 'files':before}
    try:
        # The loader relocation changes which monitor rules win, so it happens
        # ONLY inside a display transaction, guarded by the trial's rollback.
        if display:
            pre_move = ensure_loader_last()
            if pre_move is not None: pending['mainBeforeRelocation'] = pre_move
            atomic(OWN/'pending.json', json.dumps(pending))
            subprocess.Popen([sys.executable, str(Path(__file__).resolve()), '--watch', token], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        atomic(generated(), render(state))
        atomic(OWN/'settings.json', json.dumps(state, indent=2))
        user = OWN / ('user.' + syntax())
        if not user.exists(): atomic(user, ('--' if syntax() == 'lua' else '#') + ' Your overrides. CEDAR never rewrites this file.\n')
        text = MAIN.read_text()
        if marker() not in text: atomic(MAIN,text+loader())
        reload_validate()
        if verify: verify()
    except Exception:
        restore(before, main_before_relocation=pre_move); (OWN/'pending.json').unlink(missing_ok=True)
        with contextlib.suppress(Exception): reload_validate()
        raise
    return {'pending': {'token':token,'deadline':pending['deadline']} if display else None, 'mainBeforeRelocation': pre_move, 'message': 'Keep this display arrangement within 20 seconds.' if display else 'Applied and saved.'}

def verify_inputs(values):
    for key,wanted in values.items():
        data=json.loads(command(['hyprctl','-j','getoption','input:'+key]))
        kind=INPUTS[key][0]
        effective=data.get('str') if kind in ('str','enum') else data.get('float') if kind=='float' else data.get('int')
        matches=math.isclose(effective,wanted,abs_tol=1e-5) if kind=='float' and isinstance(effective,(int,float)) else effective==wanted
        if not matches: raise ValueError('A later override prevented '+key+' from applying. Your previous settings were restored; edit the user override first.')

def x11_outputs(text):
    connected, primary = [], ""
    for line in text.splitlines():
        match = re.match(r'^(\S+) connected(?: (primary))?(?: |$)', line)
        if match:
            connected.append(match[1])
            if match[2]: primary = match[1]
    return connected, primary


def apply_primary(state, output):
    live = hypr('monitors')
    if not isinstance(output, str) or not any(m['name'] == output and not m.get('disabled') for m in live):
        raise ValueError('The selected display is disconnected. Refresh the display list.')
    has_x11 = bool(os.environ.get('DISPLAY')) and bool(shutil.which('xrandr'))
    previous_x11 = ""
    if has_x11:
        connected, previous_x11 = x11_outputs(command(['xrandr', '--query']))
        if output not in connected:
            raise ValueError('This display is not available to X11 yet. No defaults were changed.')
    before = backup([OWN/'settings.json', generated(), MAIN])
    state['mainDisplay'] = output
    result = None
    try:
        result = install(state)
        effective = json.loads(command(['hyprctl', '-j', 'getoption', 'cursor:default_monitor'])).get('str')
        if effective != output:
            raise ValueError('A later user override controls the startup display. Update that override before applying.')
        if has_x11:
            command(['xrandr', '--output', output, '--primary'])
            if x11_outputs(command(['xrandr', '--query']))[1] != output:
                raise RuntimeError('X11 did not accept the selected main display.')
    except Exception:
        # install() may have relocated the loader before failing its caller's
        # checks; the rollback must undo that too, exactly like a trial revert.
        restore(before, main_before_relocation=(result or {}).get('mainBeforeRelocation'))
        with contextlib.suppress(Exception): reload_validate()
        if has_x11:
            with contextlib.suppress(Exception):
                command(['xrandr', '--output', previous_x11, '--primary'] if previous_x11 else ['xrandr', '--noprimary'])
        raise
    result['message'] = output + ' is saved as the startup display.' + (' X11 games also use it as their main display.' if has_x11 else ' X11 is unavailable in this session; its default will be applied on login when available.')
    return result


def display_manager():
    """An external monitor manager that re-applies its own layout (hyprmoncfgd:
    on hotplug, lid, suspend — and observed after config reloads, 2026-11-02)
    overrides every display change CEDAR tests. Detected honestly so the page
    can say so instead of letting a trial silently lose.

    The daemon is not the only threat: hyprmoncfg also wires a loader line into
    MAIN ("Added by hyprmoncfg") that dofile()s its generated monitor rules on
    every reload. When the daemon is off the file is dormant — but if the tool
    ever runs again it re-inserts that line after CEDAR's loader and takes the
    layout back. Detected here in three honest states:
      active  — the daemon is running right now: every trial loses.
      wired   — the loader line exists and loads BEFORE CEDAR's: CEDAR
                currently wins, but the fight resumes the moment the tool
                runs again.
      overriding — the loader line exists and loads AFTER CEDAR's (Lua runs
                top to bottom: last load wins): its stale rules win today;
                CEDAR's display page cannot apply anything.
    """
    managers = [('hyprmoncfgd', 'hyprmoncfg', 'It re-applies its saved profile on hotplug, lid close, suspend and after config reloads.')]
    for process, name, detail in managers:
        try:
            probe = subprocess.run(['pgrep', '-x', process], capture_output=True, text=True, check=False)
        except OSError:
            continue  # no process probe available; detection is best-effort and must not take down the snapshot
        if probe.returncode == 0:
            return {'name': name, 'active': True, 'dormant': False, 'detail': detail}
    # Dormant wiring: the actual loader line in MAIN and its rules file. MAIN
    # may not exist (no Hyprland config yet) — absence is reported, never
    # invented; an unreadable MAIN is reported too, never downgraded to a
    # clean all-clear. The match is the real dofile/io.open line, not any
    # comment mentioning the filename, and the LAST such line decides (Lua:
    # last load wins).
    try:
        text = MAIN.read_text()
    except OSError as error:
        return {'name': '', 'active': False, 'dormant': False,
                'detail': 'The Hyprland config (' + str(MAIN) + ') could not be read to check for dormant hyprmoncfg wiring: ' + str(error)}
    rules = (CONFIG / 'hypr' / 'hyprmoncfg-monitors.lua')
    loaders = [line for line in text.splitlines() if 'hyprmoncfg-monitors.lua' in line and ('dofile' in line or 'io.open' in line)]
    if not loaders or not rules.exists():
        return {'name': '', 'active': False, 'dormant': False, 'detail': ''}
    detail = ("hyprmoncfg's saved layout is still wired into your Hyprland config: "
              + str(rules) + ' loads on every reload. ')
    if marker() not in text:
        detail += ("CEDAR's settings are not wired into this Hyprland config at all, so hyprmoncfg's rules win — "
                   "every change tested on this page is overridden. Remove that block (or delete the rules file), or manage displays in hyprmoncfg.")
        return {'name': 'hyprmoncfg', 'active': False, 'dormant': True, 'detail': detail}
    overriding = text.rindex(loaders[-1]) > text.index(marker())
    if overriding:
        detail += ('Its rules load AFTER CEDAR\'s, so they win — every change tested on this page is overridden. '
                   'Remove that block from your Hyprland config (or delete the rules file), or manage displays in hyprmoncfg.')
    else:
        detail += ('CEDAR\'s rules currently load after it, so this page wins — but if hyprmoncfg runs again it '
                   're-inserts its loader last and takes the layout back. Remove it, or manage displays in hyprmoncfg.')
    return {'name': 'hyprmoncfg', 'active': False, 'dormant': True, 'detail': detail}


def snapshot():
    monitors = hypr('monitors')
    bindings = hypr('binds')
    inputs, errors = {}, {}
    for key in INPUTS:
        try:
            data = json.loads(command(['hyprctl','-j','getoption','input:'+key]))
            kind = INPUTS[key][0]
            value = data.get('str') if kind in ('str','enum') else data.get('float') if kind == 'float' else data.get('int')
            if value is not None: inputs[key] = bool(value) if kind == 'bool' else value
            else: errors[key] = 'Unavailable in this Hyprland version'
        except Exception as e: errors[key] = str(e)
    for b in bindings:
        b['keys'] = combo(b)
        b['editable'] = b.get('dispatcher') == 'exec' and not b.get('submap') and not any(b.get(k) for k in ('release','repeat','mouse','locked','longPress','non_consuming'))
        text = (b.get('description','')+' '+b.get('arg','')+' '+b.get('dispatcher','')).lower()
        b['category'] = next((cat for cat, words in [('CEDAR',['cedar']),('Media',['audio','volume','brightness','playerctl','media']),('Workspaces',['workspace']),('Screenshots',['capture','screenshot']),('System',['lock','power','suspend']),('Window management',['window','focus','move','resize','fullscreen'])] if any(w in text for w in words)), 'Applications')
    pending = json.loads((OWN/'pending.json').read_text()) if (OWN/'pending.json').exists() else None
    try: has_touchpad = 'E: ID_INPUT_TOUCHPAD=1' in command(['udevadm', 'info', '--export-db'])
    except Exception: has_touchpad = False
    try: windows, windows_errors = windows_live()
    except Exception as e: windows, windows_errors = {}, {'all': str(e)}
    return {'hasTouchpad':has_touchpad, 'monitors':monitors, 'bindings':bindings, 'input':inputs, 'unsupported':errors, 'windows':windows, 'windowsUnsupported':windows_errors, 'owned':read_state(), 'displayManager':display_manager(), 'pending': {'token':pending['token'],'deadline':pending['deadline']} if pending else None}

@contextlib.contextmanager
def locked():
    OWN.mkdir(parents=True, exist_ok=True)
    with (OWN/'.lock').open('w') as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        yield

def restore_pending(token):
    file = OWN/'pending.json'
    if not file.exists(): return
    pending = json.loads(file.read_text())
    if pending['token'] != token: return
    restore(pending['files'], main_before_relocation=pending.get('mainBeforeRelocation')); file.unlink()
    reload_validate()

def watch(token):
    # Survives the shell closing/reloading. A new token can never roll back another transaction.
    for _ in range(45):
        with locked():
            file = OWN/'pending.json'
            if not file.exists(): return
            pending = json.loads(file.read_text())
            if pending['token'] != token: return
            if time.time() >= pending['deadline']:
                restore_pending(token); return
        time.sleep(1)

def action(req):
    name = req.get('action','snapshot')
    if name == 'snapshot': return snapshot()
    with locked():
        if name in ('keep','revert'):
            pending_file = OWN/'pending.json'
            if not pending_file.exists(): raise ValueError('The display trial has already ended.')
            p = json.loads(pending_file.read_text())
            if req.get('token') != p['token']: raise ValueError('This display trial is no longer current.')
            if name == 'revert' or time.time() >= p['deadline']: restore_pending(p['token'])
            else: pending_file.unlink()
            return {'message':'Display trial finished.', 'pending':None}
        if (OWN/'pending.json').exists(): raise ValueError('Keep or revert the current display trial first.')
        state = read_state()
        if name == 'primary': return apply_primary(state, req.get('output'))
        if name == 'input':
            values=validate_inputs(req['values'])
            live=snapshot()['input']
            if 'expected' in req:
                changed=[key for key in values if live.get(key)!=req['expected'].get(key)]
                if changed: raise ValueError('Input changed outside Settings: '+', '.join(changed)+'. Reload before applying.')
            values={key:value for key,value in values.items() if live.get(key)!=value}
            if not values:return {'status':'unchanged','message':'Input settings are already applied.'}
            state.setdefault('input',{}).update(values)
        elif name == 'reset-input': state['input']={}
        elif name == 'apply-windows':
            values = validate_windows(req['values'])
            live, _ = windows_live()
            if 'expected' in req:
                changed = [key for key in values if live.get(key) != req['expected'].get(key)]
                if changed: raise ValueError('Window settings changed outside Settings: '+', '.join(changed)+'. Reload before applying.')
            values = {key: value for key, value in values.items() if live.get(key) != value}
            if not values: return {'status':'unchanged','message':'Window settings are already applied.'}
            state.setdefault('windows', {}).update(values)
            result = install(state, verify=lambda: verify_windows(values))
            return {'message': 'Applied '+str(len(values))+' window setting' + ('s' if len(values) != 1 else '') + '.', 'pending': None}
        elif name == 'reset-windows':
            state['windows'] = {}
            result = install(state)
            return {'message': 'Window settings reset; your compositor configuration is authoritative again.', 'pending': None}
        elif name == 'save-profile':
            write_state(save_profile(state, req.get('name',''), req.get('monitors',[]), req.get('mainDisplay','')))
            return {'message': 'Saved layout “'+str(req.get('name','')).strip()+'”. Load it any time to test it again.'}
        elif name == 'delete-profile':
            profiles = state.get('displayProfiles', [])
            if not any(p['name'] == req.get('name') for p in profiles): raise ValueError('That saved layout no longer exists.')
            state['displayProfiles'] = [p for p in profiles if p['name'] != req.get('name')]
            write_state(state)
            return {'message': 'Deleted the saved layout.'}
        elif name == 'displays':
            live=hypr('monitors')
            if 'expected' in req:
                keys=('name','width','height','refreshRate','x','y','scale','transform','disabled','mirrorOf')
                signature=lambda rows: sorted([tuple(str(m.get(k,'')) for k in keys) for m in rows])
                if signature(live)!=signature(req['expected']): raise ValueError('Displays changed outside Settings. Reload the arrangement before applying.')
            state['monitors'] = validate_monitors(req['monitors'],live)
        elif name == 'binding':
            keys = validate_combo(req['keys'])
            original = req.get('original','')
            current = snapshot()['bindings']
            originals=[b for b in current if b['keys']==original and not b.get('submap')]
            if original and (len(originals)!=1 or not originals[0]['editable'] or originals[0].get('arg')!=req.get('previousCommand')):
                raise ValueError('The original shortcut changed or cannot be safely edited. Refresh it.')
            conflicts = [b for b in current if not b.get('submap') and b['keys'].upper() == keys and b['keys'] != original]
            if conflicts:
                expected=req.get('replace',[])
                signature=lambda rows: sorted((b['keys'],b.get('arg',''),b.get('dispatcher','')) for b in rows)
                if not expected or signature(conflicts)!=signature(expected) or any(not b.get('editable') for b in conflicts):
                    raise ValueError('Shortcut already assigned or changed: '+', '.join(b.get('description') or b.get('dispatcher','action') for b in conflicts))
            elif req.get('replace'): raise ValueError('The conflicting shortcut changed. Review the new bindings before replacing.')
            cmd, desc = str(req['command']).strip(), str(req.get('description','Custom shortcut')).strip()
            if not cmd or '\x00' in cmd: raise ValueError('Enter a command.')
            previous = next((b for b in state['bindings'] if b['keys'] == original), None)
            ancestors=[]
            for b in state['bindings']:
                if b['keys'] in (keys,original): ancestors.extend(b.get('originals',[b['original']] if b.get('original') else []))
            if original and not previous: ancestors.append(original)
            state['bindings'] = [b for b in state['bindings'] if b['keys'] not in (keys,original)]
            state['bindings'].append({'keys':keys,'command':cmd,'description':desc, 'original':previous.get('original','') if previous else original, 'originals':list(dict.fromkeys(ancestors))})
        elif name == 'remove-binding':
            state['bindings'] = [b for b in state['bindings'] if b['keys'] != req['keys']]
        else: raise ValueError('Unknown desktop settings action.')
        if name=='input': return install(state,verify=lambda:verify_inputs(values))
        return install(state, name == 'displays')

def main():
    if len(sys.argv) == 3 and sys.argv[1] == '--watch': watch(sys.argv[2]); return
    try:
        req = json.loads(sys.stdin.readline()); print(json.dumps({'ok':True,'data':action(req)}))
    except Exception as e: print(json.dumps({'ok':False,'error':str(e)}))

if __name__ == '__main__': main()
