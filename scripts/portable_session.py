#!/usr/bin/env python3
"""Supervised, opt-in CEDAR sessions for stock Hyprland and resident Noctalia.

The supervisor is independent of QML and is copied to stable recovery storage.
All provider/configuration transitions require a positively unlocked compositor.
"""
import contextlib
import json
import os
import re
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import time
import uuid
import distribution as d
import portable_providers as providers
import portable_controls as controls
import adoption_plan
import startup_graph

ACTIVE = {'prepared', 'starting', 'trial', 'kept', 'restore-requested', 'failed'}


def record_path(): return d.paths()['state'] / 'portable-session.json'
def read_record(): return d.read_json(record_path()) if record_path().is_file() else None
def save(row): d.write_json(record_path(), row)
def status_report():
    row=read_record()
    if not row:return {'stage':'not active','mode':'Install-only'}
    result={key:row.get(key) for key in ('stage','login','deadline','error','locker')}
    adoption=row.get('adoption',{})
    result['mode']='Trial' if row['stage']=='trial' else adoption.get('mode','Ownership review required') if row['stage']=='kept' else row['stage']
    result['roles']=[{'role':role,'selected':selected,
                      'verification':'Retained; not replaced' if '(retained)' in selected or '(preserved)' in selected else 'Session checks passed; native acceptance remains separate' if row['stage'] in ('trial','kept') else 'Pending',
                      'restoration':'Recorded session transaction; cedar restore'}
                     for role,selected in adoption.get('roles',{}).items()]
    return result

def active():
    row = read_record()
    return bool(row and row.get('stage') in ACTIVE)


@contextlib.contextmanager
def guard():
    deadline = time.monotonic() + 10
    while True:
        lock = d.exclusive()
        try:
            lock.__enter__()
            break
        except d.Refused:
            if time.monotonic() > deadline:
                raise
            time.sleep(.1)
    try:
        yield
    finally:
        lock.__exit__(None, None, None)


def unlocked(row):
    if providers.locked(row):
        raise d.Refused('Session locked. Desktop changes are deferred until you unlock normally.')
    if cedar_rows(row) and ipc(row, 'shell', 'isLocked') != 'false':
        raise d.Refused('CEDAR is locking or locked. Desktop changes are deferred.')


def cedar_rows(row):
    source = (Path(row['root']) / 'shell.qml').resolve()
    return [r for r in providers.qs_instances() if Path(r.get('config_path', '/unavailable')).resolve() == source]


def ipc(row, *args): return providers.qs_ipc(Path(row['root']) / 'shell.qml', *args)


def authenticate(root):
    if not Path('/etc/pam.d/login').is_file():
        raise d.Refused('The system login PAM service is unavailable. No authentication files will be created or changed.')
    print('A local password-test window will open before Trailwatch can be enabled. Canceling leaves the desktop unchanged.', flush=True)
    result = subprocess.run(['qs', '-p', str(root / 'auth-test.qml')], text=True, capture_output=True, timeout=180,
                            env={**os.environ, 'CEDAR_AUTH_ONLY': '1', 'CEDAR_PAM_SERVICE': 'login', 'QS_DISABLE_FILE_WATCHER': '1'})
    if result.returncode or 'CEDAR_AUTH_OK' not in result.stdout + result.stderr:
        raise d.Refused('Authentication test did not succeed. Existing desktop preserved; no session lock was requested.')


def inspect_plan(root, cedar_launcher=False, trailwatch=False):
    root=root.resolve()
    row={**providers.inspect(root),'root':str(root),'candidateFingerprint':d.plan_install(root)['release']}
    controls.plan(row,cedar_launcher,trailwatch)
    return row,adoption_plan.build_plan(row,{'launcher':cedar_launcher,'trailwatch':trailwatch})


