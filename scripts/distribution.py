#!/usr/bin/env python3
"""CEDAR distribution transactions. Stdlib recovery works without Qt or a display."""
import argparse, contextlib, fcntl, hashlib, json, os, shutil, stat, subprocess, sys, tarfile, tempfile, time, uuid
from pathlib import Path
# The session helper imports this module. Keep one exception class when this
# file is the installed executable as well as when it is imported by tests.
if __name__=='__main__':sys.modules['distribution']=sys.modules[__name__]
ROOT=Path(__file__).resolve().parents[1]
FORMAT=1

class Refused(RuntimeError):pass

def xdg(kind, default):
    value=Path(os.environ.get('XDG_'+kind+'_HOME') or Path.home()/default)
    return value if value.is_absolute() else Path.home()/default

def paths():
    return {'data':xdg('DATA','.local/share')/'cedar','state':xdg('STATE','.local/state')/'cedar',
            'config':xdg('CONFIG','.config')/'cedar','cache':xdg('CACHE','.cache')/'cedar',
            'bin':Path.home()/'.local/bin/cedar'}

def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def info(path):
    if path.is_symlink():return {'type':'link','target':os.readlink(path)}
    if not path.exists():return {'type':'absent'}
    if not path.is_file():raise Refused('Expected a regular owned file: '+str(path))
    st=path.stat()
    return {'type':'file','sha256':digest(path),'mode':stat.S_IMODE(st.st_mode),'mtime_ns':st.st_mtime_ns}

def same(a,b):return {k:v for k,v in a.items() if k!='mtime_ns'}=={k:v for k,v in b.items() if k!='mtime_ns'}
def secure_parent(path):
    # A managed/symlinked parent needs an explicit integration, not traversal.
    for parent in [path.parent,*path.parent.parents]:
        if parent.is_symlink():raise Refused('Managed or symlinked parent needs manual integration: '+str(parent))
    path.parent.mkdir(parents=True,exist_ok=True,mode=0o700)

def atomic(path,data,mode=0o600):
    secure_parent(path)
    fd,name=tempfile.mkstemp(prefix='.cedar-',dir=path.parent)
    try:
        with os.fdopen(fd,'wb') as stream:
            stream.write(data);stream.flush();os.fsync(stream.fileno())
        os.chmod(name,mode);os.replace(name,path)
        d=os.open(path.parent,os.O_RDONLY|os.O_DIRECTORY)
        try:os.fsync(d)
        finally:os.close(d)
    finally:Path(name).unlink(missing_ok=True)

def write_json(path,value):atomic(path,(json.dumps(value,indent=2,ensure_ascii=False)+'\n').encode())
def read_json(path):return json.loads(path.read_text())
def command(argv,timeout=30):
    r=subprocess.run(argv,text=True,capture_output=True,timeout=timeout)
    if r.returncode:raise Refused('Command failed: '+argv[0]+' (exit '+str(r.returncode)+'). '+r.stderr.strip()[:300])
    return r.stdout

@contextlib.contextmanager
def exclusive():
    lock=paths()['state']/'distribution.lock';secure_parent(lock)
    with lock.open('a') as stream:
        os.chmod(lock,0o600)
        try:fcntl.flock(stream,fcntl.LOCK_EX|fcntl.LOCK_NB)
        except BlockingIOError:raise Refused('Another CEDAR operation is running.')
        yield

def files(root):
    # Use the same explicit inventory in checkouts and extracted archives.
    # Never recursively copy local settings or an accidentally nested checkout.
    inventory=root/'data/source-files.json'
    if inventory.is_symlink():raise Refused('Source inventory must be a regular file.')
    names=read_json(inventory)
    if not isinstance(names,list) or any(not isinstance(name,str) for name in names):raise Refused('Invalid source inventory.')
    if len(names)!=len(set(names)):raise Refused('Duplicate source inventory entry.')
    result=[]
    for name in sorted(names):
        rel=Path(name)
        if not name or rel.is_absolute() or '..' in rel.parts or str(rel)!=name or '.git' in rel.parts:raise Refused('Unsafe source inventory entry.')
        p=root/rel
        if any((root/Path(*rel.parts[:i])).is_symlink() for i in range(1,len(rel.parts)+1)):raise Refused('Release source contains a symlink: '+name)
        if not p.is_file():raise Refused('Required release source is missing: '+name)
        if p.read_bytes()[:80].startswith(b'version https://git-lfs.github.com/spec/'):raise Refused('Unresolved LFS asset: '+name)
        result.append((p,rel))
    return result

