"""Read-only validation of already-installed Omacale providers.

No third-party script is executed, copied, edited, enabled or removed here.
"""
from pathlib import Path
import re
import distribution as d

GUARD='cedar.omacale-guard'
ROLES={'omarchy.lock','omarchy.notifications','omarchy.osd','omarchy.idle','omarchy.menu'}

def verified_file(base,name,expected):
    rel=Path(name)
    if rel.is_absolute() or '..' in rel.parts:raise d.Refused('Unsafe provider inventory path.')
    path=base/rel
    if any(parent.is_symlink() for parent in path.parents) or path.is_symlink():raise d.Refused('Symlinked provider source needs separate review.')
    if not path.is_file() or d.digest(path)!=expected:raise d.Refused('Installed provider source differs from the reviewed adapter: '+name+'. Existing locker preserved.')

def runtime_extras(base,known,ignored=()):
    for p in base.rglob('*'):
        if any(part in ignored for part in p.relative_to(base).parts):continue
        if p.suffix in ('.qml','.js','.qsb') or p.name=='qmldir':
            if str(p.relative_to(base)) not in known:raise d.Refused('Additional provider runtime code needs review. Existing locker preserved.')

def companion_files(base,known):
    for name,checksum in known.items():verified_file(base,name,checksum)
    runtime_extras(base,known,('.git','tests','test'))
    for path in base.rglob('*'):
        if any(part in ('.git','tests','test') for part in path.relative_to(base).parts):continue
        if path.suffix in ('.py','.sh','.lua','.so') and str(path.relative_to(base)) not in known:
            raise d.Refused('Additional companion helper needs review: '+str(path.relative_to(base)))

def companion(root,base,identity,manifest,selected):
    """Match reviewed bytes and lifecycle, never a personal plugin identifier."""
    catalog=Path(root)/'integrations/omarchy/companions.json'
    profiles=d.read_json(catalog)['profiles'] if catalog.is_file() else []
    failures=[]
    for spec in profiles:
        if any(manifest.get(k,False if k=='keepLoaded' else None)!=v for k,v in spec['contract'].items()):continue
        if manifest.get('omarchy',{}).get('capabilities',[]) or manifest.get('omarchy',{}).get('clonedFrom'):continue
        try:
            companion_files(base/identity,spec['files'])
            for dep in spec.get('dependencies',[]):companion_files(base/dep['directory'],dep['files'])
        except d.Refused as error:
            failures.append(str(error));continue
        return {'id':identity,'role':'companion','profile':spec['key'],'name':spec['name'],
                'manifest':d.digest(base/identity/'manifest.json'),'files':spec['files'],
                'dependencies':spec.get('dependencies',[]),'selected':selected,
                'policy':spec['policy'],'notes':spec['notes']}
    raise d.Refused(failures[0] if failures else 'No reviewed source/lifecycle profile. Preserve this plugin and provide its source for review.')

def ready(record):
    """Read only the needed activity flag; never log/store tasks or search history."""
    if not record or not any(p.get('profile')=='aegis-1' and p.get('selected') for p in record['providers']):return
    state=Path.home()/'.local/state/omarchy/aegis-operations.json'
    if state.exists():
        try:value=d.read_json(state)
        except (OSError,ValueError):raise d.Refused('Aegis focus state is unreadable; leave its desktop running.')
        if not isinstance(value,dict):raise d.Refused('Aegis focus state is invalid; leave its desktop running.')
        if value.get('focus'):raise d.Refused('Finish or cancel the Aegis focus session in Aegis before trying CEDAR. Its timer and settings were not changed.')

