#!/usr/bin/env python3
"""Real PulseAudio-compatible PipeWire routing; no DSP is simulated."""
import json, os, shutil, subprocess, sys
from pathlib import Path

def run(*args):
    p=subprocess.run(['pactl',*args],capture_output=True,text=True,timeout=4)
    if p.returncode: raise RuntimeError(p.stderr.strip() or 'Audio server rejected the request')
    return p.stdout.strip()

def scene_path():
    return Path(os.environ.get('XDG_CONFIG_HOME',str(Path.home()/'.config')))/'cedar/audio-scenes.json'

def scenes():
    try: return json.loads(scene_path().read_text())[:8]
    except (OSError,ValueError): return []

def save(rows):
    p=scene_path();p.parent.mkdir(parents=True,exist_ok=True)
    tmp=p.with_suffix('.tmp');fd=os.open(tmp,os.O_WRONLY|os.O_CREAT|os.O_TRUNC,0o600)
    with os.fdopen(fd,'w') as f: json.dump(rows,f)
    os.replace(tmp,p)

def volume(row):
    values=[v['value']/65536 for v in row.get('volume',{}).values()]
    return sum(values)/len(values) if values else 0

def snapshot():
    outputs=json.loads(run('-f','json','list','sinks'))
    inputs=json.loads(run('-f','json','list','sources'))
    streams=json.loads(run('-f','json','list','sink-inputs'))
    default=run('get-default-sink'); mic=run('get-default-source')
    return dict(outputs=[dict(id=s['index'],name=s['name'],label=s['description'],volume=volume(s),muted=s['mute']) for s in outputs],
        inputs=[dict(name=s['name'],label=s['description'],volume=volume(s),muted=s['mute']) for s in inputs if not s['name'].endswith('.monitor')],
        streams=[dict(id=s['index'],serial=str(s.get('properties',{}).get('object.serial','')),output=s['sink'],
            app=s.get('properties',{}).get('application.id') or s.get('properties',{}).get('application.name') or '',
            label=s.get('properties',{}).get('application.name') or s.get('properties',{}).get('media.name') or 'Audio stream',
            volume=volume(s)) for s in streams],default=default,microphone=mic,scenes=scenes(),
        eq=dict(available=False,bands=[],filters=[],reason='No supported EQ control backend is connected. Audio processing is unavailable; no equalizer is applied.'),
        processorInstalled=bool(shutil.which('easyeffects')),spectrumAvailable=bool(shutil.which('cava')))

def bounded(value):
    value=float(value)
    if not 0<=value<=1.5: raise ValueError('Invalid volume')
    return str(round(value*100))+'%'

def handle(req):
    action=req.get('action','snapshot'); data=snapshot()
    if action=='snapshot': return data
    if action=='route':
        stream=next((s for s in data['streams'] if s['id']==req.get('stream') and s['serial']==str(req.get('serial',''))),None)
        output=next((s for s in data['outputs'] if s['name']==req.get('output')),None)
        if not stream or not output: raise ValueError('Stream or output changed; refresh and try again.')
        run('move-sink-input',str(stream['id']),output['name'])
    elif action=='save-scene':
        name=str(req.get('name','')).strip()[:48]
        if not name: raise ValueError('Give the scene a name')
        out=next((s for s in data['outputs'] if s['name']==data['default']),None)
        mic=next((s for s in data['inputs'] if s['name']==data['microphone']),None)
        if not out: raise ValueError('No output is available to save')
        streams=[];seen=set()
        for stream in data['streams']:
            if not stream['app'] or stream['app'] in seen: continue
            seen.add(stream['app'])
            streams.append({**stream,'output':next((o['name'] for o in data['outputs'] if o['id']==stream['output']),'')})
        rows=[s for s in data['scenes'] if s['name']!=name]
        if len(rows)>=8: raise ValueError('Eight scenes saved. Delete one before adding another.')
        save([dict(name=name,output=out,microphone=mic,streams=streams)]+rows)
    elif action=='delete-scene': save([s for s in data['scenes'] if s['name']!=req.get('name')])
    elif action=='apply-scene':
        scene=next((s for s in data['scenes'] if s['name']==req.get('name')),None)
        if not scene: raise ValueError('Scene no longer exists')
        output=scene['output'];mic=scene.get('microphone'); names={s['name'] for s in data['outputs']}
        if output['name'] not in names or (mic and mic['name'] not in {s['name'] for s in data['inputs']}):
            raise ValueError('A saved device is disconnected. Nothing was changed.')
        matches=[(s,saved) for s in data['streams'] for saved in scene.get('streams',[]) if s['app'] and s['app']==saved['app']][:64]
        if any(saved['output'] not in names for _,saved in matches): raise ValueError('A saved application output is disconnected. Nothing was changed.')
        # Validate all gain values before changing the server.
        bounded(output['volume'])
        if mic: bounded(mic['volume'])
        for _,saved in matches: bounded(saved['volume'])
        run('set-default-sink',output['name']);run('set-sink-volume',output['name'],bounded(output['volume']));run('set-sink-mute',output['name'],str(int(output['muted'])))
        if mic:
            run('set-default-source',mic['name']);run('set-source-volume',mic['name'],bounded(mic['volume']));run('set-source-mute',mic['name'],str(int(mic['muted'])))
        for stream,saved in matches:
            run('move-sink-input',str(stream['id']),saved['output']);run('set-sink-input-volume',str(stream['id']),bounded(saved['volume']))
    else: raise ValueError('Unsupported audio action')
    return snapshot()

if __name__=='__main__':
    try: print(json.dumps(dict(ok=True,data=handle(json.loads(sys.stdin.readline())))))
    except Exception as e: print(json.dumps(dict(ok=False,error=str(e))))
