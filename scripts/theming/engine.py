"""Preview, approval, application and status orchestration; no daemon per adapter."""
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import time
from . import adapters,registry,tokens
from .transaction import Store, Conflict, file_op, run

DEFAULT={'enabled':False,'mode':'managed','preset':'cedar','variant':'dark','inherit':True,'apps':[],
         'overrides':{},'accent':'','fonts':False,'fontFamily':'JetBrainsMono Nerd Font','uiFont':'sans-serif','fontSize':11,
         'opacity':1.0,'radius':12,'iconTheme':'','wallpaper':False,'lockedAccent':False,'terminalPalette':{},'externalSource':''}

def settings(store):return {**DEFAULT,**store.json(store.config/'cedar/application-theming.json',{})}

def validate_options(value):
    if not isinstance(value,dict) or set(value)-set(DEFAULT):raise ValueError('Unknown application theme preference.')
    result={**DEFAULT,**value}
    if result['mode'] not in ('managed','external','independent'):raise ValueError('Unknown ownership mode.')
    if not isinstance(result['apps'],list) or any(a not in registry.REGISTRY for a in result['apps']):raise ValueError('Unknown application adapter.')
    if not isinstance(result['overrides'],dict) or any(a not in registry.REGISTRY for a in result['overrides']):raise ValueError('Unknown application override.')
    for v in result['overrides'].values():
        if not isinstance(v,dict) or set(v)-{'variant','accent','fonts','fontFamily','fontSize','opacity','iconTheme','terminalPalette'}:raise ValueError('Unsupported per-application override.')
        tokens.compile_theme({},v)
    for name in ('enabled','inherit','fonts','wallpaper','lockedAccent'):
        if not isinstance(result[name],bool):raise ValueError(name+' must be a boolean.')
    if not isinstance(result['externalSource'],str):raise ValueError('Invalid external palette path.')
    tokens.compile_theme({},result)
    return result

def resolve(store,options):
    if options['mode']=='external':
        path=Path(options['externalSource']).expanduser()
        if not path.is_absolute() or not path.is_file() or path.stat().st_size>1024*1024:raise ValueError('Choose a readable local JSON palette under 1 MiB.')
        raw=json.loads(path.read_text())
        if 'special' in raw: # pywal/wallust JSON exchange format
            colors=raw.get('colors',{});p={'name':'External palette','mode':options['variant'],'colors':{'background':raw['special']['background'],'text':raw['special']['foreground']}}
            for name,index in [('green',2),('teal',6),('amber',3),('ember',1),('blue',4),('violet',5)]:
                if 'color'+str(index) in colors:p['colors'][name]=colors['color'+str(index)]
            return p
        if not isinstance(raw,dict) or not isinstance(raw.get('colors',{}),dict):raise ValueError('External source must be a CEDAR or pywal-style JSON palette.')
        return raw
    if options['wallpaper']:
        desktop=store.json(store.config/'cedar/desktop.json',{})
        path=desktop.get('wallpaper','')
        if os.environ.get('CEDAR_ADAPTER')=='omarchy' or os.environ.get('CEDAR_OMARCHY_SESSION')=='1':
            current=Path(os.environ.get('XDG_STATE_HOME',store.home/'.local/state'))/'omarchy/current/background'
            if current.is_symlink():path=str(current.resolve())
        if not path:raise ValueError('No current wallpaper is available.')
        from .wallpaper import extract
        return extract(store,path,options['variant'],options['accent'] if options['lockedAccent'] else '')
    if options['inherit']:
        current=store.json(store.config/'cedar/theme.json',{})
        # Never feed our own compiled output back into compilation (light/dark must be reversible).
        if current and current.get('producer')!='uate':return current
    return tokens.preset(options['preset'])


def preview(store,options=None,detected=None,automatic=False):
    options=validate_options(options if options is not None else settings(store))
    applications=detected if detected is not None else registry.discover(store)
    by_id={a['id']:a for a in applications};palette=resolve(store,options) if options['enabled'] and options['mode']!='independent' else tokens.preset(options['preset'])
    compile_options={**options}
    if options['wallpaper'] and not options['lockedAccent'] and options['mode']=='managed':compile_options['accent']=''
    theme=tokens.compile_theme(palette,compile_options)
    ops=[];reports=[]
    if options['enabled'] and options['mode']=='managed':
        for id in dict.fromkeys(options['apps']):
            app=by_id[id]
            if not app['installed']:
                reports.append({'id':id,'status':'Not installed','detail':'No files changed.'});continue
            if app['capability']=='unsupported':
                reports.append({'id':id,'status':'Unsupported','detail':app['method']});continue
            local=tokens.compile_theme(palette,{**compile_options,**options['overrides'].get(id,{})})
            try:
                if not app['native'] and app['flatpaks'] and id!='gtk4':
                    reports.append({'id':id,'status':'Requires portal integration','detail':'Sandbox access was not changed. Native palette files are not exposed to Flatpak. Enable GTK 4 preferences and a compatible portal separately.'});continue
                generated=adapters.generate(store,id,local)
                for op in generated:
                    if op['kind']=='file':store.check(op['path'],True)
                ops.extend(generated)
                status='Needs manual selection' if app['capability']=='requires-integration' else 'Ready' if generated else 'Inherited preference only'
                detail=app['method']
                if id in ('qt5ct','qt6ct') and os.environ.get('QT_QPA_PLATFORMTHEME')!=id:status='Requires platform integration';detail+='; QT_QPA_PLATFORMTHEME is not '+id+'. CEDAR does not change the session environment.'
                reports.append({'id':id,'status':status,'detail':detail,'reload':app['reload']})
            except (OSError,ValueError,RuntimeError) as e:reports.append({'id':id,'status':'Blocked','detail':str(e)})
    # External Managed follows only the shell. Independent writes no appearance output.
    if options['enabled'] and options['mode']!='independent' and not (options['mode']=='managed' and options['inherit'] and not options['wallpaper']):
        shell={'name':theme['name'],'colors':theme['colors'],'tokens':theme['tokens'],'mode':theme['mode'],'producer':'uate'}
        ops.append(file_op(store,store.config/'cedar/theme.json',json.dumps(shell,indent=2)+'\n','cedar'))
    if not automatic:
        ops.append(file_op(store,store.config/'cedar/application-theming.json',json.dumps(options,indent=2)+'\n','preferences'))
    # Conflicting duplicate destinations must be resolved before any application changes.
    destinations={}
    for op in ops:
        key=op['kind']+':'+op['path']
        if key in destinations and destinations[key]['after']!=op['after']:raise Conflict('Two adapters disagree about '+op['path'])
        destinations[key]=op
    ops=list(destinations.values())
    owners=store.json(store.state/'ownership.json',{})
    for op in ops:
        owner=owners.get(op['kind']+':'+op['path'])
        # A deliberate shell palette change is the input event, not a lost ownership conflict.
        if owner and owner['after']!=op['before']:raise Conflict('User edit preserved: '+op['path'])
    review={'options':options,'operations':ops,'theme':theme,'reports':reports}
    review['id']=hashlib.sha256(json.dumps(review,sort_keys=True).encode()).hexdigest()
    return review


