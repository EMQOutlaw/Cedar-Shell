"""Read-only validation of already-installed Omacale providers.

No third-party script is executed, copied, edited, enabled or removed here.
"""
from pathlib import Path
import distribution as d

GUARD='cedar.omacale-guard'
ROLES={'omarchy.lock','omarchy.notifications','omarchy.osd','omarchy.idle','omarchy.menu'}

def verified_file(base,name,expected):
    rel=Path(name)
    if rel.is_absolute() or '..' in rel.parts:raise d.Refused('Unsafe provider inventory path.')
    path=base/rel
    if any((base/Path(*rel.parts[:i])).is_symlink() for i in range(len(rel.parts)+1)):raise d.Refused('Symlinked provider source needs separate review.')
    if not path.is_file() or d.digest(path)!=expected:raise d.Refused('Installed Omacale source differs from the reviewed 0.45.0 adapter: '+name+'. Existing locker preserved.')

def runtime_extras(base,known):
    for p in base.rglob('*'):
        if p.suffix in ('.qml','.js','.qsb') or p.name=='qmldir':
            if str(p.relative_to(base)) not in known:raise d.Refused('Additional provider runtime code needs review. Existing locker preserved.')

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
    for p in active:
        role=p.get('clonedFrom');identity=p.get('id','')
        if role not in ROLES:raise d.Refused('An additional enabled third-party plugin needs a separate integration review.')
        if not identity or '/' in identity or '..' in identity:raise d.Refused('Invalid provider identity.')
        directory=base/identity;manifest=directory/'manifest.json'
        if manifest.is_symlink() or not manifest.is_file():raise d.Refused('Provider manifest is missing or managed.')
        m=d.read_json(manifest);spec=rules['roles'][role]
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
    disabled=config.get('disabledPlugins',[])
    if 'omarchy.lock' in disabled and not record['lockId']:raise d.Refused('Omacale lock clone is not enabled. Keep the existing setup and repair its locker before trying CEDAR.')
    if record['lockId'] and 'omarchy.lock' not in disabled:raise d.Refused('Both stock and cloned lock providers are enabled; no takeover attempted.')
    return record

def verify(root,record):
    rules=d.read_json(Path(root)/'integrations/omarchy/omacale.json');base=Path.home()/'.config/omarchy/plugins'
    for name,checksum in rules['barFiles'].items():verified_file(base/'omacale.bar',name,checksum)
    runtime_extras(base/'omacale.bar',rules['barFiles'])
    for p in record['providers']:
        verified_file(base/p['id'],'manifest.json',p['manifest'])
        for name,checksum in p['files'].items():verified_file(base/p['id'],name,checksum)
        runtime_extras(base/p['id'],p['files'])