def verify_tree(root,inventory):
    for name,record in inventory.items():
        p=root/name
        if not p.is_file() or p.is_symlink() or digest(p)!=record['sha256']:raise Refused('Release file verification failed: '+name)
    return True

class Transaction:
    def __init__(self, action):
        self.directory=paths()['state']/'transactions'/(str(time.time_ns())+'-'+uuid.uuid4().hex[:8])
        self.directory.mkdir(parents=True,mode=0o700)
        self.path=self.directory/'journal.json'
        self.record={'format':FORMAT,'action':action,'stage':'inspect','files':[],'packages':[], 'created':time.time()}
        self.save()
    def save(self):write_json(self.path,self.record)
    def stage(self,name):
        self.record['stage']=name;self.save()
        if os.environ.get('CEDAR_INJECT_FAILURE')==name:raise OSError('Injected interruption at '+name)
    def backup(self,path):
        before=info(path);entry={'path':str(path),'before':before,'after':None}
        if before['type']=='file':
            backup=self.directory/('file-'+str(len(self.record['files'])))
            shutil.copy2(path,backup);backup.chmod(0o600)
            if digest(backup)!=before['sha256']:raise Refused('Backup checksum mismatch.')
            entry['backup']=backup.name
        self.record['files'].append(entry);self.save();return entry
    def apply_file(self,entry,data,mode=0o600):
        path=Path(entry['path'])
        if not same(info(path),entry['before']):raise Refused('File changed since backup: '+str(path))
        # Intent is durable before replacement so interrupted writes are recoverable.
        entry['after']={'type':'file','sha256':hashlib.sha256(data).hexdigest(),'mode':mode};self.save()
        atomic(path,data,mode)
    def apply_link(self,entry,target):
        path=Path(entry['path']);secure_parent(path)
        if not same(info(path),entry['before']):raise Refused('Link changed since backup.')
        entry['after']={'type':'link','target':str(target)};self.save()
        temporary=path.with_name('.cedar-link-'+uuid.uuid4().hex)
        temporary.symlink_to(target);os.replace(temporary,path)
    def replace_owned_file(self,entry,data,mode=0o600):
        """A second journaled write, retaining every recoverable intermediate."""
        path=Path(entry['path'])
        if not entry.get('after') or not same(info(path),entry['after']):raise Refused('Integration changed during preparation; later edits preserved.')
        entry.setdefault('intermediate',[]).append(entry['after'])
        entry['after']={'type':'file','sha256':hashlib.sha256(data).hexdigest(),'mode':mode};self.save()
        atomic(path,data,mode)
    def commit(self):self.stage('commit')

def check_restore_journal(journal):
    value=read_json(journal)
    if value.get('format')!=FORMAT:raise Refused('Unsupported recovery journal.')
    # Check EVERY entry before changing any. Keep later user edits untouched.
    for entry in value['files']:
        if entry.get('retainOnRestore'):continue
        now=info(Path(entry['path']))
        if same(now,entry['before']):continue
        if not any(same(now,record) for record in [entry['after'],*entry.get('intermediate',[])] if record):raise Refused('Later user edit preserved; review backup: '+entry['path'])
        if entry['before']['type']=='file' and digest(journal.parent/entry['backup'])!=entry['before']['sha256']:raise Refused('Recovery backup checksum mismatch.')
    return value

def restore_journal(journal):
    value=check_restore_journal(journal)
    for entry in reversed(value['files']):
        if entry.get('retainOnRestore'):continue
        path=Path(entry['path']);before=entry['before']
        if same(info(path),before):continue
        if before['type']=='file':
            atomic(path,(journal.parent/entry['backup']).read_bytes(),before['mode'])
            os.utime(path,ns=(before['mtime_ns'],before['mtime_ns']))
        elif before['type']=='link':
            secure_parent(path);tmp=path.with_name('.cedar-restore-'+uuid.uuid4().hex);tmp.symlink_to(before['target']);os.replace(tmp,path)
        elif before['type']=='absent':path.unlink(missing_ok=True)
        else:raise Refused('Unsupported original file type.')
        if not same(info(path),before):raise Refused('Restoration verification failed.')
    value['stage']='restored';write_json(journal,value)
    return value

