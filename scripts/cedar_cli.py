#!/usr/bin/env python3
"""CEDAR command, guarded activation, and non-destructive recovery."""
import argparse
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
from migrate import locations, private, write_json, recover, fingerprint
ROOT=Path(__file__).resolve().parents[1]

def run(args,check=True,timeout=20):
    p=subprocess.run(args,text=True,capture_output=True,timeout=timeout)
    if check and p.returncode:raise RuntimeError(p.stderr.strip() or p.stdout.strip() or 'Command failed: '+args[0])
    return p

def instances(name):
    result=run(['qs','list','-j','-c',name],False)
    if result.returncode:
        if not (locations()['config']/'quickshell'/name/'shell.qml').exists():return []
        raise RuntimeError('Could not inspect the named shell: '+name)
    # Quickshell 0.3.1 prints a plain sentence, even with -j, for no instances.
    if result.stdout.startswith('No running instances for '):return []
    value=json.loads(result.stdout)
    if not isinstance(value,list):raise RuntimeError('Unexpected shell inventory response.')
    return value

def unlocked():
    result=run(['omarchy-hyprland-session-locked'],False)
    if result.returncode!=1:raise RuntimeError('Activation deferred: the session is locked or its lock state cannot be verified. Run cedar activate from the unlocked desktop.')
    for name in ('foxfire','cedar'):
        if instances(name):
            result=run(['qs','-c',name,'ipc','call','shell','isLocked'],False)
            if result.returncode or result.stdout.strip()!='false':raise RuntimeError('Activation deferred: the running shell cannot confirm that it is unlocked.')

def wait_for(name,wanted):
    end=time.monotonic()+12
    while time.monotonic()<end:
        if bool(instances(name))==wanted:return
        time.sleep(.2)
    raise RuntimeError('Desktop handoff did not complete: '+name)

