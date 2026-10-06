#!/usr/bin/env python3
"""Opt-in Omarchy 4 desktop trial. Never stop the existing authentication host
except through Omarchy's own lock-safe restart, once, while unlocked.

The independent supervisor is installed beside distribution.py for offline recovery.
The adapter only accepts audited upstream source and requires live provider checks.
"""
import contextlib, copy, hashlib, json, os, re, shlex, shutil, subprocess, sys, time, uuid
from pathlib import Path
import distribution as d
import omarchy_providers as providers

ACTIVE={'prepared','coordinating','starting','trial','kept','restore-requested','deferred','failed'}
DISABLE=['omarchy.notifications','omarchy.osd']
PROTECTED=['omarchy.lock','omarchy.idle','omarchy.polkit','omarchy.background']

def record_path():return d.paths()['state']/'session.json'
def status_path():return d.paths()['state']/'session-status.json'
def read_record():return d.read_json(record_path()) if record_path().is_file() else None
def active():
    row=read_record();return bool(row and row.get('stage') in ACTIVE)
def save(row):d.write_json(record_path(),row)

@contextlib.contextmanager
def guard():
    # Interactive Keep/Restore can arrive during a short supervisor transaction.
    deadline=time.monotonic()+10
    while True:
        lock=d.exclusive()
        try:lock.__enter__();break
        except d.Refused:
            if time.monotonic()>deadline:raise
            time.sleep(.1)
    try:yield
    finally:lock.__exit__(None,None,None)

def instances():
    from portable_providers import qs_instances
    return qs_instances()

def matching(rows,source):
    return [row for row in rows if Path(row.get('config_path','/unavailable')).resolve()==Path(source).resolve()]

def ipc(source,*args):return d.command(['qs','ipc','-p',str(source),'call',*args],timeout=3).strip()
def cedar_ipc(row,*args):return ipc(Path(row['root'])/'shell.qml',*args)
def cedar_info(row):
    try:data=json.loads(cedar_ipc(row,'shell','sessionInfo'))
    except (ValueError,d.Refused):raise d.Refused('CEDAR session state is unavailable.')
    if not isinstance(data,dict):raise d.Refused('CEDAR session state is unavailable.')
    return data
def lock_state_path():return d.paths()['state']/'lock-state.json'
def trailwatch_active(row):return bool((row.get('trailwatch') or {}).get('ready'))
def handoff_config(row):
    """After the verified lock cycle: retire the existing locker and let the
    bridge answer Omarchy's lock IPC from CEDAR's published state."""
    value=copy.deepcopy(row['configAfter'])
    value['disabledPlugins']=list(dict.fromkeys([*value.get('disabledPlugins',[]),row['trailwatch']['lockId']]))
    value['bar']['cedarLock']='trailwatch'
    value['bar']['cedarLockState']=str(lock_state_path())
    return value

def lock_state(row):
    """Unknown is locked for all mutations; a network link or process is not proof."""
    monitors=json.loads(d.command(['hyprctl','-j','monitors'],timeout=3))
    if not isinstance(monitors,list) or not monitors:raise d.Refused('Monitor lock state is unavailable.')
    if any(not isinstance(m.get('solitaryBlockedBy'),list) for m in monitors):raise d.Refused('Compositor does not expose the audited lock indicator.')
    if trailwatch_active(row):
        # CEDAR owns the lock. The compositor indicator is authoritative; CEDAR's
        # own state covers the moment between a request and the surface. A
        # shell that is gone cannot be holding a lock the compositor does not show.
        if any('LOCK' in m['solitaryBlockedBy'] for m in monitors):return True
        if not any('WORKSPACE' not in m['solitaryBlockedBy'] for m in monitors):raise d.Refused('No readable compositor lock state.')
        try:data=cedar_info(row)
        except d.Refused:return False
        return bool(data.get('locked') or data.get('lockSecure'))
    try:state=json.loads(ipc(row['omarchyShell'],'lock','status'))
    except (ValueError,d.Refused):raise d.Refused('Omarchy lock status is unavailable.')
    if not isinstance(state,dict) or state.get('passwordPam') is not True:raise d.Refused('Existing Omarchy authentication is not ready.')
    if any('LOCK' in m['solitaryBlockedBy'] for m in monitors):return True
    if not any('WORKSPACE' not in m['solitaryBlockedBy'] for m in monitors):raise d.Refused('No readable compositor lock state.')
    if state.get('locked') is not False or state.get('requested') is not False or state.get('secure') is not False:return True
    return False

