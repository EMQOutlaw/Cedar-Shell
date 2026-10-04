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

def snapshot():
    data={'profiles':[], 'profile':'', 'nightlight':None, 'errors':{}}
    try:
        data['profiles']=re.findall(r'^\s*\*?\s*(power-saver|balanced|performance):',run(['powerprofilesctl','list']),re.M)
        data['profile']=run(['powerprofilesctl','get'])
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
            run(['powerprofilesctl','set',req['value']])
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