def release_in_use():
    from portable_providers import processes, qs_instances
    base=paths()['data']/'releases'
    rows=processes({'qs', 'quickshell'})
    if not rows:return False
    if any(str(base) in arg for row in rows for arg in row['argv']):return True
    # A current-release symlink or named profile need not expose the resolved
    # release path in argv. Quickshell's own instance registry resolves it.
    return any(Path(row.get('config_path', '/unavailable')).resolve().is_relative_to(base)
               for row in qs_instances())

def installed():
    current=paths()['data']/'current'
    if not current.is_symlink():raise Refused('No versioned CEDAR installation is selected.')
    root=current.resolve()
    if root.parent!=paths()['data']/'releases':raise Refused('Current release points outside the owned release store.')
    verify_tree(root,read_json(root/'release-files.json'))
    return root

def session_inventory():
    result={'quickshell':[], 'lock':'Not Tested', 'providers':{}, 'hyprland':'Unavailable Here'}
    if shutil.which('hyprctl'):
        try:
            from portable_providers import compositor_locked
            result['lock']='locked' if compositor_locked() else 'unlocked'
            result['hyprland']='Ready'
        except (Refused,ValueError,subprocess.TimeoutExpired):pass
    if shutil.which('qs'):
        try:result['quickshell']=json.loads(command(['qs','list','--all','-j']))
        except (Refused,ValueError):pass
    # Ownership discovery is read-only and retains raw process details locally.
    for service in ['org.freedesktop.Notifications','org.freedesktop.secrets']:
        try:
            command(['busctl','--user','status',service],timeout=5);result['providers'][service]='Owned'
        except (Refused,OSError,subprocess.TimeoutExpired):result['providers'][service]='Not Tested'
    return result

def ensure_unlocked():
    from portable_providers import processes, compositor_locked
    graphical = bool(processes({'hyprland'}))
    if graphical and compositor_locked():
        raise Refused('Desktop lock is active; operation deferred until unlock.')
    if graphical and release_in_use():
        # Use explicit running source paths, not Quickshell name discovery.
        from portable_providers import qs_instances, qs_ipc
        for row in qs_instances():
            source = Path(row.get('config_path', '/unavailable'))
            if source.is_relative_to(paths()['data']/'releases') and qs_ipc(source, 'shell', 'isLocked') != 'false':
                raise Refused('CEDAR is locking or locked; operation deferred.')


def session_backend(adapter='auto'):
    import omarchy_session, portable_session
    if portable_session.active(): return portable_session
    if omarchy_session.active(): return omarchy_session
    if adapter == 'omarchy': return omarchy_session
    if adapter == 'auto' and shutil.which('qs'):
        from portable_providers import qs_instances
        upstream = Path(os.environ.get('OMARCHY_PATH', '/usr/share/omarchy'))/'shell/shell.qml'
        try:
            if any(Path(r.get('config_path', '/unavailable')).resolve() == upstream.resolve() for r in qs_instances()): return omarchy_session
        except (Refused, OSError, ValueError, subprocess.SubprocessError): pass
    return portable_session


def session_active():
    import omarchy_session, portable_session
    return omarchy_session.active() or portable_session.active()

def capabilities(root):
    manifest=read_json(root/'data/dependencies.json');out=[]
    for row in manifest['commands']:
        if row.get('scope') in ('development', 'omarchy-adapter'): continue
        out.append({'id':row['command'],'status':'Ready' if shutil.which(row['command']) else 'Needs Setup', 'purpose':row['feature'],'required':row['status']=='required','scope':row.get('scope','feature'),'package':row.get('archPackage')})
    for row in manifest['pythonModules']:
        r=subprocess.run([sys.executable,'-c',row.get('probe', 'import '+row['name'])],capture_output=True)
        out.append({'id':row['name'],'status':'Ready' if not r.returncode else 'Needs Setup','purpose':row['feature'],'required':row['status']=='required','scope':row.get('scope','feature'),'package':row.get('archPackage')})
    for row in manifest.get('fonts', []):
        family = ''
        if shutil.which('fc-match'):
            family = command(['fc-match', '--format=%{family}', row['family']], timeout=5)
        out.append({'id':row['family'], 'status':'Ready' if row['family'].lower() in family.lower() else 'Needs Setup',
                    'purpose':'Display font; readable fallback: '+row['fallback'], 'required':False, 'scope':'font', 'package':row.get('archPackage')})
    return out