def unlocked(row):
    if lock_state(row):raise d.Refused('Session locked; integration changes deferred until unlock.')

def verify_upstream(root,upstream):
    rules=d.read_json(Path(root)/'integrations/omarchy/adapter.json')
    for name,hashes in rules['sourceHashes'].items():
        if not (upstream/name).is_file() or d.digest(upstream/name) not in hashes:raise d.Refused('Omarchy integration API differs from the audited version: '+name+'. Existing authentication preserved; offline recovery remains available.')

def verify_session_api(row):
    verify_upstream(row['root'],Path(row['omarchyShell']).parent.parent)
    if row.get('omacale'):providers.verify(row['root'],row['omacale'])

def companions_ready(row):
    record=row.get('omacale')
    providers.ready(record)
    if not record or not any(p.get('profile')=='aegis-1' and p.get('selected') for p in record['providers']):return
    try:state=json.loads(ipc(row['omarchyShell'],'aegis','status'))
    except (ValueError,d.Refused):raise d.Refused('Aegis status is unavailable; leave its desktop running.')
    if not isinstance(state,dict) or state.get('healthy') is not True or state.get('operationsReady') is not True:
        raise d.Refused('Wait for Aegis to finish starting before trying CEDAR.')
    if state.get('focusActive') is not False:raise d.Refused('Finish or cancel the Aegis focus session before switching.')
    if state.get('operationsOpen') is not False:raise d.Refused('Close the Aegis Operations panel before switching so pending actions can finish.')

def transformed(config,omacale=None):
    if not isinstance(config,dict) or config.get('version')!=1:raise d.Refused('Unsupported Omarchy shell configuration.')
    value=copy.deepcopy(config)
    if not isinstance(value.get('bar'),dict):raise d.Refused('Omarchy bar configuration is missing.')
    disabled=value.get('disabledPlugins',[])
    if not isinstance(disabled,list):raise d.Refused('Invalid disabledPlugins configuration.')
    # Preserve deliberately disabled idle, polkit and wallpaper providers.
    # Only the resident locker is a prerequisite for this adapter's boundary.
    if 'omarchy.lock' in disabled and not (omacale and omacale.get('lockId')):raise d.Refused('Omarchy lockscreen (omarchy.lock) is disabled and no reviewed enabled Omacale clone was found. Existing locker preserved; do not enable competing lockers together.')
    value['bar']['id']='cedar.integration'
    value['disabledPlugins']=list(dict.fromkeys([*disabled,*DISABLE,*(omacale['disable'] if omacale else [])]))
    if omacale:value=with_guard(value)
    return value

def with_guard(config):
    value=copy.deepcopy(config);entries=value.setdefault('plugins',[])
    if not isinstance(entries,list):raise d.Refused('Unsupported Omarchy plugin configuration.')
    entries.append({'id':providers.GUARD})
    return value