def reload_apps(reports):
    results=[]
    for report in reports:
        row=dict(report);kind=row.get('reload');id=row['id']
        if row['status']!='Ready':results.append(row);continue
        row['status']='Applied'
        row['restartRequired']=kind=='restart'
        if kind=='restart':row['detail']='Configuration applied; reopen the application.'
        elif kind=='watch':row['detail']='Configuration applied; the application normally watches this file. Live appearance is not confirmed.'
        elif kind in ('manual-reload','manual-select'):row['detail']='Configuration applied; use the application’s reload/theme command.'
        elif kind in ('live','portal'):row['detail']='Appearance preference updated; supporting applications receive it through the desktop.'
        elif kind=='signal':
            count=0
            for proc in Path('/proc').glob('[0-9]*'):
                try:
                    if proc.stat().st_uid==os.getuid() and (proc/'comm').read_text().strip()=='kitty':os.kill(int(proc.name),signal.SIGUSR1);count+=1
                except (OSError,ValueError):pass
            row['detail']='Reload requested for '+str(count)+' Kitty processes; visual result not confirmed.'
        elif kind=='hypr-reload':
            try:
                run(['hyprctl','reload'])
                errors=run(['hyprctl','configerrors'])
                if errors and errors!='ok':raise RuntimeError(errors)
                row['detail']='Hyprland reload accepted; border appearance is not visually verified.'
            except (OSError,RuntimeError,subprocess.SubprocessError) as e:row['detail']='Configuration saved; reload needs attention: '+str(e);row['restartRequired']=True
        elif kind=='reload':
            argv=['makoctl','reload'] if id=='mako' else ['swaync-client','-rs']
            try:run(argv);row['detail']='Reload accepted; visual result not confirmed.'
            except (OSError,RuntimeError,subprocess.SubprocessError) as e:row['detail']='Files applied; reload unavailable: '+str(e);row['restartRequired']=True
        results.append(row)
    return results


def apply(store,options,expected,detected=None,automatic=False):
    plan=preview(store,options,detected,automatic)
    if plan['id']!=expected:raise Conflict('The preview is stale. Preview the changes again.')
    blocked=[r for r in plan['reports'] if r['status']=='Blocked']
    if blocked:raise Conflict('Resolve blocked applications or opt them out before applying: '+', '.join(r['id'] for r in blocked))
    # A shell palette changed by its normal Theme action can be adopted as the new input.
    # Other owned files remain protected by the transaction's comparison checks.
    result=store.apply(plan['operations'])
    reports=reload_apps(plan['reports']) if result['changed'] else plan['reports']
    result.update(reports=reports,theme=plan['theme']['name'],digest=plan['theme']['digest'],at=time.time())
    store.save(store.state/'status.json',result)
    return result


def synchronize(store=None):
    store=store or Store();options=settings(store)
    if not options['enabled'] or options['mode']=='independent':return {'changed':0,'disabled':True}
    if store.json(store.state/'status.json',{}).get('paused'):return {'changed':0,'paused':True}
    plan=preview(store,options,automatic=True)
    if not any(op['before']!=op['after'] for op in plan['operations']):return {'changed':0}
    return apply(store,options,plan['id'],automatic=True)

def status(store):
    apps=registry.discover(store);last=store.json(store.state/'status.json',{})
    reports={r['id']:r for r in last.get('reports',[])}
    for app in apps:
        if app['id'] in reports:app.update(reports[app['id']])
    return {'settings':settings(store),'applications':apps,'presets':tokens.presets(),'conflicts':registry.conflicts(store),'last':last,
            'interrupted':(store.state/'pending.json').exists(),'canRestore':(store.state/'last.json').exists(),
            'ownership':len(store.json(store.state/'ownership.json',{}))}
