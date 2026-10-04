#!/usr/bin/env python3
"""Legacy Omarchy registration helpers, retained for migration/recovery tests.

These helpers are retained solely for legacy migration/recovery. Normal
installation uses scripts/install.py and scripts/setup.py.
"""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
from migrate import locations, migrate, private, write_json
ROOT=Path(__file__).resolve().parents[1]

def check_system():
    if os.getuid()==0: raise RuntimeError('Run ./install.sh as your regular desktop user, not root.')
    release={}
    for line in Path('/etc/os-release').read_text().splitlines():
        if '=' in line:
            key,value=line.split('=',1);release[key]=value.strip('"')
    if release.get('ID') not in ('arch','omarchy') or not shutil.which('omarchy'):
        raise RuntimeError('Automatic installation currently supports Arch Linux with Omarchy and Hyprland. No files were changed.')

def dependencies():
    manifest=json.loads((ROOT/'data/dependencies.json').read_text())
    missing=[r for r in manifest['commands'] if not shutil.which(r['command'])]
    required=[r for r in missing if r['status']=='required']
    if importlib.util.find_spec('gi') is None: raise RuntimeError('Missing Python GObject bindings (Arch package python-gobject).')
    native=subprocess.run([sys.executable,'-c',"import gi; gi.require_version('NM','1.0'); from gi.repository import NM, Gio"],capture_output=True,text=True)
    if native.returncode:raise RuntimeError('Missing GObject integration (Arch packages python-gobject and libnm).')
    if not Path('/etc/pam.d/omarchy-lock-password').is_file(): raise RuntimeError('The supported Omarchy PAM service is missing; installation stopped.')
    if required: raise RuntimeError('Required software is missing: '+', '.join(r['command']+' ('+r['archPackage']+')' for r in required)+'. Install these packages, then rerun ./install.sh.')
    return missing

def links():
    paths=locations(); config=paths['config']
    return {config/'quickshell/cedar':ROOT, config/'omarchy/themes/cedar':ROOT/'themes', Path.home()/'.local/bin/cedar':ROOT/'scripts/cedar'}

def preflight():
    for path,target in links().items():
        if (path.exists() or path.is_symlink()) and not (path.is_symlink() and path.resolve()==target):
            raise RuntimeError('An unrelated entry occupies a CEDAR installation location. Nothing will be overwritten: '+str(path))
    existing=shutil.which('cedar')
    if existing and Path(existing).resolve()!=ROOT/'scripts/cedar': raise RuntimeError('The command cedar already belongs to another installation.')
    if (locations()['config']/'quickshell/shell.qml').exists(): raise RuntimeError('A default Quickshell configuration masks named configurations. Installation stopped without replacing it.')
    for name in ('cedar-shell.service','cedar-theme-guard.service','cedar-theme-guard.path'):
        for base in (Path('/usr/lib/systemd/user'),Path('/etc/systemd/user')):
            if (base/name).exists():raise RuntimeError('A system-provided user service conflicts with CEDAR: '+name)
        path=locations()['config']/'systemd/user'/name
        if path.exists() and 'CEDAR' not in path.read_text(): raise RuntimeError('A conflicting user service already exists: '+name)

def validate():
    # Exercise the actual components with isolated XDG paths, no live lock or compositor.
    result=subprocess.run([sys.executable,str(ROOT/'tests/check_desktop_ui.py')],capture_output=True,text=True,timeout=60)
    if result.returncode: raise RuntimeError('QML validation failed:\n'+result.stdout+result.stderr)
    return 'Settings, Field Station and controls rendered with isolated fixtures.'

def register():
    created=[]
    try:
        for path,target in links().items():
            path.parent.mkdir(parents=True,exist_ok=True)
            if path.is_symlink() and path.resolve()==target: continue
            path.symlink_to(target);created.append(path)
        state=private(locations()['state']/'cedar')
        record=state/'installation.json'
        old=json.loads(record.read_text()) if record.exists() else {}
        write_json(record,{'format':1,'source':str(ROOT),'method':'Local source registration','activation':old.get('activation','pending')})
    except Exception:
        for path in reversed(created): path.unlink()
        raise

def uninstall():
    # Source, settings, backups and legacy installation deliberately remain.
    from cedar_cli import instances
    if instances('cedar'): raise RuntimeError('Stop CEDAR from an unlocked session before unregistering it.')
    config=locations()['config'];state=locations()['state']
    current=state/'omarchy/current/theme.name'
    if current.exists() and current.read_text().strip()=='cedar': raise RuntimeError('Select another theme before uninstalling CEDAR.')
    from cedar_cli import unlocked
    unlocked()
    subprocess.run(['systemctl','--user','disable','--now','cedar-theme-guard.path'],capture_output=True)
    for group in ('theme-set.d','post-boot.d'):
        path=config/'omarchy/hooks'/group/'90-cedar'
        if path.is_symlink() and path.resolve()==ROOT/'scripts/theme-hook':path.unlink()
    for name in ('cedar-theme-guard.path','cedar-theme-guard.service'):
        path=config/'systemd/user'/name
        if path.exists() and 'CEDAR' in path.read_text():path.unlink()
    for path,target in links().items():
        if path.is_symlink() and path.resolve()==target: path.unlink()
    subprocess.run(['systemctl','--user','daemon-reload'],capture_output=True)
    print('CEDAR registration removed. Source, preferences and recovery archives were preserved.')

def main():
    parser=argparse.ArgumentParser(description='Install CEDAR safely without replacing your running desktop.')
    parser.add_argument('--yes',action='store_true',help='Accept the displayed plan for unattended installation')
    parser.add_argument('--activate',action='store_true',help='Request guarded activation after validation')
    parser.add_argument('--uninstall',action='store_true')
    args=parser.parse_args()
    if args.uninstall: uninstall();return
    print('[1/6] Checking your system',flush=True);check_system();preflight()
    print('[2/6] Checking required software',flush=True);missing=dependencies()
    print('Plan: validate CEDAR, privately back up existing data, migrate missing preferences, and register its command and theme. The original installation stays recoverable.')
    if missing:print('Optional integrations unavailable: '+', '.join(r['command'] for r in missing))
    if not args.yes and input('Install CEDAR? [y/N] ').strip().lower() not in ('y','yes'):return
    validation=validate() # No user data touched unless the replacement loads.
    print('[3/6] Backing up existing settings',flush=True);result=migrate()
    print('[4/6] Installing CEDAR',flush=True);register()
    print('[5/6] Preparing desktop integration',flush=True)
    print('Theme and command registered. Startup handoff is guarded by cedar activate.')
    print('[6/6] Checking the installation',flush=True)
    for path,target in links().items():
        if not path.is_symlink() or path.resolve()!=target:raise RuntimeError('Registration verification failed.')
    print('Files installed: yes\nConfiguration validated: yes — '+validation+'\nDesktop launch tested: no\nActivation still required: cedar activate')
    print('Recovery journal: '+result['backup']+'/journal.json')
    print('Existing CEDAR conflicts preserved: '+str(len(result['preservedConflicts'])))
    if args.activate:
        subprocess.run([sys.executable,str(ROOT/'scripts/cedar_cli.py'),'activate'],check=True)