def inspect(root):
    for name in ['qs','hyprctl','systemd-run','systemctl','busctl','omarchy']:
        if not shutil.which(name):raise d.Refused('Omarchy activation requires '+name+'.')
    version=d.command(['omarchy','version']).strip()
    if not re.search(r'\b4\.0\.(?:4|0\.alpha)(?:\b|$)',version):raise d.Refused('This adapter covers inspected Omarchy 4.0.4 sources only; detected '+version)
    upstream=Path(os.environ.get('OMARCHY_PATH','/usr/share/omarchy')).resolve()
    verify_upstream(root,upstream)
    source=upstream/'shell/shell.qml';rows=instances();running=matching(rows,source)
    if len(running)!=1:raise d.Refused('Expected exactly one running Omarchy shell on this display.')
    if any(Path(r.get('config_path','')).name=='shell.qml' and any(n in str(r.get('config_path','')).lower() for n in ('cedar','foxfire')) for r in rows):raise d.Refused('Another CEDAR installation is running; preserve it and finish its migration separately.')
    # These are the paths the audited Omarchy source actually reads, not guessed XDG paths.
    config=Path.home()/'.config/omarchy/shell.json'
    for p in [config,config.parent/'plugins/cedar.integration/manifest.json',config.parent/'plugins/cedar.integration/Bridge.qml',config.parent/'hooks/post-boot.d/95-cedar-session',config.parent/'plugins'/providers.GUARD/'manifest.json',config.parent/'plugins'/providers.GUARD/'Service.qml']:
        if p.is_symlink() or any(parent.is_symlink() for parent in p.parents):raise d.Refused('Managed Omarchy integration target requires manual integration: '+str(p))
        if p!=config and p.exists():raise d.Refused('An existing integration entry is not owned by this trial: '+str(p))
    # Legacy theme hooks can stop the authentication host; never run both strategies.
    for group in ['post-boot.d','theme-set.d']:
        if any((config.parent/'hooks'/group).glob('*cedar*')) or any((config.parent/'hooks'/group).glob('*foxfire*')):raise d.Refused('Legacy CEDAR theme handoff found. Existing integration preserved.')
    original=d.read_json(config if config.exists() else upstream/'config/omarchy/shell.json')
    if not isinstance(original,dict) or not isinstance(original.get('bar'),dict):raise d.Refused('Unsupported Omarchy shell configuration.')
    plugins=json.loads(ipc(source,'shell','listPlugins'))
    if not isinstance(plugins,list):raise d.Refused('Omarchy plugin inventory unavailable.')
    omacale=providers.inspect(root,original,plugins,upstream)
    transformed(original,omacale)
    row={'format':1,'adapter':'omarchy-4-resident-lock','omarchyVersion':version,'omarchyShell':str(source),'omarchyPid':running[0]['pid'],'root':str(root),'config':str(config),'original':original}
    if omacale:row['omacale']=omacale
    unlocked(row)
    companions_ready(row)
    reviewed={p['id'] for p in omacale['providers']} if omacale else set()
    for item in plugins:
        if item.get('enabled') and 'service' in item.get('kinds',[]) and not item.get('firstParty') and item.get('id') not in reviewed:
            raise d.Refused('An enabled third-party service needs a separate integration review.')
    if notification_owner()!=row['omarchyPid']:raise d.Refused('Notifications are owned by another provider. No provider will be stopped.')
    return row

def notification_owner():
    result=d.command(['busctl','--user','call','org.freedesktop.DBus','/org/freedesktop/DBus','org.freedesktop.DBus','GetConnectionUnixProcessID','s','org.freedesktop.Notifications'],timeout=3)
    match=re.fullmatch(r'u\s+(\d+)\s*',result)
    if not match:raise d.Refused('Cannot identify the notification provider.')
    return int(match.group(1))

def trial(root,approved=False,trailwatch=False):
    root=root.resolve()
    with guard():
        if active():raise d.Refused('A CEDAR desktop trial/session already exists. Use cedar keep, status, or restore.')
        row=inspect(root)
        plan={'action':'Try CEDAR for 120 seconds','adapter':row['adapter'],'changes':['Select the CEDAR empty-bar bridge in Omarchy user settings','Temporarily disable Omarchy notification and OSD plugins','Restart the Omarchy shell once, while unlocked, if it still holds notifications','Start the full CEDAR bar, Core, Canopy, Settings and notifications','Create a temporary post-boot recovery hook'],
              'preserve':['Omarchy lockscreen, PAM, idle handling, polkit agent, wallpaper, secret service and portals','Display configuration, existing keyboard shortcuts and applications'],
              'confirmation':'Run cedar keep before the timer expires; login startup needs cedar activate afterwards','recovery':'Independent supervisor restores the recorded configuration after timeout or a CEDAR crash; it defers while locked.'}
        if row.get('omacale'):
            plan['changes'].extend(['Pause Omacale notification/OSD repair watchers until restoration','Temporarily disable reviewed notification/OSD clones alongside their stock providers'])
            plan['preserve'].append('Existing Omacale lock clone, PAM, lock view and all Omacale files/settings; no authentication handover')
            plan['reviewedCompanions']=[{'name':p['name'],'action':p['policy'],'details':p['notes']} for p in row['omacale']['providers'] if p.get('role')=='companion']
        if trailwatch:
            lock_id=(row.get('omacale') or {}).get('lockId') or 'omarchy.lock'
            row['trailwatch']={'lockId':lock_id,'tested':False,'ready':False};row['locker']='trailwatch-pending'
            plan['changes'].append('Load CEDAR Trailwatch (PAM service omarchy-lock-password) beside the existing locker. cedar keep then runs a local password test and one real Trailwatch lock/unlock; only after that is '+lock_id+' disabled and Omarchy\'s lock requests answered by CEDAR')
            plan['preserve']=[p for p in plan['preserve'] if 'lock' not in p.lower()]+['Omarchy idle timings, lid, sleep and keyboard lock requests (they reach Trailwatch through the bridge after the handoff); PAM files, Omacale files and all other settings']
            plan['confirmation']='Run cedar keep before the timer expires; it completes the Trailwatch handoff after you unlock once. Login startup needs cedar activate afterwards'
        d.approve(plan,approved)
        print(d.validate(root));unlocked(row);companions_ready(row)
        tx=d.Transaction('omarchy-session')
        row.update({'id':uuid.uuid4().hex,'stage':'prepared','journal':str(tx.path),'deadline':time.time()+120,'login':False})
        row['generation']=uuid.uuid4().hex
        row['sessionSignature']=os.environ.get('HYPRLAND_INSTANCE_SIGNATURE','')
        row['unit']='cedar-session-'+row['id']+'-'+row['generation'][:8]
        original=row.pop('original')
        row['configAfter']=transformed(original,row.get('omacale'))
        if row.get('omacale'):row['configCoordinating']=with_guard(original)
        row['configAfter']['bar']['cedarShellPath']=str(root/'shell.qml')
        targets=[Path(row['config']),Path(row['config']).parent/'plugins/cedar.integration/manifest.json',Path(row['config']).parent/'plugins/cedar.integration/Bridge.qml',Path(row['config']).parent/'hooks/post-boot.d/95-cedar-session']
        if row.get('omacale'):targets.extend(Path(row['config']).parent/'plugins'/providers.GUARD/name for name in ('manifest.json','Service.qml'))
        tx.record['files']=[];tx.save()
        for p in targets:tx.backup(p)
        tx.stage('back-up');save(row)
        try:spawn_supervisor(row)
        except BaseException:
            d.restore_journal(tx.path);row['stage']='restored';save(row);raise
    print('Starting the full CEDAR desktop...',flush=True)
    wait_for_trial(row['id'])
    print('CEDAR is running. The trial lasts 120 seconds. Run cedar keep to keep this session, or cedar restore to go back.')
    print('If cedar is not on PATH, use '+shlex.quote(str(d.paths()['bin']))+' keep')