def validate_imports(root):
    """Load the installed runtime rather than guessing compatibility from packages."""
    with tempfile.TemporaryDirectory(prefix='cedar-imports-') as temp:
        base=Path(temp);probe=base/'imports.qml'
        runtime=base/'runtime';runtime.mkdir(mode=0o700)
        svg=base/'image.svg'
        svg.write_text('<svg xmlns="http://www.w3.org/2000/svg" width="2" height="2"><rect width="2" height="2" fill="#101E19"/></svg>')
        imports='\n'.join('import '+r['name'] for r in read_json(root/'data/dependencies.json')['modules'])
        probe.write_text(imports+'\nShellRoot { property var svg: Image { source: '+json.dumps(svg.as_uri())+' } Timer { interval: 200; running: true; onTriggered: { if (svg.status === Image.Ready) console.log("CEDAR_IMPORTS_OK"); else console.error("SVG image support unavailable"); Qt.quit(); } } }\n')
        env={**os.environ,'CEDAR_TEST':'1','CEDAR_LOCAL_ONLY':'1','QT_QPA_PLATFORM':'offscreen','QT_QPA_PLATFORMTHEME':'basic','QT_QUICK_CONTROLS_STYLE':'Basic','XDG_RUNTIME_DIR':str(runtime),'XDG_CONFIG_HOME':str(base/'config'),'XDG_STATE_HOME':str(base/'state')}
        result=subprocess.run(['qs','-p',str(probe)],capture_output=True,text=True,timeout=15,env=env)
        output=result.stdout+result.stderr
        if result.returncode or 'CEDAR_IMPORTS_OK' not in output:
            raise Refused('Existing Quickshell/Qt lacks a required import or image plugin. Its runtime was not replaced. Review cedar doctor and the dependency manifest. Details: '+output[-1500:])


def validate(root):
    required=['shell.qml','Config.qml','Theme.qml','data/branding.json','data/plugins.json','data/dependencies.json','scripts/distribution.py']
    for name in required:
        if not (root/name).is_file():raise Refused('Missing release file: '+name)
    plugins=read_json(root/'data/plugins.json')
    for plugin in plugins['plugins']:
        for file in plugin['files']:
            if not (root/file).is_file():raise Refused('Plugin artifact missing: '+file)
    if shutil.which('qs'):
        validate_imports(root)
        for test in ['check_navigation.py','check_identity.py','check_trailwatch.py','check_portable_ui.py']:
            command([sys.executable,str(root/'tests'/test)],timeout=60)
        return 'Offscreen components validated; native Wayland/PAM are Not Tested.'
    return 'Not Tested: Quickshell missing; installation only, preview/activation unavailable.'

def plan_install(root):
    source=list(files(root));size=sum(p.stat().st_size for p,_ in source)
    version=(root/'VERSION').read_text().strip()
    if not __import__('re').fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+(?:-[a-z0-9.]+)?',version):raise Refused('Invalid version identifier.')
    fingerprint=hashlib.sha256(''.join(str(rel)+digest(p) for p,rel in source).encode()).hexdigest()[:16]
    release=paths()['data']/'releases'/(version+'-'+fingerprint)
    return {'action':'Install Only','version':version,'release':str(release),'bytes':size,'packages':[],
            'files':'Complete first-party source and assets, recovery tooling and cedar command',
            'desktopChanges':[], 'network':'None. External integrations default off.', 'activation':'Separate; no running provider will be stopped.'}

def approve(plan,noninteractive=False):
    print(json.dumps(plan,indent=2))
    if noninteractive:return
    if not sys.stdin.isatty():raise Refused('No terminal for approval. Use the specific --approve-install-only flag after reviewing --plan.')
    if input('Apply this plan? [y/N] ').strip().lower() not in ('y','yes'):raise Refused('Canceled. No installation changes made.')

def installation_next_steps():
    launcher=__import__('shlex').quote(str(paths()['bin']))
    print('\nNext: open the isolated preview window:')
    print('  '+launcher+' preview')
    print('Inspect local health:')
    print('  '+launcher+' doctor')
    print('Try the desktop with automatic Hyprland / Noctalia provider detection:')
    print('  '+launcher+' try')
    print('The preview is a separate window; your existing desktop remains running.')

