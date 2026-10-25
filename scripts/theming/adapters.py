"""Native appearance adapters. Every result is a previewable transaction operation."""
import configparser
import functools
import tempfile
import json
import os
from pathlib import Path
import re
import shutil
from .formats import block, ini_patch, toml_patch, jsonc_patch
from .tokens import NAMES, rgb
from .transaction import file_op, run, Conflict


def read(store,path):
    store.check(path)
    return path.read_text() if path.exists() else ''
def ini(text):
    p=configparser.RawConfigParser(interpolation=None,strict=True,delimiters=('=',));p.optionxform=str
    p.read_string(text);return p

def flat(text, values, separator=' '):
    """Only overwrite CEDAR's section; existing assignments remain owned by the user."""
    return block(text,'\n'.join(k+separator+str(v) for k,v in values.items()))

def preferences(theme,id):
    if not shutil.which('gsettings') or not shutil.which('dconf'):raise ValueError('GSettings and dconf are required for this integration.')
    schema='org.gnome.desktop.interface'
    keys=set(run(['gsettings','list-keys',schema]).splitlines())
    desired={'color-scheme':"'prefer-"+theme['mode']+"'"}
    if theme['font']['enabled']:desired.update({'font-name':repr(theme['font']['ui']+' '+str(theme['font']['size'])),'monospace-font-name':repr(theme['font']['family']+' '+str(theme['font']['size']))})
    if theme['iconTheme']:desired['icon-theme']=repr(theme['iconTheme'])
    if 'accent-color' in keys:
        palette={'blue':'#3584e4','teal':'#2190a4','green':'#3a944a','yellow':'#c88800','orange':'#ed5b00','red':'#e62d42','pink':'#d56199','purple':'#9141ac','slate':'#6f8396'}
        target=rgb(theme['tokens']['accent.primary'])
        accent=min(palette,key=lambda k:sum((a-b)**2 for a,b in zip(rgb(palette[k]),target)))
        desired['accent-color']=repr(accent)
    ops=[]
    for key,value in desired.items():
        if key not in keys:continue
        if run(['gsettings','writable',schema,key])!='true':raise Conflict('Appearance preference is administratively locked: '+key)
        path='/org/gnome/desktop/interface/'+key
        ops.append({'kind':'gsettings','path':path,'before':{'data':run(['dconf','read',path]),'mode':0},'after':{'data':value,'mode':0},'app':id})
    if not ops:raise ValueError('This desktop does not expose supported appearance preferences.')
    return ops


@functools.lru_cache(maxsize=1)
def foot_version():
    if not shutil.which('foot'):return None
    match=re.search(r'(\d+)\.(\d+)\.',run(['foot','--version']))
    return tuple(map(int,match.groups())) if match else None