def wait_for_trial(identity):
    deadline=time.monotonic()+35
    while time.monotonic()<deadline:
        row=read_record()
        if not row or row['id']!=identity:raise d.Refused('Trial record changed. Inspect cedar status.')
        if row['stage']=='trial':return
        if row['stage']=='restored':raise d.Refused('CEDAR could not start; previous integration restored. '+row.get('error',''))
        time.sleep(.25)
    raise d.Refused('Startup/recovery is still pending, possibly awaiting unlock. Run cedar status for the local error; no permanent login choice was made.')

def spawn_supervisor(row):
    helper=d.paths()['data']/'recovery/omarchy_session.py'
    if not helper.is_file():raise d.Refused('Stable session recovery helper is missing. Reinstall the updated candidate first.')
    args=['systemd-run','--user','--quiet','--collect','--unit='+row['unit'],'--property=Restart=on-failure','--property=RestartSec=2','--property=KillMode=process','--property=StandardOutput=null','--property=StandardError=null']
    for key in ['WAYLAND_DISPLAY','DISPLAY','HYPRLAND_INSTANCE_SIGNATURE','OMARCHY_PATH','XDG_CONFIG_HOME','XDG_DATA_HOME','XDG_STATE_HOME','XDG_CACHE_HOME','XDG_RUNTIME_DIR','DBUS_SESSION_BUS_ADDRESS']:
        if key in os.environ:args.append('--setenv='+key+'='+os.environ[key])
    d.command([*args,'--',sys.executable,str(helper),'supervise',row['id'],row['generation']])

