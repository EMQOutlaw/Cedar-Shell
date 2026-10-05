"""Pure, versioned desktop handoff plans. No probes, processes or file writes.

The existing session executor owns mutations; this module binds its approved
inputs and distinguishes retained providers from a complete desktop adoption.
"""
import hashlib
import json
from pathlib import PurePath

FORMAT = 1
KINDS = frozenset(('patch-provider-settings', 'pause-provider', 'start-cedar',
                   'bind-launcher', 'verify-trailwatch'))


def fingerprint(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False,
                                     allow_nan=False).encode()).hexdigest()


def build_plan(snapshot, selections):
    """Accept already-inspected evidence; never infer authority from a label."""
    adapter = snapshot['adapter']
    if adapter not in ('hyprland', 'noctalia-v4', 'noctalia-v5'):
        raise ValueError('This provider needs a reviewed adapter before desktop adoption.')
    source = snapshot.get('root')
    if not source or not PurePath(source).is_absolute():
        raise ValueError('The candidate needs an explicit absolute source path.')
    roles = {role: 'CEDAR' for role in ('bar', 'notifications', 'osd', 'settings')}
    roles['launcher'] = 'CEDAR Go' if selections.get('launcher') else 'Existing launcher (retained)'
    roles['lock'] = 'Trailwatch after local verification' if selections.get('trailwatch') or snapshot['locker']=='trailwatch' else snapshot['locker']+' (retained)'
    roles['idle'] = 'Existing idle provider (retained)' if snapshot['locker']!='trailwatch' else 'CEDAR'
    roles['wallpaper'] = 'CEDAR' if snapshot['background']=='cedar' else 'Existing wallpaper provider (retained)'
    roles['clipboard'] = snapshot.get('clipboardProvider','Existing history provider unverified (retained)')
    roles['tray'] = 'CEDAR tray host; application-owned items preserved'
    for role in ('polkit', 'secret-service', 'portals'):
        roles[role] = 'Existing session service (preserved)'
    operations=[]
    def add(kind, target, before, desired, inverse):
        if kind not in KINDS: raise ValueError('Unknown desktop operation.')
        op={'kind':kind,'target':target,'preconditions':before,'desired':desired,'inverse':inverse,'state':'planned'}
        op['id']=fingerprint(op)[:24]
        operations.append(op)
    if snapshot.get('providerSettings'):
        add('patch-provider-settings',snapshot['providerSettings'],snapshot.get('settingsBefore'),
            fingerprint(snapshot['settingsAfter']), 'Restore verified private backup; preserve later edits')
    for process in snapshot.get('paused',[]):
        add('pause-provider',process.get('unit') or str(process['pid']),
            {key:process.get(key) for key in ('pid','start','exe','argv','unit')},'paused',
            'Resume only the recorded provider, without enabling its service')
    add('start-cedar',source,{'source':source},'healthy desktop and notification owner','Stop only after known unlock')
    if selections.get('launcher'):add('bind-launcher','reviewed shortcut',snapshot.get('controls'), 'CEDAR Go','Restore exact previous binding')
    if selections.get('trailwatch'):add('verify-trailwatch','session lock',snapshot.get('trailwatch'),'secure unlock verified','Restore prior locker before stopping CEDAR')
    result={'format':FORMAT,'adapter':adapter,'roles':roles,'operations':operations,
            'mode':'Adopted Hybrid' if any('(retained)' in value for value in roles.values()) else 'Adopted Complete',
            'source':source,'snapshotDigest':fingerprint(snapshot),'selections':dict(selections)}
    result['digest']=fingerprint(result)
    return result


def require_unchanged(plan, snapshot, selections):
    if build_plan(snapshot,selections)['digest'] != plan['digest']:
        raise ValueError('Desktop evidence changed after the plan was approved. Review a fresh plan; no provider was changed.')
