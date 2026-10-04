#!/usr/bin/env python3
"""Private, transactional namespace migration. Legacy names here are intentional."""
import fcntl
import hashlib
import json
import math
import os
from pathlib import Path
import shutil
import tempfile
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]

def locations():
    home = Path.home()
    result = {key: Path(os.environ.get('XDG_'+key.upper()+'_HOME') or home/default) for key,default in
            [('config','.config'),('data','.local/share'),('state','.local/state'),('cache','.cache')]}
    if any(not p.is_absolute() for p in result.values()):raise ValueError('XDG directory overrides must be absolute paths.')
    return result

def private(path):
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    path.chmod(0o700)
    return path

def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    tmp = path.with_name('.'+path.name+'.'+uuid.uuid4().hex)
    with tmp.open('x') as f:
        os.chmod(tmp, 0o600)
        json.dump(value, f, indent=2, ensure_ascii=False); f.write('\n')
        f.flush(); os.fsync(f.fileno())
    os.replace(tmp, path)

def validate_settings(value):
    if not isinstance(value,dict): raise ValueError('Settings must be a JSON object.')
    def finite(node):
        if isinstance(node,float) and not math.isfinite(node):raise ValueError('Settings contain an invalid non-finite number.')
        if isinstance(node,dict):
            for item in node.values():finite(item)
        elif isinstance(node,list):
            for item in node:finite(item)
    finite(value)
    version=value.get('schemaVersion',value.get('configVersion',0))
    if type(version) is not int or version not in (0,1):
        raise ValueError('Unsupported settings schema; preserved without changes.')
    # Validate types declared by the live QML adapter, retaining unknown fields.
    import re
    schema=dict((name,kind) for kind,name in re.findall(r'^            property (string|bool|int|real|var|list<[^>]+>) (\w+):', (ROOT/'Config.qml').read_text(), re.M))
    for name,item in value.items():
        kind=schema.get(name)
        good = (kind is None or kind=='var' or
                kind=='string' and isinstance(item,str) or
                kind=='bool' and type(item) is bool or
                kind=='int' and type(item) is int or
                kind=='real' and type(item) in (int,float) or
                kind.startswith('list<') and isinstance(item,list))
        if not good: raise ValueError('Settings value has an incompatible type: '+name)
    return value

def fingerprint(path):
    if path.is_symlink(): return 'link:'+os.readlink(path)
    return hashlib.sha256(path.read_bytes()).hexdigest()

def migrate():
    dirs=locations()
    # Deliberately outside the data being copied; never recursively back up backups.
    archive=private(dirs['state']/'cedar-migration')
    with (archive/'migration.lock').open('a') as lock:
        os.chmod(lock.name,0o600); fcntl.flock(lock,fcntl.LOCK_EX)
        return migrate_locked(dirs,archive)

def migrate_locked(dirs,archive):
    for namespace in ('foxfire','cedar'):
        settings=dirs['config']/namespace/'settings.json'
        if settings.exists(): validate_settings(json.loads(settings.read_text()))
    run=private(archive/(str(time.time_ns())+'-'+uuid.uuid4().hex[:8]))
    journal={'format':1,'status':'staging','created':[],'preservedConflicts':[],'backup':str(run)}
    staged=[]
    try:
        for category,base in dirs.items():
            old=base/'foxfire'; new=base/'cedar'
            for label,source in [('legacy',old),('current',new)]:
                if source.exists(): shutil.copytree(source,run/'backup'/category/label,symlinks=True)
            if not old.exists(): continue
            for source in sorted(old.rglob('*')):
                rel=source.relative_to(old); target=new/rel
                if category=='config' and rel==Path('core-timer.json'):continue
                if source.is_dir() and not source.is_symlink(): continue
                if target.exists() or target.is_symlink():
                    same=source.is_file() and target.is_file() and fingerprint(source)==fingerprint(target)
                    if not same and category=='config' and rel==Path('settings.json'):
                        legacy=json.loads(source.read_text())
                        if legacy.get('barStyle')=='foxfire':legacy['barStyle']='cedar'
                        legacy['schemaVersion']=1
                        same=legacy==json.loads(target.read_text())
                    if not same:journal['preservedConflicts'].append(category+'/'+str(rel))
                    continue
                candidate=run/'stage'/category/rel
                candidate.parent.mkdir(parents=True,exist_ok=True,mode=0o700)
                if source.is_symlink(): candidate.symlink_to(os.readlink(source))
                else: shutil.copy2(source,candidate); candidate.chmod(0o600)
                if category=='config' and rel==Path('settings.json'):
                    value=validate_settings(json.loads(candidate.read_text()))
                    if value.get('barStyle')=='foxfire': value['barStyle']='cedar'
                    value['schemaVersion']=1
                    write_json(candidate,value)
                staged.append((candidate,target))
        timer=dirs['state']/'cedar/core-timer.json'
        if not timer.exists() and not any(t==timer for _,t in staged):
            for namespace in ('cedar','foxfire'):
                source=dirs['config']/namespace/'core-timer.json'
                if source.exists():
                    value=json.loads(source.read_text())
                    if not isinstance(value,dict):raise ValueError('Timer state must be a JSON object.')
                    candidate=run/'stage/timer.json';write_json(candidate,value)
                    staged.append((candidate,timer));break
        settings=dirs['config']/'cedar/settings.json'
        if not settings.exists() and not any(t==settings for _,t in staged):
            candidate=run/'stage/fresh-settings.json';write_json(candidate,{'schemaVersion':1})
            staged.append((candidate,settings))
        journal['status']='validated';write_json(run/'journal.json',journal)
        for source,target in staged:
            # Per-file atomic commit; roll back the entire transaction on failure.
            base=next(base/'cedar' for base in dirs.values() if target.is_relative_to(base/'cedar'))
            ancestor=target.parent
            while ancestor.is_relative_to(base):
                if ancestor.is_symlink():raise RuntimeError('A destination directory is a symlink; refusing to write outside the namespace.')
                ancestor=ancestor.parent
            private(target.parent)
            if target.exists() or target.is_symlink(): raise RuntimeError('Configuration changed during migration; retry.')
            temp=target.with_name('.cedar-stage-'+uuid.uuid4().hex)
            if source.is_symlink(): temp.symlink_to(os.readlink(source))
            else: shutil.copy2(source,temp)
            try:
                os.link(temp,target,follow_symlinks=False)  # atomic, refuses a racing writer
            finally:
                temp.unlink()
            journal['created'].append({'path':str(target),'hash':fingerprint(target)})
            write_json(run/'journal.json',journal)
        journal['status']='committed';write_json(run/'journal.json',journal)
        return journal
    except Exception:
        for entry in reversed(journal['created']):
            target=Path(entry['path'])
            if (target.exists() or target.is_symlink()) and fingerprint(target)==entry['hash']: target.unlink()
        journal['status']='rolled-back';write_json(run/'journal.json',journal)
        raise

def recover(journal_path):
    """Remove only unchanged files created by this run; originals were never edited."""
    journal=json.loads(Path(journal_path).read_text())
    conflicts=[]
    for entry in reversed(journal['created']):
        path=Path(entry['path'])
        if not path.exists() and not path.is_symlink(): continue
        if fingerprint(path)!=entry['hash']: conflicts.append(str(path));continue
        path.unlink()
    return conflicts

if __name__=='__main__':
    result=migrate()
    print('Migration committed. Recovery journal: '+result['backup']+'/journal.json')
    print('Existing CEDAR conflicts preserved: '+str(len(result['preservedConflicts'])))