def prepare(row):
    verify_session_api(row);unlocked(row);companions_ready(row);journal=Path(row['journal']);tx=d.Transaction.__new__(d.Transaction)
    tx.path=journal;tx.directory=journal.parent;tx.record=d.read_json(journal)
    source=Path(row['root']);entries=tx.record['files']
    # Bridge first; configuration becomes effective only after the files exist.
    for entry in entries[1:3]:
        if entry.get('after') and d.same(d.info(Path(entry['path'])),entry['after']):continue
        tx.apply_file(entry,(source/'integrations/omarchy'/Path(entry['path']).name).read_bytes())
    for entry in entries[4:]:
        if entry.get('after') and d.same(d.info(Path(entry['path'])),entry['after']):continue
        tx.apply_file(entry,(source/'integrations/omarchy/omacale-guard'/Path(entry['path']).name).read_bytes())
    helper=d.paths()['data']/'recovery/omarchy_session.py'
    hook=('#!/bin/bash\n# CEDAR-owned trial recovery and confirmed login startup\nexec '+shlex.quote(sys.executable)+' '+shlex.quote(str(helper))+' login\n').encode()
    if not entries[3].get('after') or not d.same(d.info(Path(entries[3]['path'])),entries[3]['after']):tx.apply_file(entries[3],hook,0o700)
    if not entries[0].get('after') or not d.same(d.info(Path(entries[0]['path'])),entries[0]['after']):tx.apply_file(entries[0],(json.dumps(row.get('configCoordinating',row['configAfter']),indent=2)+'\n').encode())
    tx.stage('activate');row['stage']='coordinating' if row.get('omacale') else 'starting';row['readyDeadline']=time.time()+25;save(row)

def coordinated(row):
    verify_session_api(row);unlocked(row)
    if ipc(row['omarchyShell'],'cedarOmacaleGuard','ready')!='true':raise d.Refused('Waiting for Omacale notification/OSD operations to finish; locker preserved.')
    companions_ready(row)
    tx=d.Transaction.__new__(d.Transaction);tx.path=Path(row['journal']);tx.directory=tx.path.parent;tx.record=d.read_json(tx.path)
    data=(json.dumps(row['configAfter'],indent=2)+'\n').encode()
    tx.replace_owned_file(tx.record['files'][0],data)
    row['stage']='starting';row['readyDeadline']=time.time()+25;save(row)

def publish(locked):d.write_json(status_path(),{'locked':locked,'updated':time.time()*1000})

def cedar_rows(row):return matching(instances(),Path(row['root'])/'shell.qml')

def check_omarchy(row):
    matches=matching(instances(),row['omarchyShell'])
    if len(matches)!=1:raise d.Refused('Omarchy authentication host is unavailable.')
    # Only release_notifications may restart this host, through Omarchy's own command.
    if trailwatch_active(row):return matches[0] # Omarchy's lock target is CEDAR's bridge; healthy() checks CEDAR itself.
    try:state=json.loads(ipc(row['omarchyShell'],'lock','status'))
    except (ValueError,d.Refused):raise d.Refused('Omarchy lock status is unavailable.')
    if not isinstance(state,dict) or state.get('passwordPam') is not True:raise d.Refused('Omarchy authentication is not ready.')
    return matches[0]

def release_notifications(row):
    """Quickshell keeps org.freedesktop.Notifications for the life of any process
    that ever loaded a NotificationServer, so disabling Omarchy's notification
    plugins cannot free it. Restart the host once, while unlocked, through
    Omarchy's own lock-safe command; the new host loads without those plugins."""
    host=check_omarchy(row)
    try:owner=notification_owner()
    except d.Refused:return # Unowned: CEDAR registers on start.
    if owner!=host['pid']:return
    if row.get('hostRestarted'):raise d.Refused('Omarchy still owns notifications after its restart.')
    unlocked(row)
    upstream=Path(row['omarchyShell']).parent.parent
    row['hostRestarted']=True;row['readyDeadline']=time.time()+45;save(row)
    env={**os.environ,'PATH':str(upstream/'bin')+os.pathsep+os.environ.get('PATH','')}
    r=subprocess.run([str(upstream/'bin/omarchy-restart-shell')],env=env,text=True,capture_output=True,timeout=40)
    if r.returncode:raise d.Refused('Omarchy shell restart failed: '+r.stderr.strip()[:300])
    raise d.Refused('Omarchy shell restarted to release notifications; waiting for its plugins.')