def install(root,approved=False,plan_only=False):
    plan=plan_install(root)
    if plan_only:print(json.dumps(plan,indent=2));return
    approve(plan,approved)
    with exclusive():
        if session_active():raise Refused('Restore the active CEDAR desktop session before installing another release.')
        destination=Path(plan['release']);current=paths()['data']/'current';binary=paths()['bin']
        recovery=paths()['data']/'recovery/distribution.py'
        session_recovery=paths()['data']/'recovery/omarchy_session.py'
        provider_recovery=paths()['data']/'recovery/omarchy_providers.py'
        portable_recovery=[paths()['data']/('recovery/'+name) for name in ('portable_session.py','portable_providers.py')]
        if binary.exists() or binary.is_symlink():
            if not binary.is_file() or b'# CEDAR distribution launcher' not in binary.read_bytes():raise Refused('The cedar command is already owned elsewhere. Existing installation preserved.')
        if current.exists() and not current.is_symlink():raise Refused('Unmanaged current-release entry exists.')
        if current.is_symlink() and current.resolve().parent!=destination.parent:raise Refused('Unmanaged current-release link exists.')
        if current.is_symlink() and current.resolve()==destination and binary.is_file() and recovery.is_file():
            verify_tree(destination,read_json(destination/'release-files.json'))
            print('This candidate is already installed. No files or recovery checkpoints changed.')
            installation_next_steps()
            return
        if current.is_symlink():
            ensure_unlocked()
            if release_in_use():raise Refused('This release is in use. Close CEDAR safely before switching versions; current files are preserved.')
        ancestor=destination.parent
        while not ancestor.exists():ancestor=ancestor.parent
        if shutil.disk_usage(ancestor).free < plan['bytes']*3+16*1024*1024:raise Refused('Insufficient space for staging and recovery.')
        validation=validate(root)
        tx=Transaction('install')
        try:
            tx.stage('plan');entries={str(p):tx.backup(p) for p in [current,binary,recovery,session_recovery,provider_recovery,*portable_recovery]}
            for p in (recovery,session_recovery,provider_recovery,*portable_recovery):entries[str(p)]['retainOnRestore']=True
            tx.save();tx.stage('back-up')
            destination.parent.mkdir(parents=True,exist_ok=True,mode=0o700)
            if not destination.exists():
                temporary=Path(tempfile.mkdtemp(prefix='.prepare-',dir=destination.parent))
                inventory={}
                for file,rel in files(root):
                    target=temporary/rel;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(file,target)
                    inventory[str(rel)]={'sha256':digest(target),'mode':stat.S_IMODE(target.stat().st_mode)}
                write_json(temporary/'release-files.json',inventory);verify_tree(temporary,inventory)
                tx.record['release']=str(destination);tx.save();tx.stage('prepare');os.replace(temporary,destination)
            else:verify_tree(destination,read_json(destination/'release-files.json'))
            tx.stage('validate')
            # Recheck immediately before replacing any installed helper. A
            # refused upgrade must not temporarily overwrite live recovery code.
            if current.is_symlink():
                ensure_unlocked()
                if release_in_use():raise Refused('This release is in use. Close CEDAR safely before switching versions; current files are preserved.')
            for p in portable_recovery: tx.apply_file(entries[str(p)], (root/'scripts'/p.name).read_bytes(), 0o700)
            tx.apply_file(entries[str(provider_recovery)],(root/'scripts/omarchy_providers.py').read_bytes(),0o700)
            tx.apply_file(entries[str(session_recovery)],(root/'scripts/omarchy_session.py').read_bytes(),0o700)
            tx.apply_file(entries[str(recovery)],(root/'scripts/distribution.py').read_bytes(),0o700)
            launcher='#!/bin/sh\n# CEDAR distribution launcher\nexec python3 '+__import__('shlex').quote(str(recovery))+' "$@"\n'
            tx.apply_file(entries[str(binary)],launcher.encode(),0o700)
            tx.apply_link(entries[str(current)],destination)
            tx.stage('confirm');tx.commit()
            print('Files installed and verified. '+validation+' Desktop activation: not performed.')
            print('Recovery: '+__import__('shlex').join(['python3',str(recovery),'restore']))
            installation_next_steps()
        except BaseException:
            restore_journal(tx.path);raise