def trial(root, approved=False, expected_adapter='auto', cedar_launcher=False, trailwatch=False, expected_plan=None):
    root = root.resolve()
    for name in ('qs', 'hyprctl', 'systemd-run', 'systemctl', 'busctl'):
        if not shutil.which(name):
            raise d.Refused('Missing ' + name + '. Run cedar dependencies or rerun the installer to prepare it.')
    with guard():
        import omarchy_session
        if active() or omarchy_session.active():
            raise d.Refused('A managed CEDAR session already exists. Use cedar status, keep or restore.')
        # Discovery describes the existing providers, not the candidate. Every
        # following lock/IPC check must already know the explicit candidate path.
        row,approved_plan = inspect_plan(root,cedar_launcher,trailwatch)
        if expected_plan is not None and approved_plan['digest']!=expected_plan:
            raise d.Refused('The reviewed desktop plan is stale. Refresh it before approving changes.')
        if expected_adapter == 'noctalia' and row['locker'] != 'noctalia' or expected_adapter == 'hyprland' and row['adapter'] != 'hyprland':
            raise d.Refused('The requested adapter does not match the running desktop. Use cedar try for automatic detection.')
        selections = {'launcher':cedar_launcher,'trailwatch':trailwatch}
        plan = {'planDigest':approved_plan['digest'],'result':approved_plan['mode'],'roles':approved_plan['roles'],'action': 'Try CEDAR for 120 seconds', 'adapter': row['adapter'],
                'pause': [Path(p['exe']).name for p in row['paused']],
                'changes': ['Start CEDAR bar, Core, Canopy, Go, Settings and notifications'],
                'locker': row['locker'], 'wallpaperProvider': row['background'],
                'preserve': ['Applications, displays, shortcuts, audio/network services, portals and authentication agents'],
                'recovery': 'Independent supervisor; cedar keep confirms this session. Timeout/crash restores the previous desktop when unlocked.'}
        if row.get('providerSettings'):
            plan['changes'].append('Privately back up Noctalia settings; suspend its bar, dock, notifications and OSD. Preserve wallpaper and its authentication agent.')
        if row.get('controls'):
            plan['shortcuts'] = row['controls']['bindings']
            plan['preserve'][0] = 'Applications, displays, all other shortcuts, audio/network services, portals and authentication agents'
        if row.get('trailwatch'):
            plan['changes'].append('Test PAM locally, then open Trailwatch for one real lock/unlock test. Only after a successful secure unlock, select Trailwatch. Preserve Noctalia idle timings and route lock actions to CEDAR. Start one private hypridle sleep/lock bridge; no global idle service is enabled.')
        if row['locker'] == 'trailwatch':
            plan['authentication'] = 'Test the existing system login PAM service in a local window, then enable Trailwatch. No PAM files are changed.'
        d.approve(plan, approved)
        print(d.validate(root))
        if row['locker'] == 'trailwatch':
            authenticate(root)
        unlocked(row)
        refreshed = {**providers.inspect(root), 'root':str(root), 'candidateFingerprint':d.plan_install(root)['release']}
        controls.plan(refreshed, cedar_launcher, trailwatch)
        try: adoption_plan.require_unchanged(approved_plan, refreshed, selections)
        except ValueError as error: raise d.Refused(str(error)) from error
        tx = d.Transaction('portable-session')
        tx.record['plan'] = approved_plan
        tx.record['operations'] = [dict(operation) for operation in approved_plan['operations']]
        tx.save()
        row.update({'root': str(root), 'id': uuid.uuid4().hex, 'generation': uuid.uuid4().hex,
                    'stage': 'prepared', 'journal': str(tx.path), 'deadline': time.time() + 120,
                    'login': False, 'sessionSignature': os.environ.get('HYPRLAND_INSTANCE_SIGNATURE', ''),
                    'adoption':{'mode':approved_plan['mode'],'roles':approved_plan['roles'],'planDigest':approved_plan['digest']},
                    'pausedIntents': [], 'statusFile': str(d.paths()['state'] / 'portable-status.json')})
        row['pausedProviders'] = row['paused']
        row['unit'] = 'cedar-session-' + row['id'] + '-' + row['generation'][:8]
        if row.get('providerSettings'):
            tx.backup(Path(row['providerSettings']))
        controls.backup(row, tx)
        tx.stage('back-up')
        save(row)
        try:
            spawn(row)
        except BaseException:
            d.restore_journal(tx.path)
            row['stage'] = 'restored'
            save(row)
            raise
    print('Starting CEDAR. Your applications stay open.', flush=True)
    if row.get('trailwatch'): print('Trailwatch will lock once for verification. Unlock with your normal password; the previous lock integration stays available until this succeeds.', flush=True)
    deadline = time.monotonic() + (180 if row.get('trailwatch') else 40)
    while time.monotonic() < deadline:
        current = read_record()
        if current and current['id'] == row['id']:
            if current['stage'] == 'trial':
                print('CEDAR is ready for review. Run cedar keep within 120 seconds, or cedar restore to go back.')
                return
            if current['stage'] in ('restored', 'failed'):
                raise d.Refused('Trial did not start: ' + current.get('error', 'Run cedar status for details.'))
        time.sleep(.25)
    raise d.Refused('Startup or recovery is pending. Run cedar status; locked sessions are never interrupted.')


