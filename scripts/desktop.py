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
        result.append({**vrr,'name': m['name'], 'mode': mode.removesuffix('Hz'), 'x': x, 'y': y, 'scale': scale, 'transform': rotation})
    return result

def render_lua(state):
    lines = ['-- Generated by CEDAR. Put personal overrides in user.lua.']
    inputs = {}
    for key, value in state.get('input',{}).items():
        if ':' in key:
            group, leaf = key.split(':',1); inputs.setdefault(group,{})[leaf] = value
        else: inputs[key] = value
    if inputs: lines.append('hl.config('+lua({'input': inputs})+')')
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
        lines.append('hl.monitor('+lua(monitor)+')')
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
    for key, value in state.get('input', {}).items():
        lines.append('input:' + key + ' = ' + conf_value(value))
    if state.get('mainDisplay'):
        output = conf_value(state['mainDisplay'])
        lines.append('cursor:default_monitor = ' + output)
        lines.append('exec-once = ' + shlex.join(['xrandr', '--output', output, '--primary']))
    for m in state.get('monitors', []):
        values = [m['name'], m['mode'], str(m['x'])+'x'+str(m['y']), m['scale'], 'transform', m['transform']]
        if 'vrrPolicy' in m: values += ['vrr', m['vrrPolicy']]
        lines.append('monitor = ' + ', '.join(conf_value(v) for v in values))
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

def backup(paths): return {str(p): p.read_text() if p.exists() else None for p in paths}

def restore(files):
    for name, text in files.items():
        path = Path(name)
        if path == MAIN:
            # We only append our loader. Preserve concurrent user edits on rollback.
            current = path.read_text() if path.exists() else ""
            if text is not None and marker() not in text:
                atomic(path, current.replace(loader(), ""))
        elif text is None: path.unlink(missing_ok=True)
        else: atomic(path, text)

def install(state, display=False, verify=None):
    if not MAIN.exists(): raise RuntimeError('Hyprland configuration was not found. No files were changed.')
    if not os.environ.get('CEDAR_HYPR_CONFIG') and all((CONFIG/'hypr'/name).exists() for name in ('hyprland.conf', 'hyprland.lua')):
        raise RuntimeError('Both Hyprland config formats exist; the running main config must be identified before applying settings.')
    from portable_providers import safe_target
    for target in [MAIN, generated(), OWN/'settings.json', OWN/('user.'+syntax())]: safe_target(target)
    before = backup([OWN/'settings.json', generated(), MAIN])
    # Keep a human-readable recovery copy for every applied change.
    journal = OWN/'backups'/str(time.time_ns())
    atomic(journal.with_suffix('.json'), json.dumps(before, indent=2))
    token = uuid.uuid4().hex
    pending = {'token':token, 'deadline':time.time()+20, 'files':before}
    try:
        if display:
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
        restore(before); (OWN/'pending.json').unlink(missing_ok=True)
        with contextlib.suppress(Exception): reload_validate()
        raise
    return {'pending': {'token':token,'deadline':pending['deadline']} if display else None, 'message': 'Keep this display arrangement within 20 seconds.' if display else 'Applied and saved.'}

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
        restore(before)
        with contextlib.suppress(Exception): reload_validate()
        if has_x11:
            with contextlib.suppress(Exception):
                command(['xrandr', '--output', previous_x11, '--primary'] if previous_x11 else ['xrandr', '--noprimary'])
        raise
    result['message'] = output + ' is saved as the startup display.' + (' X11 games also use it as their main display.' if has_x11 else ' X11 is unavailable in this session; its default will be applied on login when available.')
    return result


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
    return {'hasTouchpad':has_touchpad, 'monitors':monitors, 'bindings':bindings, 'input':inputs, 'unsupported':errors, 'owned':read_state(), 'pending': {'token':pending['token'],'deadline':pending['deadline']} if pending else None}

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
    restore(pending['files']); file.unlink()
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
        elif name == 'displays':
            live=hypr('monitors')
            if 'expected' in req:
                keys=('name','width','height','refreshRate','x','y','scale','transform','disabled')
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
