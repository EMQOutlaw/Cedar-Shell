"""Versioned discovery for managed shells. Not authority to kill their hosts."""
import json
from pathlib import Path
import shutil
import subprocess
import distribution as d


def package_inventory():
    """One query per inspection, never repository refreshes or package mutation."""
    if not shutil.which('pacman'):return {}
    result=subprocess.run(['pacman','-Q'],capture_output=True,text=True,timeout=10)
    if result.returncode:return {}
    return dict(line.split(' ',1) for line in result.stdout.splitlines() if ' ' in line)


def inspect(kind, source, packages, root=d.ROOT):
    if kind not in ('ryoku','caelestia'):raise ValueError('Unknown managed adapter')
    rules=d.read_json(root/'integrations'/kind/'adapter.json')
    state=d.xdg('STATE','.local/state')/rules['stateFile']
    result={'adapter':rules['id'],'adapterVersion':rules['adapterVersion'],
            'takeoverCertified':False,'action':'Isolated preview only; existing providers preserved',
            'reviewState':'Needs installed startup/lock review','blocker':rules['activationBlocker'],
            'evidence':'Running Quickshell source matched this provider name; settings alone do not prove ownership',
            'packageVersions':{name:version for name,version in packages.items() if name in (kind+'-shell',kind+'-shell-git',kind+'-cli',kind+'-desktop')},
            'state':'Unavailable','managedFiles':0,'enabledComponents':[],
            'preservedOverrideCount':sum((d.xdg('CONFIG','.config')/path).exists() for path in rules['preservedOverrides'])}
    # Inspect only the bounded JSON ownership state. Never execute hooks or
    # deserialize application code. Private paths stay out of doctor output.
    if state.is_file() and not state.is_symlink():
        try:
            with state.open('rb') as stream:raw=stream.read(1048577)
            if len(raw)>1048576:raise ValueError('State exceeds limit')
            value=json.loads(raw)
            if not isinstance(value,dict):raise ValueError('Invalid state')
            result['state']='Read'
            files=value.get('deployed_files',{})
            if isinstance(files,dict):result['managedFiles']=len(files)
            enabled=value.get('enabled_components',[])
            # These are implementation component IDs, not arbitrary user text.
            known={'hypr','auth','clipboard','network','bluetooth','pipewire','uwsm'}
            if isinstance(enabled,list):result['enabledComponents']=sorted(key for key in enabled if isinstance(key,str) and key in known)
        except (OSError,ValueError):result['state']='Failed to read bounded ownership state'
    return result
