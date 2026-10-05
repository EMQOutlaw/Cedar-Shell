"""Versioned read-only integration adapters. No unverified takeover recipes."""
from pathlib import Path
import json

VERSION=3

def inspect(instances, manifest):
    findings=[]
    packages=None
    # Evidence must be a running instance's source, not an installed folder.
    for instance in instances:
        source=str(instance.get('configPath',instance.get('config_path',instance.get('config', ''))))
        source=source.replace('\\','/')
        kind=next((name for name in ('omarchy','caelestia','ryoku') if '/'+name+'/' in source), 'generic-quickshell')
        if (Path(source).parent/'Commons/Settings.qml').is_file() and (Path(source).parent/'Services/Control/IPCService.qml').is_file():kind='noctalia-v4'
        if kind in ('caelestia','ryoku'):
            import managed_adapters
            if packages is None:packages=managed_adapters.package_inventory()
            findings.append(managed_adapters.inspect(kind,source,packages))
            continue
        declared=next((e for e in manifest['environments'] if e['id']==('arch-omarchy' if kind=='omarchy' else kind)),None)
        findings.append({'adapter':kind,'adapterVersion':VERSION,'evidence':'Running Quickshell instance source; version/source checks still required before trial','takeoverCertified':bool(declared and declared['takeoverCertified']), 'action':'Guarded trial available' if declared and declared.get('trialImplemented') else 'Preview only; existing providers preserved'})
    from portable_providers import processes
    if any(Path(p['exe']).name == 'noctalia' for p in processes()):
        findings.append({'adapter':'noctalia-v5','adapterVersion':VERSION,'evidence':'Running native process; version/IPC checks still required before trial','takeoverCertified':False,'action':'Guarded trial available for reviewed version'})
    if not findings:findings.append({'adapter':'plain-hyprland','adapterVersion':VERSION,'evidence':'No identified running Quickshell provider; other bars/lockers may still exist','takeoverCertified':False,'action':'Read-only discovery; no startup edits'})
    return findings

def startup_inventory(config):
    # Do not recursively source or execute compositor configuration while inspecting.
    result=[]
    for rel in ['hypr/hyprland.conf','hypr/hyprland.lua','hypr/autostart.conf','hypr/autostart.lua']:
        path=config/rel
        if path.exists():
            from startup_graph import inspect as inspect_graph
            graph=inspect_graph(path,config,Path.home())
            result.append({'location':rel,'kind':'managed symlink' if path.is_symlink() else 'ordinary file',
                           'syntax':path.suffix,'includeFiles':len(graph['files']),'discoveryComplete':graph['complete'],
                           'unresolved':graph['unresolved'],
                           'editPolicy':'Login edits require a healthy kept trial, explicit approval and an ordinary owned target'})
    return result
