#!/usr/bin/env python3
"""Read installed desktop apps and apply explicit per-user default associations."""
import json,os,shlex,shutil,sys,time,uuid
import distribution as storage
from pathlib import Path
from gi.repository import Gio, GLib
try:
    from gi.repository import GioUnix
    DesktopAppInfo = GioUnix.DesktopAppInfo
except ImportError:
    DesktopAppInfo = Gio.DesktopAppInfo  # GLib versions before the namespace split.
from desktop_runtime import omarchy

ROLES=json.loads((Path(__file__).resolve().parents[1]/'data/default-apps.json').read_text())
def apps():
    return {a.get_id():a for a in Gio.AppInfo.get_all() if a.get_id() and a.should_show()}
def snapshot(installed=None):
    installed=dict(apps() if installed is None else installed);rows=[]
    for role in ROLES:
        ids=[a.get_id() if (a:=Gio.AppInfo.get_default_for_type(t,False)) else '' for t in role['types']]
        current=ids[0] if ids else ''
        if current and current not in installed:
            selected=Gio.AppInfo.get_default_for_type(role['types'][0],False)
            if selected:installed[current]=selected
        recommendations=[]
        for key,app in installed.items():
            cats=set((app.get_categories() or '').split(';')) if isinstance(app,DesktopAppInfo) else set()
            if set(app.get_supported_types() or []) & set(role['types']) or cats & set(role['categories']):recommendations.append(key)
        rows.append({**role,'current':current,'mixed':len(set(ids))>1,'recommended':recommendations})
    catalog=[]
    for key, app in installed.items():
        description=app.get_description() or ''
        keywords=list(app.get_keywords() or []) if isinstance(app,DesktopAppInfo) else []
        label=app.get_display_name() or key
        catalog.append({'id':key,'label':label,'description':description,'keywords':keywords,
                        'visible':app.should_show(), 'icon':app.get_icon().to_string() if app.get_icon() else '',
                        'search':(' '.join([label,key,description,*keywords])).casefold()})
    return {'roles':rows,'apps':sorted(catalog,key=lambda a:(a['label'].casefold(),a['id']))}


def launch(app_id, arguments=()):
    # Resolve immediately before launching. GIO implements Exec field codes,
    # Terminal, Path and D-Bus activation; never execute a catalog's cached Exec.
    if not isinstance(app_id,str) or not app_id.endswith('.desktop') or '/' in app_id:
        raise ValueError('Invalid desktop application ID.')
    try: app=DesktopAppInfo.new(app_id)
    except TypeError: raise ValueError('That application is no longer installed or its desktop entry cannot be read.') from None
    if app is None: raise ValueError('That application is no longer installed.')
    uris=[Gio.File.new_for_commandline_arg(arg).get_uri() for arg in arguments]
    if not app.launch_uris(uris, None): raise RuntimeError('The application did not launch.')
    return {'launched':app_id}


def watch():
    """One catalog, one monitor. Hidden changes mark dirty without a rescan.

    Gio rearms AppInfoMonitor when get_all() reads the catalog. Connect before
    the first read; a queued change after that read creates another revision.
    Input/output are bounded JSON lines, no commands or environment dumps.
    """
    generation=uuid.uuid4().hex
    state={'visible':False,'dirty':True,'pending':0,'seq':0,'catalog':None}
    loop=GLib.MainLoop()
    def publish():
        state['pending']=0
        if not state['visible']: return False
        if state['dirty']:
            state['dirty']=False
            state['catalog']=snapshot()
        state['seq']+=1
        payload=json.dumps({'schema':1,'generation':generation,'sequence':state['seq'],
                            'kind':'snapshot','data':state['catalog']},ensure_ascii=False)
        if len(payload.encode())>4*1024*1024: raise ValueError('Application catalog exceeds the safe response limit.')
        print(payload,flush=True)
        return False
    def schedule():
        if state['visible'] and not state['pending']: state['pending']=GLib.timeout_add(80,publish)
    def changed(*_):
        state['dirty']=True
        schedule()
    monitor=Gio.AppInfoMonitor.get()
    handler=monitor.connect('changed',changed)
    # Nonblocking fd reads avoid losing buffered lines or blocking the GLib loop
    # on an incomplete request. No unbounded readline() on a pipe.
    os.set_blocking(sys.stdin.fileno(),False)
    buffer=bytearray()
    def read_request(fd,condition):
        chunk=os.read(fd,4096)
        if not chunk: loop.quit(); return False
        buffer.extend(chunk)
        if len(buffer)>65536: loop.quit(); return False
        while b'\n' in buffer:
            line,_,tail=buffer.partition(b'\n');buffer[:]=tail
            try:
                request=json.loads(line)
                if request.get('action')=='visible': state['visible']=request.get('value') is True
                elif request.get('action')=='refresh': state['dirty']=True
                else: continue
                schedule()
            except (ValueError,AttributeError): loop.quit(); return False
        return True
    channel=GLib.io_add_watch(sys.stdin.fileno(),GLib.IO_IN|GLib.IO_HUP,read_request)
    try: loop.run()
    finally:
        monitor.disconnect(handler)
        if state['pending']: GLib.source_remove(state['pending'])