def activate():
    unlocked()  # Before ANY filesystem or startup changes.
    paths=locations();home=Path.home();config=paths['config'];state=paths['state']
    # The packaged Omarchy theme command ignores XDG overrides. Do not silently
    # apply a theme to the wrong configuration tree.
    if config!=home/'.config' or state!=home/'.local/state':
        raise RuntimeError('This Omarchy theme command uses default home paths. CEDAR data supports XDG overrides, but automatic Omarchy activation with these overrides is not supported yet.')
    from install import preflight,validate
    preflight();validate()
    if not (config/'quickshell/cedar').exists():raise RuntimeError('Run ./install.sh before activation.')
    runtime=Path(os.environ.get('XDG_RUNTIME_DIR','/run/user/'+str(os.getuid())))
    with (runtime/'cedar-activation.lock').open('a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX);unlocked()
        current=state/'omarchy/current/theme.name'
        previous=current.read_text().strip() if current.exists() else ''
        if previous=='cedar' and instances('cedar'):
            print('CEDAR is already active.');return
        # Refuse unknown legacy integrations rather than overwriting user scripts.
        oldconfig=config/'quickshell/foxfire'
        oldroot=oldconfig.resolve() if oldconfig.exists() else None
        edits=[]
        for group in ('theme-set.d','post-boot.d'):
            old=config/'omarchy/hooks'/group/'90-foxfire'
            new=config/'omarchy/hooks'/group/'90-cedar'
            if old.exists() and (not old.is_symlink() or oldroot is None or old.resolve()!=oldroot/'scripts/theme-hook'):
                raise RuntimeError('A custom legacy theme hook needs manual review; no startup changes made.')
            if new.exists() and (not new.is_symlink() or new.resolve()!=ROOT/'scripts/theme-hook'):
                raise RuntimeError('A custom CEDAR theme hook needs manual review.')
            edits.extend([old,new])
        main=config/'hypr/hyprland.lua'
        units=config/'systemd/user'
        for name in ('cedar-theme-guard.path','cedar-theme-guard.service'):
            edits.append(units/name)
        archive=private(state/'cedar/activation-backups'/str(time.time_ns()))
        snapshots=[]
        for i,path in enumerate(edits+[main]):
            kind='absent';backup=archive/str(i)
            if path.is_symlink():kind='link';backup.symlink_to(os.readlink(path))
            elif path.exists():kind='file';shutil.copy2(path,backup)
            snapshots.append({'path':str(path),'kind':kind,'backup':str(backup)})
        journal={'status':'prepared','previousTheme':previous,'files':snapshots}
        background=state/'omarchy/current/background'
        if background.exists() and background.is_file():
            preserved=archive/('wallpaper'+background.resolve().suffix)
            shutil.copy2(background,preserved);preserved.chmod(0o600)
            journal['wallpaper']=str(preserved)
        write_json(archive/'activation.json',journal)
        had_legacy=bool(instances('foxfire'))
        guard_enabled=run(['systemctl','--user','is-enabled','foxfire-theme-guard.path'],False).returncode==0
        journal['legacyGuardEnabled']=guard_enabled
        write_json(archive/'activation.json',journal)
        try:
            unlocked()
            run(['systemctl','--user','disable','--now','foxfire-theme-guard.path'],False)
            for group in ('theme-set.d','post-boot.d'):
                old=config/'omarchy/hooks'/group/'90-foxfire'
                if old.is_symlink():old.unlink()
                new=config/'omarchy/hooks'/group/'90-cedar'
                new.parent.mkdir(parents=True,exist_ok=True)
                if not new.exists():new.symlink_to(ROOT/'scripts/theme-hook')
            # Change only exact generated path references. Preserve user overrides,
            # bindings and every monitor setting byte-for-byte otherwise.
            if main.exists():
                text=main.read_text()
                from desktop import atomic, loader
                legacy=loader(config/'foxfire/hypr').replace('-- CEDAR graphical settings', '-- Foxfire graphical settings')
                if legacy in text:
                    text=text.replace(legacy,loader(config/'cedar/hypr'),1)
                elif '-- Foxfire graphical settings (user overrides load last).' in text:
                    raise RuntimeError('The generated compositor loader was customized; review it before migration.')
                atomic(main,text)
                run(['hyprctl','reload'])
                errors=run(['hyprctl','configerrors']).stdout.strip()
                if errors and errors.lower() not in ('ok','no errors','[]'):raise RuntimeError('Hyprland reported configuration errors: '+errors)
            for name in ('cedar-theme-guard.path','cedar-theme-guard.service'):
                source=(ROOT/'systemd'/name).read_text()
                if name.endswith('.service'):
                    source=source.replace('%h/.config/quickshell/cedar/scripts/theme-sync.py','"'+str(ROOT/'scripts/theme-sync.py').replace('%','%%').replace('"','\\"')+'"')
                units.mkdir(parents=True,exist_ok=True);(units/name).write_text(source)
            if had_legacy:
                run(['qs','-c','foxfire','ipc','call','shell','stop']);wait_for('foxfire',False)
            run(['omarchy','theme','set','cedar'],timeout=90)
            if journal.get('wallpaper'):run(['omarchy-theme-bg-set',journal['wallpaper']],timeout=30)
            run([sys.executable,str(ROOT/'scripts/theme-sync.py')],timeout=30)
            wait_for('cedar',True)
            if run(['qs','-c','cedar','ipc','call','shell','isLocked']).stdout.strip() not in ('false','true'):
                raise RuntimeError('CEDAR IPC readiness check failed.')
            run(['systemctl','--user','daemon-reload'])
            run(['systemctl','--user','enable','--now','cedar-theme-guard.path'])
            journal['status']='active'
            for entry in journal['files']:
                path=Path(entry['path']);entry['appliedHash']=fingerprint(path) if path.exists() or path.is_symlink() else None
            write_json(archive/'activation.json',journal)
            write_json(state/'cedar/installation.json',{'format':1,'source':str(ROOT),'method':'Local source registration','activation':'active'})
            print('CEDAR is active. Original source and migration archives are retained.')
        except Exception:
            # Never roll back a live locker. Keep the recovery journal for a later
            # unlocked recovery instead of weakening the session lock.
            try:unlocked()
            except Exception:
                journal['status']='recovery-deferred-locked';write_json(archive/'activation.json',journal);raise
            if instances('cedar'):
                run(['qs','-c','cedar','ipc','call','shell','stop']);wait_for('cedar',False)
            for entry in reversed(snapshots):
                path=Path(entry['path']);backup=Path(entry['backup'])
                if path.exists() or path.is_symlink():path.unlink()
                if entry['kind']=='link':path.symlink_to(os.readlink(backup))
                elif entry['kind']=='file':shutil.copy2(backup,path)
            if previous:run(['omarchy','theme','set',previous],False,90)
            run(['systemctl','--user','daemon-reload'],False)
            if guard_enabled:run(['systemctl','--user','enable','--now','foxfire-theme-guard.path'],False)
            journal['status']='rolled-back';write_json(archive/'activation.json',journal)
            raise

def rollback():
    unlocked()
    paths=locations();base=paths['state']/'cedar/activation-backups'
    candidates=sorted(base.glob('*/activation.json'),reverse=True)
    candidate=next((p for p in candidates if json.loads(p.read_text()).get('status') in ('active','recovery-deferred-locked')),None)
    if candidate is None:raise RuntimeError('No active CEDAR handoff is available to roll back.')
    journal=json.loads(candidate.read_text())
    for entry in journal['files']:
        path=Path(entry['path']);present=path.exists() or path.is_symlink()
        if 'appliedHash' in entry and (fingerprint(path) if present else None)!=entry['appliedHash']:
            raise RuntimeError('Integration was edited after activation. Recovery copies are retained; review the activation journal before restoring it.')
    unlocked()
    run(['systemctl','--user','disable','--now','cedar-theme-guard.path'],False)
    if instances('cedar'):
        run(['qs','-c','cedar','ipc','call','shell','stop']);wait_for('cedar',False)
    for entry in reversed(journal['files']):
        path=Path(entry['path']);backup=Path(entry['backup'])
        if path.exists() or path.is_symlink():path.unlink()
        if entry['kind']=='link':path.symlink_to(os.readlink(backup))
        elif entry['kind']=='file':shutil.copy2(backup,path)
    if journal['previousTheme']:run(['omarchy','theme','set',journal['previousTheme']],timeout=90)
    run(['hyprctl','reload'])
    run(['systemctl','--user','daemon-reload'])
    if journal.get('legacyGuardEnabled'):run(['systemctl','--user','enable','--now','foxfire-theme-guard.path'])
    journal['status']='rolled-back';write_json(candidate,journal)
    print('Previous theme and startup integration restored; CEDAR data is retained.')

def main():
    parser=argparse.ArgumentParser(description='CEDAR Shell')
    parser.add_argument('action',nargs='?',default='status',choices=['activate','status','ipc','migrate','recover','uninstall','rollback'])
    parser.add_argument('arguments',nargs=argparse.REMAINDER)
    args=parser.parse_args()
    if args.action=='activate':activate()
    elif args.action=='rollback':rollback()
    elif args.action=='ipc':os.execvp('qs',['qs','-c','cedar','ipc','call',*args.arguments])
    elif args.action=='migrate':
        from migrate import migrate
        print('Migration journal: '+migrate()['backup']+'/journal.json')
    elif args.action=='recover':
        if len(args.arguments)!=1:raise RuntimeError('Usage: cedar recover PATH/TO/journal.json')
        unlocked()
        if instances('cedar'):raise RuntimeError('Select another theme before recovering migrated preferences.')
        remaining=recover(args.arguments[0]);print('Recovery complete; modified files preserved: '+str(len(remaining)))
    elif args.action=='uninstall':
        from install import uninstall
        uninstall()
    else:
        print('CEDAR running: '+str(bool(instances('cedar'))))
        print('Legacy shell running: '+str(bool(instances('foxfire'))))

if __name__=='__main__':
    from distribution import main as distribution_main
    try:distribution_main()
    except Exception as error:print('CEDAR: '+str(error),file=sys.stderr);raise SystemExit(1)