def recover_latest(action=None):
    records=sorted((paths()['state']/'transactions').glob('*/journal.json'),reverse=True)
    for journal in records:
        row=read_json(journal)
        if row['stage']!='restored' and (action is None or row['action']==action):
            ensure_unlocked();
            if release_in_use():raise Refused('Release is still running; restoration deferred.')
            restore_journal(journal);print('Recorded changes restored. User preferences and package installations retained.');return
    raise Refused('No unrestored transaction found.')

def preview(root):
    if not shutil.which('qs'):raise Refused('Quickshell is missing. Run cedar dependencies for the package plan.')
    with tempfile.TemporaryDirectory(prefix='cedar-preview-') as temp:
        base=Path(temp);runtime=base/'runtime';runtime.mkdir(mode=0o700)
        env={**os.environ,'CEDAR_TEST':'1','CEDAR_LOCAL_ONLY':'1','XDG_CONFIG_HOME':str(base/'config'),'XDG_STATE_HOME':str(base/'state'),'XDG_CACHE_HOME':str(base/'cache')}
        # A FloatingWindow only. No session lock, wallpaper, notifications or layer surfaces.
        subprocess.run(['qs','-p',str(root/'preview.qml')],env=env,check=True)

def missing_packages(root,include_recommended=False):
    manifest = read_json(root/'data/dependencies.json')
    rows = {r['command']: r for r in manifest['commands']}
    rows.update({r['name']: r for r in manifest['pythonModules']})
    rows.update({r['family']: r for r in manifest.get('fonts', [])})
    packages = set()
    for capability in capabilities(root):
        row = rows.get(capability['id'], {})
        needed = row.get('status') in ('required', 'feature-required')
        recommended = include_recommended and row.get('status') == 'recommended'
        if (needed or recommended) and row.get('autoInstall', True) and capability['status'] != 'Ready' and capability.get('package'):
            packages.add(capability['package'])
    if shutil.which('qs'):
        # A compatible local/isolated build need not be registered with pacman.
        # Never replace somebody else's working Qt/Quickshell to satisfy -Q.
        validate_imports(root)
    else:
        packages.update(row.get('archPackage') or row.get('package') for row in manifest['modules'] + manifest.get('imageFormats', []) if row.get('archPackage') or row.get('package'))
    return sorted(packages)


def package_host(root):
    """Explicitly reviewed package systems, independent of desktop adapters."""
    try: release=__import__('platform').freedesktop_os_release()
    except OSError: release={}
    distro=release.get('ID', 'unknown')
    machine=__import__('platform').machine()
    for backend in read_json(root/'data/dependencies.json')['packageManagement']['backends']:
        if distro in backend['distributions'] and machine in backend['architectures']:
            return {**backend, 'distribution':distro, 'displayName':backend['distributions'][distro]}
    raise Refused('Automatic package setup is not reviewed for this distribution/architecture ('+distro+'/'+machine+'). '
                  'Install the missing dependencies with your own package manager, then rerun bash ./install.sh. No package changes made.')


def check_package_plan(plan):
    if plan['backend'] != 'pacman':raise Refused('Unrecognized package backend; no package changes made.')
    if not shutil.which('pacman') or not shutil.which('sudo'):
        raise Refused('Automatic package setup needs pacman and sudo. Install the listed dependencies through your distribution tools instead.')
    if Path('/var/lib/pacman/db.lck').exists():raise Refused('The package manager is busy; its lock will not be removed.')
    for package in plan['packages']:
        try: command(['pacman','-Si',package])
        except (Refused, subprocess.SubprocessError) as error:
            raise Refused('Package '+package+' could not be verified in your configured repositories. '
                          'No repositories were added or packages changed. Details: '+str(error)) from error


def install_packages(plan,approve_upgrade=False):
    # Use the exact disclosed plan, not a fresh dependency scan after approval.
    if not plan['packages']:return
    if not approve_upgrade:raise Refused('A full supported upgrade requires separate consent. Review and explicitly add --approve-system-upgrade, or manage dependencies yourself.')
    check_package_plan(plan)
    with exclusive():
        tx=Transaction('packages');tx.record['packages']=[{'command':['pacman','-Syu','--needed',*plan['packages']],'result':'pending','reversible':False}];tx.save()
        r=subprocess.run(['sudo','pacman','-Syu','--needed',*plan['packages']])
        tx.record['packages'][0]['result']='succeeded' if r.returncode==0 else 'failed';tx.save()
        if r.returncode:raise Refused('Package operation failed/canceled. No desktop configuration changed.')
        tx.commit()