def generate(store,id,theme,config=None):
    cfg=Path(config or store.config);data=store.data;t=theme['tokens'];f=theme['font']
    bg=t['background.primary'];fg=t['text.primary'];surface=t['surface.default'];muted=t['text.secondary'];accent=t['accent.primary'];selection=t['surface.active']
    ansi=[t['terminal.'+n] for n in NAMES]+[t['terminal.bright.'+n] for n in NAMES]
    ops=[]
    def put(path,text):ops.append(file_op(store,path,text,id))
    def patch(path,values):put(path,ini_patch(read(store,path),values))
    def toml(path,values):put(path,toml_patch(read(store,path),values))
    def native(path,values,sep=' '):put(path,flat(read(store,path),values,sep))
    def generated(path,text):put(path,text)
    if id=='hyprland':
        candidates=[cfg/'hypr/hyprland.lua',cfg/'hypr/hyprland.conf']
        custom=os.environ.get('CEDAR_HYPR_CONFIG')
        if custom:path=Path(custom)
        else:
            existing=[p for p in candidates if p.exists()]
            if len(existing)>1:raise ValueError('Both Hyprland config formats exist. Set CEDAR_HYPR_CONFIG to the active path.')
            if not existing:raise ValueError('No existing Hyprland configuration to integrate.')
            path=existing[0]
        if path.suffix=='.lua':
            from desktop import lua
            target=cfg/'cedar/hypr/application-theme.lua'
            generated(target,'-- Generated appearance only.\nhl.config('+lua({'general':{'col':{'active_border':accent,'inactive_border':t['border.default']}}})+')\n')
            put(path,block(read(store,path),'dofile('+lua(str(target))+')',comment='--'))
        elif path.suffix=='.conf':
            target=cfg/'cedar/hypr/application-theme.conf'
            generated(target,'general {\n    col.active_border = rgb('+accent[1:]+')\n    col.inactive_border = rgb('+t['border.default'][1:]+')\n}\n')
            if any(c in str(target) for c in ('\n','\r','#','$')):raise ValueError('Unsupported Hyprland include path.')
            native(path,{'source':str(target)},' = ')
        else:raise ValueError('Unsupported Hyprland configuration format.')
    elif id=='kde':
        groups={}
        for role,back in [('View',bg),('Window',surface),('Button',surface),('Selection',accent),('Tooltip',t['background.elevated']),('Complementary',surface),('Header',surface)]:
            text=t['text.onAccent'] if role=='Selection' else fg
            vals={'BackgroundNormal':back,'BackgroundAlternate':t['background.elevated'],'ForegroundNormal':text,'ForegroundInactive':muted,'ForegroundActive':accent,'ForegroundLink':t['accent.secondary'],'ForegroundVisited':t['terminal.magenta'],'ForegroundNegative':t['status.error'],'ForegroundNeutral':t['status.warning'],'ForegroundPositive':t['status.success'],'DecorationFocus':accent,'DecorationHover':t['accent.secondary']}
            groups['Colors:'+role]={k:','.join(map(str,rgb(v))) for k,v in vals.items()}
        groups['General']={'ColorScheme':'CEDAR','Name':'CEDAR'}
        if f['enabled']:groups['General']['font']=f['ui']+','+str(f['size'])+',-1,5,50,0,0,0,0,0'
        if theme['iconTheme']:groups['Icons']={'Theme':theme['iconTheme']}
        generated(data/'color-schemes/CEDAR.colors',ini_patch('',groups))
        globals_groups={k:dict(v) for k,v in groups.items()};globals_groups['General'].pop('Name')
        patch(cfg/'kdeglobals',globals_groups)
    elif id in ('qt5ct','qt6ct'):
        # QPalette roles in qt5ct/qt6ct serialization order, through PlaceholderText.
        roles=[fg,surface,t['background.elevated'],surface,muted,t['border.default'],fg,fg,fg,bg,surface,t['border.default'],accent,t['text.onAccent'],t['accent.secondary'],t['terminal.magenta'],t['background.elevated'],surface,t['background.elevated'],fg,muted,accent]
        if id=='qt5ct':roles=roles[:21]
        colors=cfg/id/'colors/CEDAR.conf'
        disabled=[muted if i in (0,6,8,19,20) else value for i,value in enumerate(roles)]
        generated(colors,ini_patch('',{'ColorScheme':{'active_colors':','.join(roles),'inactive_colors':','.join(roles),'disabled_colors':','.join(disabled)}}))
        vals={'custom_palette':'true','color_scheme_path':str(colors)}
        if theme['iconTheme']:vals['icon_theme']=theme['iconTheme']
        patch(cfg/id/(id+'.conf'),{'Appearance':vals})
    elif id=='gtk3':
        vals={'gtk-theme-name':'Adwaita-dark' if theme['mode']=='dark' else 'Adwaita','gtk-application-prefer-dark-theme':'1' if theme['mode']=='dark' else '0'}
        if f['enabled']:vals['gtk-font-name']=f['ui']+' '+str(f['size'])
        if theme['iconTheme']:vals['gtk-icon-theme-name']=theme['iconTheme']
        patch(cfg/'gtk-3.0/settings.ini',{'Settings':vals})
    elif id=='gtk4':ops.extend(preferences(theme,id))
    elif id=='alacritty':
        candidates=[cfg/'alacritty/alacritty.toml',cfg/'alacritty.toml',store.home/'.alacritty.toml']
        path=next((p for p in candidates if p.exists()),candidates[0])
        vals={'colors.primary':{'background':bg,'foreground':fg,'dim_foreground':muted,'bright_foreground':fg},'colors.cursor':{'text':bg,'cursor':accent},'colors.selection':{'text':fg,'background':selection},'colors.normal':dict(zip(NAMES,ansi[:8])),'colors.bright':dict(zip(NAMES,ansi[8:])),'window':{'opacity':theme['opacity']}}
        if f['enabled']:vals.update({'font':{'size':f['size']},'font.normal':{'family':f['family']}})
        toml(path,vals)
    elif id=='kitty':
        palette=cfg/'kitty/cedar-theme.conf'
        vals={'foreground':fg,'background':bg,'cursor':accent,'cursor_text_color':bg,'selection_foreground':fg,'selection_background':selection,'background_opacity':theme['opacity'],**{'color'+str(i):c for i,c in enumerate(ansi)}}
        if f['enabled']:vals.update(font_family=f['family'],font_size=f['size'])
        generated(palette,'\n'.join(k+' '+str(v) for k,v in vals.items())+'\n')
        native(cfg/'kitty/kitty.conf',{'include':'cedar-theme.conf'})
    elif id=='ghostty':
        path=cfg/'ghostty/config.ghostty' if (cfg/'ghostty/config.ghostty').exists() else cfg/'ghostty/config'
        palette=cfg/'ghostty/cedar-theme.conf'
        vals={'background':bg,'foreground':fg,'cursor-color':accent,'cursor-text':bg,'selection-background':selection,'selection-foreground':fg,'background-opacity':theme['opacity']}
        if f['enabled']:vals.update({'font-family':f['family'],'font-size':f['size']})
        generated(palette,'\n'.join(k+' = '+str(v) for k,v in vals.items())+'\n'+'\n'.join('palette = '+str(i)+'='+c for i,c in enumerate(ansi))+'\n')
        native(path,{'config-file':'cedar-theme.conf'},' = ')
    elif id=='foot':
        path=cfg/'foot/foot.ini';text=read(store,path)
        version=foot_version();modern=version>=(1,26) if version else '[colors]' not in text
        section='colors-'+theme['mode'] if modern else 'colors'
        vals={section:{'background':bg[1:],'foreground':fg[1:],'alpha':theme['opacity'],'selection-background':selection[1:],'selection-foreground':fg[1:],**{'regular'+str(i):c[1:] for i,c in enumerate(ansi[:8])},**{'bright'+str(i):c[1:] for i,c in enumerate(ansi[8:])}}}
        if modern:
            vals[section]['cursor']=bg[1:]+' '+accent[1:]
            vals['main']={'initial-color-theme':theme['mode']}
        else:vals['cursor']={'color':bg[1:]+' '+accent[1:]}
        if f['enabled']:vals.setdefault('main',{})['font']=f['family']+':size='+str(f['size'])
        # Foot permits main keys before the first explicit section.
        prefix=text.split('[',1)[0]
        if any(line.strip() and not line.lstrip().startswith(('#',';')) for line in prefix.splitlines()):text='[main]\n'+text
        output=ini_patch(text,vals)
        if version:
            with tempfile.NamedTemporaryFile(mode='w',suffix='.ini') as handle:
                handle.write(output);handle.flush()
                run(['foot','--check-config','--config='+handle.name])
        put(path,output)
    elif id=='konsole':
        vals={'General':{'Description':'CEDAR','Opacity':theme['opacity']}}
        for name,c in [('Background',bg),('Foreground',fg)]+[('Color'+str(i),c) for i,c in enumerate(ansi[:8])]+[('Color'+str(i)+'Intense',c) for i,c in enumerate(ansi[8:])]:vals[name]={'Color':','.join(map(str,rgb(c)))}
        generated(data/'konsole/CEDAR.colorscheme',ini_patch('',vals))
        settings=ini(read(store,cfg/'konsolerc'));profile=settings.get('Desktop Entry','DefaultProfile',fallback='CEDAR.profile')
        if not re.fullmatch(r'[\w .+-]+\.profile',profile):raise ValueError('Unsupported Konsole profile path.')
        vals={'Appearance':{'ColorScheme':'CEDAR'}}
        if f['enabled']:vals['Appearance']['Font']=f['family']+','+str(f['size'])+',-1,5,50,0,0,0,0,0'
        if not (data/'konsole'/profile).exists():vals['General']={'Name':'CEDAR','Parent':'FALLBACK/'}
        patch(data/'konsole'/profile,vals);patch(cfg/'konsolerc',{'Desktop Entry':{'DefaultProfile':profile}})
    elif id=='wezterm':
        vals={'colors':{'background':bg,'foreground':fg,'cursor_bg':accent,'cursor_fg':bg,'selection_bg':selection,'selection_fg':fg,'ansi':ansi[:8],'brights':ansi[8:]},'metadata':{'name':'CEDAR'}}
        generated(cfg/'wezterm/colors/CEDAR.toml',toml_patch('',vals))
    elif id in ('gnome-terminal','tilix'):
        if not shutil.which('dconf'):raise ValueError('dconf is required.')
        base='/org/gnome/terminal/legacy/profiles:/' if id=='gnome-terminal' else '/com/gexperts/Tilix/profiles/'
        schema='org.gnome.Terminal.ProfilesList' if id=='gnome-terminal' else 'com.gexperts.Tilix.ProfilesList'
        profile=run(['gsettings','get',schema,'default']).strip("'")
        if not re.fullmatch(r'[0-9a-f-]{36}',profile):raise ValueError('No supported default terminal profile.')
        path=base+(':' if id=='gnome-terminal' else '')+profile+'/'
        vals={'use-theme-colors':'false','background-color':repr(bg),'foreground-color':repr(fg),'palette':str(ansi)}
        vals.update({'cursor-colors-set':'true','cursor-background-color':repr(accent),'cursor-foreground-color':repr(bg),'highlight-colors-set':'true','highlight-background-color':repr(selection),'highlight-foreground-color':repr(fg)})
        if f['enabled']:vals.update({'use-system-font':'false','font':repr(f['family']+' '+str(f['size']))})
        profile_schema=('org.gnome.Terminal.Legacy.Profile' if id=='gnome-terminal' else 'com.gexperts.Tilix.Profile')+':'+path
        keys=set(run(['gsettings','list-keys',profile_schema]).splitlines())
        for key,value in vals.items():
            if key not in keys:raise ValueError('This terminal profile does not support '+key)
            if run(['gsettings','writable',profile_schema,key])!='true':raise Conflict('Terminal profile is locked: '+key)
            ops.append({'kind':'gsettings','path':path+key,'before':{'data':run(['dconf','read',path+key]),'mode':0},'after':{'data':value,'mode':0},'app':id})
    elif id=='xfce-terminal':
        vals={'ColorForeground':fg,'ColorBackground':bg,'ColorCursor':accent,'ColorPalette':';'.join(ansi),'ColorUseTheme':'FALSE'}
        if f['enabled']:vals['FontName']=f['family']+' '+str(f['size'])
        patch(cfg/'xfce4/terminal/terminalrc',{'Configuration':vals})
    elif id=='terminator':generated(cfg/'cedar/theming/exports/terminator.conf','[profiles]\n  [[cedar]]\n    background_color = '+bg+'\n    foreground_color = '+fg+'\n    palette = "'+':'.join(ansi)+'"\n')
    elif id=='xterm':generated(cfg/'cedar/theming/exports/Xresources','XTerm*background: '+bg+'\nXTerm*foreground: '+fg+'\nXTerm*cursorColor: '+accent+'\n'+'\n'.join('XTerm*color'+str(i)+': '+c for i,c in enumerate(ansi))+'\n')
    elif id in ('vscode','vscodium'):
        folder='Code' if id=='vscode' else 'VSCodium';path=cfg/folder/'User/settings.json'
        text=read(store,path)
        # Parse through the lossless scanner; reparse its normalized copy to retain unowned color keys.
        from .formats import jsonc_load
        old=jsonc_load(text or '{}');custom=old.get('workbench.colorCustomizations',{})
        if not isinstance(custom,dict):raise ValueError('Invalid editor color customizations.')
        custom={**custom,'editor.background':bg,'editor.foreground':fg,'sideBar.background':surface,'activityBar.background':surface,'statusBar.background':surface,'focusBorder':accent,'terminal.background':bg,'terminal.foreground':fg,'terminalCursor.foreground':accent}
        for i,name in enumerate(['Black','Red','Green','Yellow','Blue','Magenta','Cyan','White']):
            custom['terminal.ansi'+name]=ansi[i];custom['terminal.ansiBright'+name]=ansi[i+8]
        vals={'workbench.colorCustomizations':custom}
        if f['enabled']:vals.update({'editor.fontFamily':f['family'],'editor.fontSize':f['size'],'terminal.integrated.fontFamily':f['family']})
        put(path,jsonc_patch(text,vals))
    elif id=='helix':
        generated(cfg/'helix/themes/cedar.toml','"ui.background" = { bg = "'+bg+'" }\n"ui.text" = "'+fg+'"\n"ui.selection" = { bg = "'+selection+'" }\n"ui.cursor" = { bg = "'+accent+'", fg = "'+bg+'" }\n"comment" = "'+muted+'"\n"keyword" = "'+accent+'"\n"string" = "'+t['accent.secondary']+'"\n')
        toml(cfg/'helix/config.toml',{'':{'theme':'cedar'}})
    elif id=='neovim':
        groups={'Normal':(fg,bg),'NormalFloat':(fg,surface),'Comment':(muted,None),'Visual':(fg,selection),'Cursor':(bg,accent),'String':(t['accent.secondary'],None),'Keyword':(accent,None),'Error':(t['status.error'],None)}
        text='vim.cmd("highlight clear")\nvim.g.colors_name = "cedar"\n'
        for group,(front,back) in groups.items():text+='vim.api.nvim_set_hl(0, '+json.dumps(group)+', {fg='+json.dumps(front)+((', bg='+json.dumps(back)) if back else '')+'})\n'
        for i,c in enumerate(ansi):text+='vim.g.terminal_color_'+str(i)+' = '+json.dumps(c)+'\n'
        generated(data/'nvim/site/colors/cedar.lua',text)
    elif id=='emacs':generated(cfg/'cedar/theming/exports/cedar-theme.el',"(deftheme cedar)\n(custom-theme-set-faces 'cedar\n '(default ((t (:background \""+bg+'" :foreground "'+fg+"\"))))\n '(region ((t (:background \""+selection+"\"))))\n '(font-lock-keyword-face ((t (:foreground \""+accent+"\")))))\n(provide-theme 'cedar)\n")
    elif id=='zed':
        style={'background':bg,'editor.background':bg,'editor.foreground':fg,'text':fg,'text.muted':muted,'border':t['border.default'],'border.focused':accent,'terminal.background':bg,'terminal.foreground':fg}
        for i,name in enumerate(NAMES):style['terminal.ansi.'+name]=ansi[i];style['terminal.ansi.bright_'+name]=ansi[i+8]
        generated(cfg/'zed/themes/cedar.json',json.dumps({'name':'CEDAR','author':'CEDAR','themes':[{'name':'CEDAR','appearance':theme['mode'],'style':style}]},indent=2)+'\n')
        put(cfg/'zed/settings.json',jsonc_patch(read(store,cfg/'zed/settings.json'),{'theme':'CEDAR'}))
    elif id=='sublime':
        folder=cfg/'sublime-text/Packages/User'
        generated(folder/'CEDAR.sublime-color-scheme',json.dumps({'name':'CEDAR','globals':{'background':bg,'foreground':fg,'caret':accent,'selection':selection},'rules':[{'scope':'comment','foreground':muted},{'scope':'keyword','foreground':accent}]},indent=2)+'\n')
        put(folder/'Preferences.sublime-settings',jsonc_patch(read(store,folder/'Preferences.sublime-settings'),{'color_scheme':'Packages/User/CEDAR.sublime-color-scheme'}))
    elif id=='jetbrains':generated(cfg/'cedar/theming/exports/CEDAR.icls','<scheme name="CEDAR" version="142" parent_scheme="'+('Darcula' if theme['mode']=='dark' else 'Default')+'"><attributes><option name="TEXT"><value><option name="FOREGROUND" value="'+fg[1:]+'"/><option name="BACKGROUND" value="'+bg[1:]+'"/></value></option></attributes></scheme>\n')
    elif id=='rofi':
        path=cfg/'rofi/cedar.rasi';generated(path,'* { background: '+bg+'; foreground: '+fg+'; selected-normal-background: '+accent+'; selected-normal-foreground: '+t['text.onAccent']+'; }\nwindow { background-color: @background; border: 1px; border-color: '+t['border.default']+'; border-radius: '+str(theme['radius'])+'px; }\nelement selected { background-color: @selected-normal-background; text-color: @selected-normal-foreground; }\n')
        put(cfg/'rofi/config.rasi',block(read(store,cfg/'rofi/config.rasi'),'@theme "cedar.rasi"','CEDAR APPLICATION THEME','//'))
    elif id in ('wofi','waybar','swaync'):
        path=cfg/id/'cedar.css';generated(path,'@define-color cedar_bg '+bg+';\n@define-color cedar_fg '+fg+';\n@define-color cedar_accent '+accent+';\nwindow { background-color: @cedar_bg; color: @cedar_fg; }\n'+('button:selected, row:selected { background-color: @cedar_accent; color: '+t['text.onAccent']+'; }\n' if id!='waybar' else ''))
        text=read(store,cfg/id/'style.css');start='/* BEGIN CEDAR APPLICATION THEME */';end='/* END CEDAR APPLICATION THEME */'
        if start in text:
            if text.count(start)!=1 or text.count(end)!=1:raise ValueError('Invalid CSS managed section')
            a=text.index(start);b=text.index(end)+len(end);text=text[:a]+text[b:]
        put(cfg/id/'style.css',start+'\n@import url("cedar.css");\n'+end+'\n'+text.lstrip('\n'))
    elif id=='fuzzel':
        vals={'colors':{'background':bg[1:]+'ff','text':fg[1:]+'ff','match':accent[1:]+'ff','selection':selection[1:]+'ff','selection-text':fg[1:]+'ff','selection-match':accent[1:]+'ff','border':t['border.default'][1:]+'ff'},'border':{'radius':theme['radius']}}
        if f['enabled']:vals['main']={'font':f['family']+':size='+str(f['size'])}
        patch(cfg/'fuzzel/fuzzel.ini',vals)
    elif id=='eww':generated(cfg/'eww/cedar-palette.scss','$cedar-bg: '+bg+';\n$cedar-fg: '+fg+';\n$cedar-accent: '+accent+';\n')
    elif id=='yazi':toml(cfg/'yazi/theme.toml',{'mgr.border_style':{'fg':t['border.default']},'status.overall':{'fg':fg,'bg':bg}})
    elif id=='btop':
        generated(cfg/'btop/themes/cedar.theme','\n'.join('theme['+k+']="'+v+'"' for k,v in {'main_bg':bg,'main_fg':fg,'title':accent,'hi_fg':accent,'selected_bg':selection,'selected_fg':fg,'inactive_fg':muted,'proc_misc':t['accent.secondary'],'cpu_box':accent,'mem_box':t['accent.secondary'],'net_box':t['status.info'],'proc_box':t['status.warning'],'div_line':t['border.default']}.items())+'\n')
        native(cfg/'btop/btop.conf',{'color_theme':'"cedar"'},' = ')
    elif id=='lazygit':generated(cfg/'cedar/theming/exports/lazygit.yml',"gui:\n  theme:\n    activeBorderColor: ['"+accent+"', bold]\n    inactiveBorderColor: ['"+muted+"']\n    selectedLineBgColor: ['"+selection+"']\n    defaultFgColor: ['"+fg+"']\n")
    elif id=='zathura':
        path=cfg/'zathura/cedar.conf';generated(path,'\n'.join('set '+k+' "'+v+'"' for k,v in {'default-bg':bg,'default-fg':fg,'statusbar-bg':surface,'statusbar-fg':fg,'inputbar-bg':surface,'inputbar-fg':fg,'completion-bg':surface,'completion-fg':fg,'completion-highlight-bg':accent,'completion-highlight-fg':t['text.onAccent']}.items())+'\n')
        native(cfg/'zathura/zathurarc',{'include':'cedar.conf'})
    elif id=='mako':
        # Mako criteria sections change the interpretation of subsequent keys.
        path=cfg/'mako/config';text=read(store,path)
        if re.search(r'^\s*\[',text,re.M):raise ValueError('Mako criteria sections require manual appearance integration.')
        native(path,{'background-color':bg,'text-color':fg,'border-color':accent,'border-radius':theme['radius']},'=')
    elif id=='dunst':patch(cfg/'dunst/dunstrc',{'global':{'background':'"'+bg+'"','foreground':'"'+fg+'"','frame_color':'"'+accent+'"','corner_radius':theme['radius']}})
    elif id=='mpv':native(cfg/'mpv/mpv.conf',{'osd-color':fg,'osd-border-color':bg,'osd-back-color':surface},'=')
    elif id in ('firefox','chromium','thunderbird','libreoffice','vlc','ranger','fastfetch'):
        # These inherit an enabled toolkit/terminal adapter. No invented app-specific config.
        pass
    else:raise ValueError('No native configuration adapter is available for '+id)
    return ops