def inspect(root,config,plugins,upstream):
    """Return an exact, private snapshot of the providers this trial preserves."""
    selected=config.get('bar',{}).get('id')=='omacale.bar'
    # A cloned locker has its own service lifetime. Changing the bar does not
    # remove it, so discover enabled provider roles independently of bar.id.
    lock_clones=[p for p in plugins if p.get('enabled') and not p.get('firstParty') and p.get('clonedFrom')=='omarchy.lock']
    if not selected and not lock_clones:return None
    rules=d.read_json(root/'integrations/omarchy/omacale.json')
    base=Path.home()/'.config/omarchy/plugins'
    bar=base/'omacale.bar'
    for name,checksum in rules['barFiles'].items():verified_file(bar,name,checksum)
    runtime_extras(bar,rules['barFiles'])
    if selected and not any(p.get('id')=='omacale.bar' and p.get('active') for p in plugins):raise d.Refused('Omacale is selected but its running bar could not be verified.')
    record={'version':rules['version'],'providers':[],'disable':[],'lockId':None}
    active=[p for p in plugins if p.get('enabled') and not p.get('firstParty') and p.get('id')!='omacale.bar']
    failures=[]
    for p in active:
        role=p.get('clonedFrom');identity=p.get('id','')
        if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]*',identity) or '..' in identity:raise d.Refused('Invalid provider identity.')
        directory=base/identity;manifest=directory/'manifest.json'
        if manifest.is_symlink() or not manifest.is_file():raise d.Refused('Provider manifest is missing or managed.')
        m=d.read_json(manifest)
        if role not in ROLES:
            try:
                if m.get('id')!=identity:raise d.Refused('Manifest identity differs from the running inventory.')
                is_selected=config.get('bar',{}).get('id')==identity
                if is_selected and not p.get('active'):raise d.Refused('Selected companion bar is not active.')
                record['providers'].append(companion(root,base,identity,m,is_selected))
            except d.Refused as error:failures.append(identity+': '+str(error))
            continue
        spec=rules['roles'][role]
        if m.get('id')!=identity or m.get('omarchy',{}).get('clonedFrom')!=role:raise d.Refused('Provider identity does not match the running shell.')
        for key,expected in spec['contract'].items():
            if m.get(key)!=expected:raise d.Refused('Provider lifecycle contract differs for '+role+'. Existing locker preserved.')
        if m.get('omarchy',{}).get('capabilities',[])!=spec['capabilities']:raise d.Refused('Provider capability contract differs for '+role+'.')
        valid=False
        for variant in spec['variants']:
            try:
                for name,checksum in variant.items():verified_file(directory,name,checksum)
                valid=True;break
            except d.Refused:pass
        if not valid:raise d.Refused('Unreviewed or stale clone of '+role+'. No provider was changed.')
        runtime_extras(directory,variant)
        # Record the verified bytes for later mutation/startup checks. IDs and
        # paths remain local; release metadata contains no machine identities.
        entry={'id':identity,'role':role,'manifest':d.digest(manifest),'files':variant}
        record['providers'].append(entry)
        if role=='omarchy.lock':
            if record['lockId']:raise d.Refused('Multiple enabled lock clones; no takeover attempted.')
            record['lockId']=identity
        if role in ('omarchy.notifications','omarchy.osd'):record['disable'].append(identity)
    if failures:raise d.Refused('Plugin review incomplete; no desktop changes made:\n'+'\n'.join(failures))
    disabled=config.get('disabledPlugins',[])
    if 'omarchy.lock' in disabled and not record['lockId']:raise d.Refused('Omacale lock clone is not enabled. Keep the existing setup and repair its locker before trying CEDAR.')
    if record['lockId'] and 'omarchy.lock' not in disabled:raise d.Refused('Both stock and cloned lock providers are enabled; no takeover attempted.')
    ready(record)
    return record

def verify(root,record):
    rules=d.read_json(Path(root)/'integrations/omarchy/omacale.json');base=Path.home()/'.config/omarchy/plugins'
    for name,checksum in rules['barFiles'].items():verified_file(base/'omacale.bar',name,checksum)
    runtime_extras(base/'omacale.bar',rules['barFiles'])
    for p in record['providers']:
        verified_file(base/p['id'],'manifest.json',p['manifest'])
        if p.get('role')=='companion':
            companion_files(base/p['id'],p['files'])
            for dep in p.get('dependencies',[]):companion_files(base/dep['directory'],dep['files'])
            continue
        for name,checksum in p['files'].items():verified_file(base/p['id'],name,checksum)
        runtime_extras(base/p['id'],p['files'])