def spawn(row):
    helper = d.paths()['data'] / 'recovery/portable_session.py'
    if not helper.is_file():
        raise d.Refused('Stable session recovery is missing. Reinstall this candidate first.')
    args = ['systemd-run', '--user', '--quiet', '--collect', '--unit=' + row['unit'], '--property=Restart=on-failure',
            '--property=RestartSec=2', '--property=KillMode=process', '--property=StandardOutput=null', '--property=StandardError=null']
    for key in ('WAYLAND_DISPLAY', 'DISPLAY', 'HYPRLAND_INSTANCE_SIGNATURE', 'XDG_CONFIG_HOME', 'XDG_DATA_HOME',
                'XDG_STATE_HOME', 'XDG_CACHE_HOME', 'XDG_RUNTIME_DIR', 'DBUS_SESSION_BUS_ADDRESS', 'PATH'):
        if key in os.environ:
            args.append('--setenv=' + key + '=' + os.environ[key])
    d.command([*args, '--', sys.executable, str(helper), 'supervise', row['id'], row['generation']])


def transaction(row):
    tx = d.Transaction.__new__(d.Transaction)
    tx.path = Path(row['journal'])
    tx.directory = tx.path.parent
    tx.record = d.read_json(tx.path)
    return tx


def operation_state(row, kind, state, target=None):
    """Journal coarse operation outcomes; file and process records hold evidence.

    Applying is durable before an external effect. Recovery reconciles the
    original file hashes/process identities rather than trusting this label.
    Older recovery records without a versioned plan remain readable.
    """
    tx = transaction(row)
    changed = False
    for operation in tx.record.get('operations', []):
        if operation['kind'] == kind and (target is None or operation['target'] == target):
            operation['state'] = state
            changed = True
    if changed: tx.save()


def prepare(row):
    unlocked(row)
    if row.get('supervisorReady') != row.get('generation') or not row.get('supervisorReady'):
        raise d.Refused('Recovery supervisor has not acknowledged this trial generation. Existing desktop preserved.')
    tx = transaction(row)
    if row.get('providerSettings'):
        entry = tx.record['files'][0]
        if not entry.get('after'):
            operation_state(row, 'patch-provider-settings', 'applying')
            tx = transaction(row)
            entry = tx.record['files'][0]
            tx.apply_file(entry, row['settingsAfter'].encode(), entry['before'].get('mode', 0o600))
        normalize_provider_record(row)
        operation_state(row, 'patch-provider-settings', 'verified')
    for process in row['paused']:
        if process['pid'] not in row['pausedIntents']:
            row['pausedIntents'].append(process['pid'])
            save(row)  # durable intent precedes any stop
        # If interruption happened between durable intent and stopping the
        # process, retry only that same verified identity.
        if providers.same_process(process):
            operation_state(row, 'pause-provider', 'applying', process.get('unit') or str(process['pid']))
            providers.pause(process)
        if providers.same_process(process):
            raise d.Refused('The reviewed provider has not stopped; CEDAR will not overlap it.')
        operation_state(row, 'pause-provider', 'verified', process.get('unit') or str(process['pid']))
    row['stage'] = 'starting'
    row['readyDeadline'] = time.time() + 25
    transaction(row).stage('activate')
    save(row)