def start_cedar(row):
    verify_session_api(row);check_omarchy(row);unlocked(row)
    plugins=json.loads(ipc(row['omarchyShell'],'shell','listPlugins'))
    if not any(p.get('id')=='cedar.integration' and p.get('active') for p in plugins):raise d.Refused('Omarchy has not loaded the CEDAR bridge yet.')
    disabled=DISABLE+row.get('omacale',{}).get('disable',[])
    if any(p.get('id') in disabled and p.get('enabled') for p in plugins):raise d.Refused('Overlapping Omarchy plugins have not stopped yet.')
    if row.get('omacale') and ipc(row['omarchyShell'],'cedarOmacaleGuard','ready')!='true':raise d.Refused('Omacale handover coordination is not ready.')
    release_notifications(row)
    if ipc(row['omarchyShell'],'cedarBridge','enable')!='true':raise d.Refused('Keyboard IPC bridge did not become ready.')
    source=Path(row['root']);d.verify_tree(source,d.read_json(source/'release-files.json'))
    env={**os.environ,'CEDAR_OMARCHY_SESSION':'1','CEDAR_SESSION_STATUS':str(status_path()),'CEDAR_SESSION_HELPER':str(d.paths()['data']/'recovery/omarchy_session.py'),'CEDAR_SHELL_PATH':str(source/'shell.qml'),'CEDAR_QS_BIN':shutil.which('qs'),'QS_DISABLE_FILE_WATCHER':'1','QS_NO_RELOAD_POPUP':'1'}
    env['PATH']=str(source/'scripts/shim')+os.pathsep+os.environ.get('PATH','')
    if row.get('trailwatch'):env.update({'CEDAR_OMARCHY_LOCK':'trailwatch','CEDAR_EXTERNAL_IDLE':'1','CEDAR_LOCK_STATE':str(lock_state_path())})
    publish(False)
    subprocess.Popen([env['CEDAR_QS_BIN'],'-n','-p',str(source/'shell.qml')],env=env,stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)

def healthy(row):
    check_omarchy(row);rows=cedar_rows(row)
    if row.get('omacale') and ipc(row['omarchyShell'],'cedarOmacaleGuard','ready')!='true':raise d.Refused('Omacale coordination stopped; returning to the recorded desktop.')
    if len(rows)!=1:raise d.Refused('CEDAR is not running.')
    data=cedar_info(row)
    if row.get('trailwatch'):
        if data.get('externalLock') is not False or data.get('lockReady') is not True:raise d.Refused('CEDAR Trailwatch lock surface is not ready.')
    elif data.get('externalLock') is not True:raise d.Refused('CEDAR lock delegation was not enabled.')
    if data.get('stage')!=3 or not data.get('screenCount'):raise d.Refused('The full desktop has not loaded on an output.')
    if notification_owner()!=rows[0]['pid']:raise d.Refused('CEDAR notification ownership was not acquired.')
    return rows[0]

def restore(row):
    if no_graphical_session():
        d.restore_journal(Path(row['journal']));row['stage']='restored';row['login']=False;save(row);publish(True);return
    verify_session_api(row);unlocked(row)
    d.check_restore_journal(Path(row['journal'])) # Refuse later user edits before stopping a working UI.
    try:ipc(row['omarchyShell'],'cedarBridge','disable')
    except d.Refused:pass # A failed bridge may never have registered; never stop its host.
    publish(False)
    if cedar_rows(row):
        until=time.monotonic()+5
        while cedar_rows(row) and time.monotonic()<until:
            unlocked(row);ipc(Path(row['root'])/'shell.qml','shell','stop');time.sleep(.1)
        if cedar_rows(row):raise d.Refused('CEDAR did not stop cleanly; existing authentication and recovery are preserved.')
    unlocked(row);d.restore_journal(Path(row['journal']))
    row['stage']='restored';row['login']=False;save(row);publish(True)
    deadline=time.monotonic()+8
    while time.monotonic()<deadline:
        try:
            host=check_omarchy(row)
            if notification_owner()==host['pid']:return
        except (d.Refused,OSError,ValueError,subprocess.SubprocessError):pass
        time.sleep(.2)
    raise d.Refused('Files restored, but Omarchy notification readiness is unverified. Existing authentication was not stopped.')

def no_graphical_session():
    for p in Path('/proc').glob('[0-9]*'):
        try:
            if p.stat().st_uid==os.getuid() and (p/'comm').read_text().strip().lower() in ('hyprland','qs','quickshell'):return False
        except (FileNotFoundError,ProcessLookupError):continue
        except PermissionError:raise d.Refused('Cannot prove a graphical session is absent; recovery deferred.')
    return True

