#!/usr/bin/env python3
"""Read installed desktop apps and apply explicit per-user default associations."""
import json,os,shlex,shutil,sys,time
from pathlib import Path
from gi.repository import Gio
from desktop_runtime import omarchy

ROLES=json.loads((Path(__file__).resolve().parents[1]/'data/default-apps.json').read_text())
def apps():
    return {a.get_id():a for a in Gio.AppInfo.get_all() if a.get_id() and a.should_show()}
def snapshot():
    installed=apps();rows=[]
    for role in ROLES:
        ids=[a.get_id() if (a:=Gio.AppInfo.get_default_for_type(t,False)) else '' for t in role['types']]
        current=ids[0] if ids else ''
        if current and current not in installed:
            selected=Gio.AppInfo.get_default_for_type(role['types'][0],False)
            if selected:installed[current]=selected
        recommendations=[]
        for key,app in installed.items():
            cats=set((app.get_categories() or '').split(';')) if isinstance(app,Gio.DesktopAppInfo) else set()
            if set(app.get_supported_types() or []) & set(role['types']) or cats & set(role['categories']):recommendations.append(key)
        rows.append({**role,'current':current,'mixed':len(set(ids))>1,'recommended':recommendations})
    return {'roles':rows,'apps':sorted([{'id':key,'label':a.get_display_name(),'icon':a.get_icon().to_string() if a.get_icon() else ''} for key,a in installed.items()],key=lambda a:a['label'].casefold())}
def apply(role_id,app_id):
    role=next((r for r in ROLES if r['id']==role_id),None)
    if role is None:raise ValueError('Unknown default application category.')
    app=apps().get(app_id)
    if app is None:raise ValueError('That application is no longer installed or available.')
    config=Path(os.environ.get('XDG_CONFIG_HOME',Path.home()/'.config'))
    # Keep a recovery copy without replacing other associations or user overrides.
    mime=config/'mimeapps.list'
    if mime.exists():
        backup=Path(os.environ.get('XDG_STATE_HOME',Path.home()/'.local/state'))/'cedar/default-app-backups'
        backup.mkdir(parents=True,exist_ok=True)
        shutil.copy2(mime,backup/(str(time.time_ns())+'-mimeapps.list'))
        for old in sorted(backup.glob('*-mimeapps.list'))[:-20]:old.unlink()
    changed=[]
    try:
        for kind in role['types']:
            if not app.set_as_default_for_type(kind):raise RuntimeError('Could not save '+kind)
            changed.append(kind)
        if role_id=='editor':
            # Desktop entries may need arguments (for example Flatpak). Preserve
            # their launch semantics and pass document paths through as argv.
            wrapper=Path(os.environ.get('XDG_STATE_HOME', Path.home()/'.local/state'))/'cedar/default-editor'
            wrapper.parent.mkdir(parents=True,exist_ok=True)
            temp=wrapper.with_name('.default-editor.tmp')
            temp.write_text('#!/bin/sh\nexec gtk-launch '+shlex.quote(app_id)+' "$@"\n')
            temp.chmod(0o700);os.replace(temp,wrapper)
            if omarchy():
                dest=Path(os.environ.get('XDG_STATE_HOME', Path.home()/'.local/state'))/'omarchy/defaults/editor'
                dest.parent.mkdir(parents=True,exist_ok=True)
                temp=dest.with_name('.editor.cedar');temp.write_text(str(wrapper)+'\n');os.replace(temp,dest)
    except Exception as e:
        raise RuntimeError(str(e)+(' Already updated: '+', '.join(changed)+'. Refresh to see the current defaults.' if changed else '')) from e
    return {**snapshot(),'launchKey':role.get('launchKey',''),'launchCommand':'gtk-launch '+app_id,'message':role['label']+' set to '+app.get_display_name()+'.'}
def main(request):
    if request.get('action')=='snapshot':return snapshot()
    if request.get('action')=='apply':return apply(request.get('role'),request.get('app'))
    raise ValueError('Unknown default-app action.')
if __name__=='__main__':
    try:print(json.dumps({'ok':True,'data':main(json.loads(sys.stdin.readline()))}))
    except Exception as e:print(json.dumps({'ok':False,'error':str(e)}))