def package_plan(root,approve_packages=False,approve_upgrade=False,include_recommended=False):
    packages=missing_packages(root,include_recommended)
    plan={'packages':packages,'includeRecommended':include_recommended,
          'providerChanges':'No replacement desktop/audio/network providers or repositories are added. A full upgrade may update existing system packages.',
          'operation':'None needed'}
    if packages:
        print('Missing software from the CEDAR dependency manifest: '+', '.join(packages))
        host=package_host(root)
        plan.update(backend=host['id'],distribution=host['displayName'],source=host['source'],operation='sudo pacman -Syu --needed (includes a full system upgrade)')
        # Read-only checks happen before offering an unsupported privileged plan.
        check_package_plan(plan)
    print(json.dumps(plan,indent=2))
    if approve_packages:install_packages(plan,approve_upgrade)
    return plan

def doctor(root):
    result={'format':1,'dependencies':capabilities(root),'session':session_inventory(),'qml':'Not Tested','plugins':[],'release':'Development candidate; not certified'}
    sys.path.insert(0,str(root/"scripts"))
    from adapters import inspect, startup_inventory
    result['adapters']=inspect(result['session']['quickshell'],read_json(root/'data/compatibility.json'))
    result['startup']=startup_inventory(paths()['config'].parent)
    try:result['qml']=validate(root)
    except (Refused,subprocess.TimeoutExpired) as e:result['qml']='Failed: '+str(e)
    for p in read_json(root/'data/plugins.json')['plugins']:
        if p.get('scope') == 'omarchy-adapter':
            result['plugins'].append({'id':p['id'],'state':'Not Tested','reason':'Optional Omarchy compatibility adapter; not needed on Hyprland or Noctalia'})
            continue
        missing=[d for d in result['dependencies'] if d['id'] in p['dependencies'] and d['status']!='Ready']
        result['plugins'].append({'id':p['id'],'state':'Needs Setup' if missing or p.get('external') else 'Not Tested','reason':'Live services/hardware and lifecycle not validated' if not missing else 'Missing: '+', '.join(d['id'] for d in missing)})
    print(json.dumps(result,indent=2));return result

def safe_extract(archive,destination):
    with tarfile.open(archive,'r:gz') as tar:
        members=tar.getmembers();total=0;seen=set()
        for member in members:
            path=Path(member.name)
            if path.is_absolute() or '..' in path.parts or member.name in seen or not (member.isdir() or member.isfile()):raise Refused('Unsafe release archive entry.')
            seen.add(member.name);total+=member.size
            if total>512*1024*1024 or len(members)>10000:raise Refused('Release archive exceeds limits.')
        tar.extractall(destination,filter='data')

def update(archive,signature,key,approved=False):
    # No automatic download, trust-on-first-use or unsigned upgrade.
    if not all((archive,signature,key)):raise Refused('Usage: cedar update ARCHIVE --signature SIGNATURE --trusted-key PUBLIC_KEY. No publisher signing identity is configured yet.')
    if not shutil.which('openssl'):raise Refused('OpenSSL is required to verify the selected publisher key.')
    command(['openssl','dgst','-sha256','-verify',str(key),'-signature',str(signature),str(archive)])
    with tempfile.TemporaryDirectory(prefix='cedar-update-') as temp:
        safe_extract(archive,Path(temp));candidate=Path(temp)/'cedar-shell'
        # Caller selects an independently verified public key; checksum alone is insufficient.
        print('Signature verified against the explicitly selected key. Review release notes and new permissions before proceeding.')
        print((candidate/'CHANGELOG.md').read_text())
        ensure_unlocked();install(candidate,approved)