def supervise(identity,generation=None):
    while True:
        with guard():
            row=read_record()
            if not row or row['id']!=identity or row['stage']=='restored':return
            if generation is not None and row.get('generation')!=generation:return
            known_unlocked=False
            try:
                locked=lock_state(row);publish(locked)
                if locked:
                    time.sleep(1);continue
                known_unlocked=True
                if row['stage']=='prepared':prepare(row)
                if row['stage']=='coordinating':
                    try:coordinated(row)
                    except (d.Refused,OSError,ValueError,subprocess.SubprocessError) as error:
                        row['error']=str(error)[:500]
                        if time.time()>row['readyDeadline']:row['stage']='restore-requested'
                        save(row)
                if row['stage']=='starting':
                    try:
                        if not cedar_rows(row):start_cedar(row)
                        healthy(row)
                        row['stage']='kept' if row.get('login') else 'trial';row['deadline']=time.time()+120;row.pop('error',None);save(row)
                    except (d.Refused,OSError,ValueError,subprocess.SubprocessError) as error:
                        row['error']=str(error)[:500];save(row)
                        if time.time()>row['readyDeadline']:row['stage']='restore-requested';save(row)
                elif row['stage'] in ('trial','kept'):
                    try:healthy(row)
                    except (d.Refused,OSError,ValueError,subprocess.SubprocessError):row['stage']='restore-requested';save(row)
                    if row['stage']=='trial' and time.time()>row['deadline']:row['stage']='restore-requested';save(row)
                if row['stage'] in ('restore-requested','deferred','failed'):restore(row);return
            except (d.Refused,OSError,ValueError,subprocess.SubprocessError) as error:
                publish(True)
                # Retain a useful local error without process environment or credentials.
                row['error']=str(error)[:500];save(row)
                if known_unlocked and row['stage']=='prepared':row['stage']='restore-requested';save(row)
        time.sleep(1)

def keep(login=False,approved=False):
    with guard():
        row=read_record()
        if not row or row['stage']=='restored':raise d.Refused('No CEDAR trial is running. Start one with cedar try, then run cedar keep only after the full desktop appears.')
        if row['stage'] not in ('trial','kept'):raise d.Refused('The trial is not ready. Run cedar status; wait for startup or resolve its reported error.')
        unlocked(row);healthy(row)
        if row['stage']=='trial' and time.time()>row['deadline']:raise d.Refused('Trial expired. Let recovery finish and start a new trial.')
        pending=bool(row.get('trailwatch')) and not row['trailwatch'].get('ready') and not login
        if pending:
            # The handoff waits for the user; give the trial time and leave the guard.
            row['deadline']=time.time()+900;save(row)
    if pending:
        lock_handoff(row['id'])
    with guard():
        row=read_record()
        if not row or row['stage'] not in ('trial','kept'):raise d.Refused('The trial ended before it could be kept. Inspect cedar status.')
        if login:
            if row['stage']!='kept':raise d.Refused('First confirm the running desktop with cedar keep.')
            d.approve({'action':'Use CEDAR at login','startup':'Keep the existing CEDAR post-boot hook; preserve Omarchy authentication, idle and wallpaper','undo':'cedar restore'},approved)
            row['login']=True
        row['stage']='kept';save(row)
        journal=Path(row['journal']);record=d.read_json(journal);record['stage']='commit';d.write_json(journal,record)
    print('CEDAR will start at login. Use cedar restore to undo.' if login else 'CEDAR kept for this session. Run cedar activate to opt into login startup, or cedar restore to go back.')

def request_restore():
    with guard():
        row=read_record()
        if not row or row['stage']=='restored':return False
        try:restore(row)
        except d.Refused:
            row['stage']='restore-requested';save(row);raise
        print('Previous Omarchy desktop restored. Authentication host and applications were preserved.')
        return True

def login():
    with guard():
        row=read_record()
        if not row or row['stage']=='restored':return
        try:verify_session_api(row)
        except d.Refused as error:row['error']=str(error);save(row);raise
        signature=os.environ.get('HYPRLAND_INSTANCE_SIGNATURE','')
        if signature and row.get('sessionSignature')==signature and row['stage'] in ('starting','trial','kept'):return
        row['generation']=uuid.uuid4().hex
        row['sessionSignature']=signature
        row.pop('hostRestarted',None) # A new login session is a new host.
        row['unit']='cedar-session-'+row['id']+'-'+row['generation'][:8]
        # No retained confirmation means recovery, not an implicit login opt-in.
        row['stage']='starting' if row.get('login') else 'restore-requested'
        row['readyDeadline']=time.time()+30;save(row)
        spawn_supervisor(row)

def wait_for(predicate,seconds,message):
    deadline=time.monotonic()+seconds
    while time.monotonic()<deadline:
        try:
            if predicate():return
        except d.Refused:pass
        time.sleep(.5)
    raise d.Refused(message)