def apply(role_id,app_id):
    role=next((r for r in ROLES if r['id']==role_id),None)
    if role is None:raise ValueError('Unknown default application category.')
    app=apps().get(app_id)
    if app is None:raise ValueError('That application is no longer installed or available.')
    config=Path(os.environ.get('XDG_CONFIG_HOME',Path.home()/'.config'))
    # Unchanged associations are true no-ops: no backup, wrapper or MIME write.
    before={kind:(a.get_id() if (a:=Gio.AppInfo.get_default_for_type(kind,False)) else '') for kind in role['types']}
    pending=[kind for kind,value in before.items() if value!=app_id]
    target={'kind':'desktop-entry','id':app_id}
    if role['types'] and not pending:
        return {**snapshot(),'status':'unchanged','launchKey':role.get('launchKey',''),'launchTarget':target,
                'message':role['label']+' is already set to '+app.get_display_name()+'.'}
    state=Path(os.environ.get('XDG_STATE_HOME',Path.home()/'.local/state'))/'cedar'
    storage.private_directory(state)
    if role_id=='editor' and (state/'default-editor').is_symlink():
        raise ValueError('The editor wrapper is managed by another owner.')
    if mime_is_managed(config/'mimeapps.list'):
        raise ValueError('Default associations are managed or linked. Edit them through their existing owner.')
    # Keep a private recovery copy without replacing unrelated associations.
    mime=config/'mimeapps.list'
    if pending and mime.exists():
        backup=Path(os.environ.get('XDG_STATE_HOME',Path.home()/'.local/state'))/'cedar/default-app-backups'
        storage.private_directory(backup)
        storage.atomic(backup/(str(time.time_ns())+'-mimeapps.list'),mime.read_bytes())
        # Recovery copies are retained until explicitly reviewed and removed.
    changed=[]
    try:
        for kind in pending:
            if not app.set_as_default_for_type(kind):raise RuntimeError('Could not save '+kind)
            changed.append(kind)
        if role_id=='editor':
            # Desktop entries may need arguments (for example Flatpak). Preserve
            # their launch semantics and pass document paths through as argv.
            wrapper=Path(os.environ.get('XDG_STATE_HOME', Path.home()/'.local/state'))/'cedar/default-editor'
            content=('#!/bin/sh\nexec gtk-launch '+shlex.quote(app_id)+' "$@"\n').encode()
            storage.private_directory(wrapper.parent)
            if wrapper.is_symlink(): raise ValueError('The editor wrapper is managed by another owner.')
            if not wrapper.exists() or wrapper.read_bytes()!=content: storage.atomic(wrapper,content,0o700)
            if omarchy():
                dest=Path(os.environ.get('XDG_STATE_HOME', Path.home()/'.local/state'))/'omarchy/defaults/editor'
                if mime_is_managed(dest): raise ValueError('The existing editor setting is managed by another owner.')
                storage.atomic(dest,(str(wrapper)+'\n').encode())
    except Exception as e:
        raise RuntimeError(str(e)+(' Already updated: '+', '.join(changed)+'. Refresh to see the current defaults.' if changed else '')) from e
    result=snapshot()
    verified=next(r for r in result['roles'] if r['id']==role_id)
    if role['types'] and (verified['current']!=app_id or verified['mixed']):
        return {**result,'status':'partial','message':'Some associations were not saved. Current defaults have been read back.'}
    return {**result,'status':'complete','launchKey':role.get('launchKey',''),'launchTarget':target,
            'message':role['label']+' set to '+app.get_display_name()+'.'}


def mime_is_managed(path):
    return path.is_symlink() or any(parent.is_symlink() for parent in path.parents)

def main(request):
    if request.get('action')=='snapshot':return snapshot()
    if request.get('action')=='launch':return launch(request.get('id'),request.get('arguments',[]))
    if request.get('action')=='apply':return apply(request.get('role'),request.get('app'))
    raise ValueError('Unknown default-app action.')
if __name__=='__main__':
    try:
        if sys.argv[1:2]==['--watch']: watch()
        elif sys.argv[1:2]==['--launch']: launch(sys.argv[2],sys.argv[3:])
        else: print(json.dumps({'ok':True,'data':main(json.loads(sys.stdin.readline(65537)))}))
    except Exception as e:
        if sys.argv[1:2]==['--launch']:
            print('CEDAR: '+str(e),file=sys.stderr);sys.exit(1)
        print(json.dumps({'ok':False,'error':str(e)}))