def uninstall(approved=False):
    if session_active():raise Refused('Run cedar restore to leave the active desktop session before uninstalling.')
    approve({'action':'Uninstall program entry points','preserve':['preferences','plugins','themes','backups','release source','recovery tool','shared packages'],'desktop':'Restore recorded integration first; never kill a session'},approved)
    with exclusive():
        ensure_unlocked()
        if release_in_use():raise Refused('Release is still running; restoration deferred.')
        journals=[];simulated={}
        for journal in sorted((paths()['state']/'transactions').glob('*/journal.json'),reverse=True):
            row=read_json(journal)
            if row['action']!='install' or row['stage']=='restored':continue
            if row.get('format')!=FORMAT:raise Refused('Unsupported recovery journal.')
            journals.append(journal)
            # Preflight the complete restoration chain before its first mutation.
            # Each older transaction sees the state the newer one would restore.
            for entry in reversed(row['files']):
                if entry.get('retainOnRestore'):continue
                name=entry['path'];now=simulated.get(name)
                if now is None:now=info(Path(name))
                if not same(now,entry['before']):
                    if not entry['after'] or not same(now,entry['after']):raise Refused('Later user edit preserved; review backup: '+name)
                    if entry['before']['type']=='file' and digest(journal.parent/entry['backup'])!=entry['before']['sha256']:raise Refused('Recovery backup checksum mismatch.')
                simulated[name]=entry['before']
        if not journals:raise Refused('No unrestored installation found.')
        for journal in journals:restore_journal(journal)
        print('Program entry points restored. Release files/recovery retained for safe manual storage review; no purge performed.')

def main(argv=None):
    parser=argparse.ArgumentParser(description='CEDAR: install, preview and recover without replacing your desktop implicitly.')
    parser.add_argument('action',nargs='?',default='doctor',choices=['install','preview','try','activate','keep','status','restore','rollback','doctor','update','uninstall','ipc','dependencies','session-login'])
    parser.add_argument('arguments',nargs='*');parser.add_argument('--source',type=Path,default=ROOT)
    parser.add_argument('--plan',action='store_true');parser.add_argument('--approve-install-only',action='store_true')
    parser.add_argument('--approve-packages',action='store_true');parser.add_argument('--approve-system-upgrade',action='store_true')
    parser.add_argument('--include-recommended',action='store_true',help='Include recommended fonts in the explicit dependencies plan; not required to install CEDAR.')
    parser.add_argument('--approve-uninstall',action='store_true');parser.add_argument('--signature',type=Path);parser.add_argument('--trusted-key',type=Path)
    parser.add_argument('--adapter', choices=['auto','hyprland','noctalia','omarchy'], default='auto')
    parser.add_argument('--approve-trial', action='store_true')
    parser.add_argument('--approve-omarchy-trial',action='store_true');parser.add_argument('--approve-login',action='store_true')
    args=parser.parse_args(argv)
    if os.getuid()==0:raise Refused('Run CEDAR as your ordinary user, never root.')
    if args.action=='install':install(args.source.resolve(),args.approve_install_only,args.plan)
    elif args.action=='dependencies':package_plan(args.source.resolve() if (args.source/'data/dependencies.json').is_file() else installed(),args.approve_packages,args.approve_system_upgrade,args.include_recommended)
    elif args.action in ('restore','rollback'):
        if session_active():
            if args.action=='rollback':raise Refused('Run cedar restore before switching releases.')
            session_backend().request_restore();return
        with exclusive():recover_latest('install')
    elif args.action=='uninstall':uninstall(args.approve_uninstall)
    elif args.action=='update':update(Path(args.arguments[0]) if args.arguments else None,args.signature,args.trusted_key)
    elif args.action in ('try','activate','keep','status'):
        backend=session_backend(args.adapter)
        if args.action=='try':
            if backend.__name__ == 'portable_session': backend.trial(installed(),args.approve_trial, expected_adapter=args.adapter)
            else: backend.trial(installed(),args.approve_trial or args.approve_omarchy_trial)
        elif args.action=='status':
            row=backend.read_record()
            print(json.dumps({k:row.get(k) for k in ('stage','login','deadline','error')} if row else {'stage':'not active'},indent=2))
        else:backend.keep(args.action=='activate',args.approve_login)
    elif args.action=='session-login':session_backend(args.adapter).login()
    elif args.action=='ipc':os.execvp('qs',['qs','-p',str(installed()/'shell.qml'),'ipc','call',*args.arguments])
    else:
        root=args.source.resolve() if (args.source/'shell.qml').exists() else installed()
        if args.action=='preview':preview(root)
        else:doctor(root)

if __name__=='__main__':
    try:main()
    except (Refused,OSError,ValueError,subprocess.SubprocessError) as error:print('CEDAR: '+str(error),file=sys.stderr);sys.exit(1)
