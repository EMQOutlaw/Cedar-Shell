#!/usr/bin/env python3
"""Read-only settings inventory, plus explicit whitelisted desktop actions."""
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import platform
import subprocess
import sys
import desktop_runtime as runtime

ROOT=Path(__file__).resolve().parents[1]
HOME=Path.home()
CONFIG=Path(os.environ.get('XDG_CONFIG_HOME',HOME/'.config'))
SERVICES=[('PipeWire','pipewire.service',True),('WirePlumber','wireplumber.service',True),
 ('NetworkManager','NetworkManager.service',False),('Bluetooth','bluetooth.service',False),
 ('Desktop portal','xdg-desktop-portal.service',True),('Hyprland portal','xdg-desktop-portal-hyprland.service',True)]

def run(args):
    p=subprocess.run(args,text=True,capture_output=True,timeout=8)
    if p.returncode: raise RuntimeError(p.stderr.strip() or p.stdout.strip() or 'Command failed')
    return p.stdout.strip()

def probe(args):
    try: return run(args)
    except Exception as e: return 'Unavailable: '+str(e)

def service(row):
    label,unit,user=row
    try:
        text=run(['systemctl']+(['--user'] if user else [])+['show',unit,'--property=LoadState,ActiveState,SubState,Result'])
        p=dict(line.split('=',1) for line in text.splitlines() if '=' in line)
        status='Unavailable' if p.get('LoadState')!='loaded' else 'Healthy' if p.get('ActiveState')=='active' else 'Failed' if p.get('ActiveState')=='failed' else 'Warning'
        detail=' · '.join(p.get(k,'unknown') for k in ['ActiveState','SubState','Result'])
    except Exception as e: status,detail='Unavailable',str(e)
    return {'name':label,'unit':unit,'user':user,'status':status,'detail':detail}

def inventory():
    walls = runtime.wallpapers()
    try: selected = json.loads((runtime.config()/'theme.json').read_text()).get('name', 'cedar')
    except (OSError, ValueError): selected = 'cedar'
    return {'theme': 'CEDAR' if selected == 'cedar' else selected,
            'wallpaper': walls['selected'], 'wallpaperFolder': walls['folder'], 'themes': runtime.themes(), 'wallpapers': walls['items']}

def snapshot():
    commands={'quickshell':['qs','--version'],'hyprland':['hyprctl','version'], 'qt':['/usr/lib/qt6/bin/qtpaths','--qt-version']}
    with ThreadPoolExecutor(max_workers=6) as pool:
        futures={key:pool.submit(probe,args) for key,args in commands.items()}
        health=list(pool.map(service,SERVICES))
        versions={k:(f.result().splitlines()[0] if f.result() and not f.result().startswith('Unavailable') else 'Unavailable') for k,f in futures.items()}
    return {**inventory(),'hostname':platform.node(),'kernel':platform.release(),'os':platform.freedesktop_os_release().get('PRETTY_NAME',platform.system()),
      'version':(ROOT/'VERSION').read_text().strip() if (ROOT/'VERSION').exists() else 'Unavailable', 'versions':versions,'services':health,'installationMethod':'Local source registration' if (CONFIG/'quickshell/cedar').is_symlink() else 'Unavailable'}

def action(req):
    name=req.get('action','snapshot')
    if name=='snapshot': return snapshot()
    if name in ('restart','logs'):
        row=next((r for r in SERVICES if r[1]==req.get('unit')),None)
        if row is None: raise ValueError('Unsupported service')
        _,unit,user=row
        if name=='restart':
            run((['systemctl','--user'] if user else ['pkexec','systemctl'])+['restart',unit])
            return {'message':row[0]+' restarted.'}
        from redaction import redact
        return {'logs':redact(probe(['journalctl']+(['--user'] if user else [])+['-u',unit,'-n','60','--no-pager']))}
    if name=='wallpaper':
        chosen=Path(req['path']).resolve()
        if str(chosen) not in [w['path'] for w in inventory()['wallpapers']]: raise ValueError('Wallpaper is no longer available.')
        runtime.set_wallpaper(str(chosen)); return inventory()
    if name=='theme':
        if req['name'] not in [t['name'] for t in inventory()['themes']]: raise ValueError('Theme is no longer installed.')
        runtime.set_theme(req['name']); return inventory()
    raise ValueError('Unknown settings action')

if __name__=='__main__':
    try: print(json.dumps({'ok':True,'data':action(json.loads(sys.stdin.readline()))}))
    except Exception as e: print(json.dumps({'ok':False,'error':str(e)}))