def bridge_serving(row):
    try:
        state=json.loads(ipc(row['omarchyShell'],'lock','status'))
        plugins=json.loads(ipc(row['omarchyShell'],'shell','listPlugins'))
    except (ValueError,d.Refused):return False
    return isinstance(state,dict) and state.get('provider')=='cedar' and state.get('passwordPam') is True and isinstance(plugins,list) and not any(p.get('id')==row['trailwatch']['lockId'] and p.get('enabled') for p in plugins)

def lock_handoff(identity):
    """Trailwatch on Omarchy. Nothing about the existing locker changes until the
    user has passed a local PAM check and one real Trailwatch lock/unlock."""
    def current():
        row=read_record()
        if not row or row['id']!=identity or row['stage'] not in ('trial','kept'):raise d.Refused('The trial ended before the Trailwatch handoff finished. Inspect cedar status.')
        return row
    row=current()
    if not row['trailwatch'].get('tested'):
        info=cedar_info(row)
        if info.get('lockReady') is not True:raise d.Refused('CEDAR Trailwatch is not ready; the existing locker stays selected.')
        tests=int(info.get('authTests') or 0)
        cedar_ipc(row,'lock','testAuthentication')
        print('Enter your password in the CEDAR test window, not in this terminal. This does not lock the desktop.',flush=True)
        wait_for(lambda:int(cedar_info(row).get('authTests') or 0)>tests,180,'The password test was not completed. The existing locker stays selected; run cedar keep to try again.')
        unlocks=int(cedar_info(row).get('securedUnlocks') or 0)
        print('Password accepted. Locking once with Trailwatch now; unlock with your password to continue.',flush=True)
        cedar_ipc(row,'lock','lock')
        def unlocked_once():
            info=cedar_info(row)
            return info.get('locked') is False and int(info.get('securedUnlocks') or 0)>unlocks
        wait_for(unlocked_once,180,'A secure Trailwatch unlock was not confirmed. The existing locker stays selected; run cedar keep to try again.')
        with guard():
            row=current();row['trailwatch']['tested']=True;save(row)
    with guard():
        row=current();unlocked(row);healthy(row)
        tx=d.Transaction.__new__(d.Transaction);tx.path=Path(row['journal']);tx.directory=tx.path.parent;tx.record=d.read_json(tx.path)
        desired=handoff_config(row)
        # Mark CEDAR as the locker before the swap so the supervisor reads lock
        # state from CEDAR while Omarchy reloads its plugins.
        row['trailwatch']['ready']=True;row['locker']='trailwatch';row['configAfter']=desired;save(row)
        tx.replace_owned_file(tx.record['files'][0],(json.dumps(desired,indent=2)+'\n').encode())
    wait_for(lambda:bridge_serving(row),20,'Omarchy did not hand its lock requests to CEDAR. Run cedar restore to return to the previous locker.')
    print('Trailwatch is now the lock screen. Keyboard, idle, lid and sleep lock requests reach it through Omarchy.',flush=True)

def request_lock(suspend=False):
    row=read_record()
    if not row or row['stage'] not in ACTIVE:raise d.Refused('No managed Omarchy session.')
    if trailwatch_active(row):
        cedar_ipc(row,'lock','lock')
        if suspend:
            wait_for(lambda:cedar_info(row).get('lockSecure') is True and lock_state(row),10,'Lock coverage was not confirmed. Suspend canceled.')
            d.command(['systemctl','suspend'])
        return
    result=ipc(row['omarchyShell'],'lock','lock')
    if result!='ok':raise d.Refused('Omarchy could not begin locking: '+result)
    if suspend:
        deadline=time.monotonic()+10
        while time.monotonic()<deadline:
            state=json.loads(ipc(row['omarchyShell'],'lock','status'))
            if state.get('secure') is True and lock_state(row):d.command(['systemctl','suspend']);return
            time.sleep(.1)
        raise d.Refused('Lock coverage was not confirmed. Suspend canceled.')

def main(args):
    if os.getuid()==0:raise d.Refused('Run CEDAR as your ordinary user.')
    action=args[0] if args else 'status'
    if action=='supervise':supervise(args[1],args[2])
    elif action=='login':login()
    elif action=='lock':request_lock('--suspend' in args)
    else:raise d.Refused('Use cedar try, keep, activate, status or restore.')

if __name__=='__main__':
    try:main(sys.argv[1:])
    except (d.Refused,OSError,ValueError,subprocess.SubprocessError) as error:print('CEDAR: '+str(error),file=sys.stderr);sys.exit(1)
