#!/usr/bin/env python3
"""Capability-aware power and night-light controls."""
import json
import re
import subprocess
import sys
from desktop_runtime import omarchy

def run(args):
    result=subprocess.run(args,capture_output=True,text=True,timeout=12)
    if result.returncode: raise RuntimeError(result.stderr.strip() or result.stdout.strip() or 'Command failed')
    return result.stdout.strip()

# power-profiles-daemon and Fedora's tuned-ppd serve the same net.hadess.PowerProfiles
# D-Bus interface; only the former ships powerprofilesctl. Fedora 41+ installs tuned-ppd
# by default (no powerprofilesctl), so the same readings and the same set go over D-Bus.
PPD=['busctl','--system','--','net.hadess.PowerProfiles','/net/hadess/PowerProfiles','net.hadess.PowerProfiles']
PROFILES=('power-saver','balanced','performance')

def have_ctl():
    import shutil
    return bool(shutil.which('powerprofilesctl'))

def profiles_dbus():
    listing=run(['busctl','--system','get-property',*PPD[3:],'Profiles'])
    found=re.findall(r'"Profile"\s+s\s+"([^"]+)"',listing)
    return [p for p in found if p in PROFILES]

def profile_dbus():
    return run(['busctl','--system','get-property',*PPD[3:],'ActiveProfile']).split('"')[1]

def set_profile(value):
    if have_ctl(): run(['powerprofilesctl','set',value])
    else: run(['busctl','--system','set-property',*PPD[3:],'ActiveProfile','s',value])

def snapshot():
    data={'profiles':[], 'profile':'', 'nightlight':None, 'errors':{}}
    try:
        if have_ctl():
            data['profiles']=re.findall(r'^\s*\*?\s*(power-saver|balanced|performance):',run(['powerprofilesctl','list']),re.M)
            data['profile']=run(['powerprofilesctl','get'])
        else:
            data['profiles']=profiles_dbus()
            data['profile']=profile_dbus()
    except Exception as e: data['errors']['power']=str(e)
    try:
        if omarchy(): data['nightlight']=json.loads(run(['omarchy-toggle-nightlight','--status']))['enabled']
        else: data['nightlight']=int(run(['hyprctl','hyprsunset','temperature'])) < 6500
    except Exception as e: data['errors']['nightlight']=str(e)
    return data

def main():
    try:
        req=json.loads(sys.stdin.readline())
        if req.get('action')=='profile':
            if req['value'] not in snapshot()['profiles']: raise ValueError('This power profile is unavailable.')
            set_profile(req['value'])
        elif req.get('action')=='nightlight':
            if omarchy(): run(['omarchy','toggle','nightlight'])
            else:
                state=snapshot()['nightlight']
                if state is None: raise RuntimeError('Hyprsunset is not running. Start your configured night-light provider first.')
                run(['hyprctl','hyprsunset','temperature', '6500' if state else '4500'])
        elif req.get('action','snapshot')!='snapshot': raise ValueError('Unknown control action')
        print(json.dumps({'ok':True,'data':snapshot()}))
    except Exception as e: print(json.dumps({'ok':False,'error':str(e)}))
if __name__=='__main__': main()