def normalize_provider_record(row):
    """Accept the provider's serializer only when the ENTIRE value is equal.

    User edits, migrations and dropped unknown keys remain conflicts.
    """
    if not row.get('providerSettings'):
        return
    tx = transaction(row)
    entry = tx.record['files'][0]
    path = Path(entry['path'])
    now = d.info(path)
    if not entry.get('after') or d.same(now, entry['after']):
        return
    parse = json.loads if row['adapter'] == 'noctalia-v4' else providers.tomllib.loads
    if now['type'] != 'file' or parse(path.read_text()) != parse(row['settingsAfter']):
        raise d.Refused('Noctalia settings changed after the handoff. Later edits are preserved; review the private recovery journal.')
    entry['after'] = now
    tx.save()


def start_cedar(row):
    unlocked(row)
    normalize_provider_record(row)
    providers.hide_bar(row)
    if row['adapter'].startswith('noctalia-') and providers.noctalia_state(row)['barVisible']:
        raise d.Refused('Waiting for Noctalia to release its bar.')
    if providers.notification_owner() is not None:
        raise d.Refused('Waiting for the previous notification provider to release its name.')
    root = Path(row['root'])
    d.verify_tree(root, d.read_json(root / 'release-files.json'))
    if cedar_rows(row):
        return
    env = {**os.environ, 'CEDAR_ADAPTER': row['adapter'], 'CEDAR_SESSION_GENERATION': row['generation'], 'CEDAR_MANAGED_SESSION': '1',
           'CEDAR_EXTERNAL_LOCK': '0' if row['locker'] == 'trailwatch' else '1',
           'CEDAR_EXTERNAL_IDLE': '1' if row.get('trailwatch') else '0',
           'CEDAR_BACKGROUND': row['background'], 'CEDAR_PAM_SERVICE': 'login',
           'CEDAR_SESSION_STATUS': row['statusFile'],
           'CEDAR_SESSION_HELPER': str(d.paths()['data'] / 'recovery/portable_session.py'),
           'CEDAR_SHELL_PATH': str(root / 'shell.qml'), 'QS_DISABLE_FILE_WATCHER': '1', 'QS_NO_RELOAD_POPUP': '1'}
    # An optional legacy adapter must not leak into a standalone launch.
    env.pop('CEDAR_OMARCHY_SESSION', None)
    with contextlib.suppress(d.Refused):
        env['CEDAR_HYPR_CONFIG'] = str(providers.main_config())
    publish(row, False)
    operation_state(row, 'start-cedar', 'applying')
    subprocess.Popen(['qs', '-n', '-p', str(root / 'shell.qml')], env=env, stdin=subprocess.DEVNULL,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    operation_state(row, 'start-cedar', 'applied')


def healthy(row):
    matches = cedar_rows(row)
    if len(matches) != 1:
        raise d.Refused('CEDAR is not running on this display.')
    state = json.loads(ipc(row, 'shell', 'sessionInfo'))
    if state.get('generation') != row['generation']:
        raise d.Refused('The running CEDAR instance belongs to a different trial generation.')
    if state.get('stage') != 3 or not state.get('screenCount'):
        raise d.Refused('CEDAR has not loaded its full desktop.')
    if state.get('externalLock') != (row['locker'] != 'trailwatch'):
        raise d.Refused('CEDAR lock delegation does not match the reviewed plan.')
    if row.get('trailwatch') and state.get('lockReady') is not True:
        raise d.Refused('Trailwatch authentication surfaces have not loaded; the existing locker remains available.')
    if providers.notification_owner() != matches[0]['pid']:
        raise d.Refused('CEDAR did not acquire notification ownership.')
    if row['adapter'].startswith('noctalia-') and providers.noctalia_state(row)['barVisible']:
        raise d.Refused('Noctalia bar was re-enabled; restoring the prior desktop.')
    if row.get('trailwatch', {}).get('ready'): controls.bridge_ready(row)
    paused_exes = {p['exe'] for p in row['paused']}
    if any(p['exe'] in paused_exes for p in providers.processes()):
        raise d.Refused('A paused desktop provider restarted. Returning to the previous desktop without terminating its new instance.')
    return matches[0]


def publish(row, locked):
    d.write_json(Path(row['statusFile']), {'locked': locked, 'updated': time.time() * 1000})


def no_graphical_session():
    return not any(Path(p['exe']).name.lower() in ('hyprland', 'qs', 'quickshell', 'noctalia') for p in providers.processes())


def restore(row):
    offline = no_graphical_session()
    if not offline:
        unlocked(row)
    normalize_provider_record(row)
    journal = Path(row['journal'])
    d.check_restore_journal(journal)
    if row.get('loginJournal'):
        d.check_restore_journal(Path(row['loginJournal']))
    if not offline:
        controls.restore_lock_handoff(row, transaction(row), save, unlocked)
        d.check_restore_journal(journal)
        unlocked(row)
        matches = cedar_rows(row)
        if matches:
            if ipc(row, 'shell', 'isLocked') != 'false':
                raise d.Refused('CEDAR is locking or locked. Restoration deferred.')
            ipc(row, 'shell', 'stop')
            deadline = time.monotonic() + 8
            while cedar_rows(row) and time.monotonic() < deadline:
                time.sleep(.1)
            if cedar_rows(row):
                raise d.Refused('CEDAR did not close safely. No process was killed.')
    if offline and row.get('trailwatch', {}).get('bridgeStarted'):
        controls.stop_bridge(row)
    if row.get('loginJournal'):
        d.restore_journal(Path(row['loginJournal']))
    d.restore_journal(journal)
    if not offline:
        if row.get('controls'):
            d.command(['hyprctl', 'reload'])
            if d.command(['hyprctl', 'configerrors']).strip() not in ('', 'ok', '[]'):
                raise d.Refused('Files restored, but Hyprland reported a configuration error. Review cedar status.')
        providers.restore_bar(row)
        for process in row['paused']:
            if process['pid'] in row.get('pausedIntents', []):
                providers.resume(process)
    row['stage'] = 'restored'
    row['login'] = False
    save(row)


def supervise(identity, generation):
    while True:
        with guard():
            row = read_record()
            if not row or row['id'] != identity or row['generation'] != generation or row['stage'] == 'restored':
                return
            try:
                if no_graphical_session():
                    # At session end restore unconfirmed trials; confirmed login
                    # choices wait for the compositor to run the owned hook.
                    if not row.get('login'):
                        restore(row)
                    return
                if row.get('supervisorReady') != generation:
                    row['supervisorReady'] = generation
                    save(row)  # durable ACK before prepare can suppress a provider
                is_locked = providers.locked(row)
                publish(row, is_locked)
                if not is_locked:
                    if row['stage'] == 'prepared':
                        prepare(row)
                    elif row['stage'] == 'starting':
                        if not cedar_rows(row):
                            start_cedar(row)
                        healthy(row)
                        operation_state(row, 'start-cedar', 'verified')
                        if not row.get('controlsApplied'):
                            operation_state(row, 'bind-launcher', 'applying')
                            controls.apply(row, transaction(row))
                            operation_state(row, 'bind-launcher', 'verified')
                            row['controlsApplied'] = True
                            save(row)
                        if row.get('trailwatch'): operation_state(row, 'verify-trailwatch', 'applying')
                        if controls.finish_lock_handoff(row, transaction(row), save, ipc, unlocked):
                            if row.get('trailwatch'): operation_state(row, 'verify-trailwatch', 'verified')
                            row['stage'] = 'kept' if row.get('login') else 'trial'
                            row['deadline'] = time.time() + 120
                            row.pop('error', None)
                            save(row)
                    elif row['stage'] in ('trial', 'kept'):
                        healthy(row)
                        if row['stage'] == 'trial' and time.time() > row['deadline']:
                            row['stage'] = 'restore-requested'
                            save(row)
                    if row['stage'] in ('restore-requested', 'failed'):
                        restore(row)
                        return
            except (d.Refused, OSError, ValueError, subprocess.SubprocessError) as error:
                publish(row, True)
                row['error'] = str(error)[:500]
                if row['stage'] != 'starting' or time.time() > row.get('readyDeadline', 0):
                    row['stage'] = 'restore-requested'
                save(row)
        time.sleep(1)


LOGIN_BLOCK = re.compile(r'\n?(?:--|#) CEDAR LOGIN START\n.*?(?:--|#) CEDAR LOGIN END\n?', re.S)


def without_login_block(text):
    """The startup file without CEDAR's own login block.

    The block is CEDAR-owned and delimited by its markers; one left behind by
    an earlier installation (a restore that could not run, a manual removal
    of CEDAR files) is replaced rather than refused, so re-enabling login is
    always possible. A block with a start marker and no end marker is not
    CEDAR's writing any more and is refused."""
    if 'CEDAR LOGIN START' not in text:
        return text
    if 'CEDAR LOGIN END' not in text:
        raise d.Refused('A CEDAR startup block in the Hyprland configuration is incomplete; review it before enabling login.')
    cleaned = LOGIN_BLOCK.sub('\n', text)
    if 'CEDAR LOGIN START' in cleaned:
        raise d.Refused('More than one CEDAR startup block exists; review the Hyprland configuration before enabling login.')
    return cleaned.rstrip('\n') + '\n'


def startup_entry(row):
    path = Path(row['controls']['loginFile']) if row.get('controls') else providers.main_config()
    providers.safe_target(path)
    if path.suffix not in ('.conf', '.lua'):
        raise d.Refused('Unsupported Hyprland startup syntax.')
    graph=startup_graph.inspect(path,d.xdg('CONFIG','.config'),Path.home())
    if path.suffix=='.conf' and not graph['complete']:
        raise d.Refused('Startup includes could not be fully reviewed. Existing login configuration is preserved: '+', '.join(graph['unresolved']))
    original = without_login_block(path.read_text())
    helper = d.paths()['data'] / 'recovery/portable_session.py'
    command = shlex.join([sys.executable, str(helper), 'login'])
    if any(c in command for c in ('\n', '\r', '$', '`', '#')):
        raise d.Refused('This path needs a manually reviewed Hyprland startup entry.')
    if path.suffix == '.lua':
        line = 'hl.on("hyprland.start", function() hl.exec_cmd(' + json.dumps(command, ensure_ascii=False) + ') end)'
        block = '\n-- CEDAR LOGIN START\n' + line + '\n-- CEDAR LOGIN END\n'
    else:
        block = '\n# CEDAR LOGIN START\nexec-once = ' + command + '\n# CEDAR LOGIN END\n'
    return path, (original + block).encode()


def keep(login=False, approved=False, expected_login_digest=None):
    with guard():
        row = read_record()
        if not row or row['stage'] not in ('trial', 'kept'):
            raise d.Refused('No CEDAR trial is running. Start one with cedar try; use cedar status for its progress.')
        unlocked(row)
        healthy(row)
        if row['stage'] == 'trial' and time.time() > row['deadline']:
            raise d.Refused('The trial expired. Wait for restoration, then try again.')
        if login:
            if row['stage'] != 'kept':
                raise d.Refused('First confirm this desktop with cedar keep.')
            if row.get('login'):
                print('CEDAR is already selected for login.')
                return
            path, content = startup_entry(row)
            proposed = adoption_plan.fingerprint({'path':str(path),'before':d.info(path),'content':content.decode()})
            if expected_login_digest is not None and proposed!=expected_login_digest:
                raise d.Refused('The reviewed login change is stale. Review it again; startup was not changed.')
            d.approve({'action': 'Use CEDAR at login', 'edit': str(path),
                       'changes': 'Enable the reviewed CEDAR session at login. All unselected startup commands and shortcuts stay intact.',
                       'undo': 'cedar restore'}, approved)
            unlocked(row)
            integrated = bool(row.get('controls'))
            tx = transaction(row) if integrated else d.Transaction('portable-login')
            if not integrated:
                row['loginJournal'] = str(tx.path)
                save(row)
            previous = path.read_bytes()
            try:
                entry = next(e for e in tx.record['files'] if e['path'] == str(path)) if integrated else tx.backup(path)
                if integrated: tx.replace_owned_file(entry, content, 0o600)
                else: tx.apply_file(entry, content, entry['before']['mode'])
                d.command(['hyprctl', 'reload'])
                errors = d.command(['hyprctl', 'configerrors']).strip()
                if errors not in ('', 'ok', '[]'):
                    raise d.Refused('Hyprland rejected the startup entry: ' + errors[:300])
                tx.commit()
                row['login'] = True
            except BaseException:
                if integrated: tx.replace_owned_file(entry, previous, 0o600)
                else: d.restore_journal(tx.path)
                with contextlib.suppress(Exception): d.command(['hyprctl', 'reload'])
                raise
        row['stage'] = 'kept'
        save(row)
        tx = transaction(row)
        tx.commit()
    print('CEDAR will start at login. cedar restore undoes the integration.' if login else 'CEDAR kept for this session. Run cedar activate for login startup, or cedar restore to go back.')


def request_restore():
    with guard():
        row = read_record()
        if not row or row['stage'] == 'restored':
            return False
        row['stage'] = 'restore-requested'
        save(row)
        restore(row)
    print('Previous desktop restored. Applications and the existing locker were preserved.')
    return True


def login():
    # Compositor exec-once and other providers initialize concurrently.
    with guard():
        row = read_record()
        if not row or row['stage'] == 'restored':
            return
        signature = os.environ.get('HYPRLAND_INSTANCE_SIGNATURE', '')
        if signature and signature == row.get('sessionSignature'):
            return
        if not row.get('login'):
            row['stage'] = 'restore-requested'
        else:
            row['stage'] = 'starting'
        row['generation'] = uuid.uuid4().hex
        row['unit'] = 'cedar-session-' + row['id'] + '-' + row['generation'][:8]
        row['sessionSignature'] = signature
        row['readyDeadline'] = time.time() + 40
        row['controlsApplied'] = False
        if row.get('trailwatch'):
            row['trailwatch']['bridgeStarted'] = False
            row['trailwatch']['ready'] = False
        # Refresh provider PIDs on the same reviewed source, never use old PIDs.
        if row['adapter'].startswith('noctalia-'):
            providers.verify_noctalia(Path(row['root']), row)
            matches = [p for p in providers.processes() if p['exe'] == row['providerExe']]
            if row['adapter'] == 'noctalia-v4':
                matches = [p for p in matches if any(i['pid'] == p['pid'] and i.get('config_path') == row['providerSource'] for i in providers.qs_instances())]
            if len(matches) != 1:
                raise d.Refused('Waiting for the recorded Noctalia provider. Run cedar session-login after it has started.')
            row['provider'] = matches[0]
        # Standalone providers may have started at login; pause only identical
        # executable/argv combinations recorded in the approved original plan.
        refreshed = []
        for previous in row.get('pausedProviders', row['paused']):
            matches = [p for p in providers.processes() if p['exe'] == previous['exe'] and p['argv'][1:] == previous['argv'][1:]]
            if len(matches) == 1:
                refreshed.append({**previous, **matches[0]})
            else:
                raise d.Refused('Waiting for the recorded desktop provider. An absent or changed startup provider requires a new reviewed trial.')
        row['paused'] = refreshed
        row['pausedIntents'] = []
        if row.get('login'): row['stage'] = 'prepared'
        save(row)
        spawn(row)


def main(args):
    action = args[0] if args else ''
    if action == 'supervise': supervise(args[1], args[2])
    elif action == 'login':
        deadline = time.monotonic() + 45
        while True:
            try:
                login()
                break
            except (d.Refused, OSError, ValueError, subprocess.SubprocessError):
                if time.monotonic() > deadline: raise
                time.sleep(1)
    elif action in ('lock', 'launcher'):
        row = read_record()
        if not row or not active(): raise d.Refused('No active portable session.')
        if action == 'lock': providers.request_lock(row, '--suspend' in args)
        else:
            unlocked(row)
            ipc(row, 'launcher', 'toggle')
    else: raise d.Refused('Use cedar try, keep, activate, status or restore.')


if __name__ == '__main__':
    try: main(sys.argv[1:])
    except (d.Refused, OSError, ValueError, subprocess.SubprocessError) as error:
        print('CEDAR: ' + str(error), file=sys.stderr)
        sys.exit(1)
