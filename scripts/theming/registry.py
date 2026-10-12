"""Capabilities describe actual integrations; detection never implies theme success."""
from pathlib import Path
import configparser
import os
import shutil
import subprocess

# id, label, category, executables, config hint, method, capability, reload
ROWS = [
('hyprland','Hyprland','Desktop','Hyprland','hypr/hyprland.conf','Native border palette include; preserves window rules and animations','partial','hypr-reload'),
('kde','KDE applications','Qt','dolphin kate kwrite okular gwenview ark spectacle kcalc partitionmanager kdeconnect-app','kdeglobals','KDE color scheme + owned kdeglobals keys','partial','restart'),
('qt5ct','Qt 5 configuration','Qt','qt5ct','qt5ct/qt5ct.conf','qt5ct native palette; existing platform plugin required','partial','restart'),
('qt6ct','Qt 6 configuration','Qt','qt6ct','qt6ct/qt6ct.conf','qt6ct native palette; existing platform plugin required','partial','restart'),
('gtk3','GTK 3 appearance','GTK','thunar mousepad geany gimp inkscape transmission-gtk','gtk-3.0/settings.ini','GTK settings: native light/dark, icons and fonts','partial','restart'),
('gtk4','GTK 4 / libadwaita','GTK','nautilus gnome-text-editor gnome-calculator gnome-disks gnome-system-monitor file-roller','gtk-4.0/settings.ini','GSettings + desktop portal preferences, no CSS injection','light-dark','portal'),
('alacritty','Alacritty','Terminals','alacritty','alacritty/alacritty.toml','Owned native TOML appearance keys','full','watch'),
('kitty','Kitty','Terminals','kitty','kitty/kitty.conf','Native include + separate palette','full','signal'),
('ghostty','Ghostty','Terminals','ghostty','ghostty/config','Native config-file include','full','manual-reload'),
('foot','Foot','Terminals','foot','foot/foot.ini','Owned INI appearance keys','full','restart'),
('konsole','Konsole','Terminals','konsole','konsolerc','Native color scheme + selected profile appearance','full','restart'),
('wezterm','WezTerm','Terminals','wezterm','wezterm/wezterm.lua','Native TOML color scheme; select CEDAR in Lua config','requires-integration','manual-select'),
('gnome-terminal','GNOME Terminal','Terminals','gnome-terminal','','GSettings default terminal profile','full','live'),
('tilix','Tilix','Terminals','tilix','','GSettings default terminal profile','full','live'),
('xfce-terminal','XFCE Terminal','Terminals','xfce4-terminal','xfce4/terminal/terminalrc','Owned INI color keys','full','restart'),
('terminator','Terminator','Terminals','terminator','terminator/config','ConfigObj default profile palette file; manual import','requires-integration','manual-select'),
('xterm','xterm','Terminals','xterm','','Xresources palette; explicit xrdb merge required','requires-integration','manual-select'),
('vscode','VS Code','Editors','code','Code/User/settings.json','Owned JSONC workbench/terminal color customizations','partial','watch'),
('vscodium','VSCodium','Editors','codium','VSCodium/User/settings.json','Owned JSONC workbench/terminal color customizations','partial','watch'),
('neovim','Neovim','Editors','nvim','nvim/init.lua','Native runtime colorscheme; :colorscheme cedar','requires-integration','manual-select'),
('helix','Helix','Editors','hx','helix/config.toml','Native theme and theme selection','partial','manual-reload'),
('emacs','Emacs','Editors','emacs','','Native deftheme file; load-theme cedar','requires-integration','manual-select'),
('zed','Zed','Editors','zed','zed/settings.json','Native theme file and JSONC theme selection','partial','watch'),
('sublime','Sublime Text','Editors','subl','sublime-text/Packages/User/Preferences.sublime-settings','Native color scheme and selection','partial','watch'),
('jetbrains','JetBrains IDEs','Editors','idea pycharm clion','','Editor color scheme import; IDE chrome uses native settings','requires-integration','manual-select'),
('rofi','Rofi','Launchers','rofi','rofi/config.rasi','Native Rasi theme include','partial','next-launch'),
('wofi','Wofi','Launchers','wofi','wofi/style.css','Managed CSS import','partial','next-launch'),
('fuzzel','Fuzzel','Launchers','fuzzel','fuzzel/fuzzel.ini','Owned native INI appearance keys','full','next-launch'),
('waybar','Waybar','Panels','waybar','waybar/style.css','Managed CSS import; no layout changes','partial','manual-reload'),
('eww','Eww','Panels','eww','eww/eww.scss','SCSS palette variables; widget integration required','requires-integration','manual-select'),
('yazi','Yazi','CLI','yazi','yazi/theme.toml','Owned native TOML theme keys','partial','restart'),
('ranger','Ranger','CLI','ranger','ranger/rc.conf','Terminal ANSI palette inheritance','partial','terminal'),
('btop','Btop','CLI','btop','btop/btop.conf','Native theme file and color_theme selection','partial','restart'),
('fastfetch','Fastfetch','CLI','fastfetch','fastfetch/config.jsonc','Terminal ANSI palette inheritance; preserves custom modules','partial','terminal'),
('lazygit','Lazygit','CLI','lazygit','lazygit/config.yml','Native YAML theme fragment; merge manually','requires-integration','manual-select'),
('zathura','Zathura','Documents','zathura','zathura/zathurarc','Native include for UI colors; document recoloring stays off','partial','restart'),
('swaync','SwayNotificationCenter','Notifications','swaync','swaync/style.css','Native CSS import','partial','reload'),
('mako','Mako','Notifications','mako','mako/config','Owned appearance section','partial','reload'),
('dunst','Dunst','Notifications','dunst','dunst/dunstrc','Owned global INI appearance keys','partial','manual-reload'),
('firefox','Firefox','Browsers','firefox','','System appearance; custom browser theme via supported extension','light-dark','portal'),
('chromium','Chromium browsers','Browsers','chromium google-chrome brave','','Native GTK/system theme when selected in browser settings','light-dark','portal'),
('thunderbird','Thunderbird','Mail','thunderbird','','System appearance when System theme is selected','light-dark','portal'),
('libreoffice','LibreOffice','Documents','libreoffice','','Toolkit/system appearance; in-app theme selection may be needed','light-dark','restart'),
('obs','OBS Studio','Media','obs','','OBS native theme import is version-specific; not generated','unsupported','none'),
('vlc','VLC','Media','vlc','','Qt palette where its native widget UI supports it','partial','restart'),
('mpv','MPV','Media','mpv','mpv/mpv.conf','Owned native OSD color keys','partial','restart'),
('spotify','Spotify clients','Media','spotify','','Client-native appearance only; no Spicetify or binary patches','unsupported','none'),
('discord','Discord clients','Communication','discord vesktop','','Client-native appearance only; no injected CSS/plugins','unsupported','none')]
REGISTRY={r[0]:dict(zip(('id','name','category','executables','config','method','capability','reload'),r)) for r in ROWS}
SHARED={'kde','gtk3','gtk4','qt5ct','qt6ct'}
FLATPAKS={'org.kde.dolphin':'kde','org.kde.kate':'kde','org.kde.okular':'kde','org.kde.konsole':'konsole','org.gnome.Nautilus':'gtk4','org.gnome.TextEditor':'gtk4','org.gnome.Calculator':'gtk4','org.gimp.GIMP':'gtk3','org.inkscape.Inkscape':'gtk3','org.mozilla.firefox':'firefox','org.mozilla.Thunderbird':'thunderbird','com.visualstudio.code':'vscode','com.vscodium.codium':'vscodium','com.obsproject.Studio':'obs','org.videolan.VLC':'vlc','com.spotify.Client':'spotify','com.discordapp.Discord':'discord'}

def discover(store, which=shutil.which, flatpaks=None):
    desktop={}
    roots=[store.data/'applications',store.home/'.local/share/flatpak/exports/share/applications',Path('/var/lib/flatpak/exports/share/applications')]
    roots += [Path(p)/'applications' for p in os.environ.get('XDG_DATA_DIRS','/usr/local/share:/usr/share').split(':')]
    for directory in roots:
        for path in directory.glob('*.desktop'):
            try:
                if path.stat().st_size>256000:continue
                parser=configparser.ConfigParser(interpolation=None,strict=False);parser.read(path)
                row=parser['Desktop Entry'];desktop[path.stem]={'name':row.get('Name',path.stem),'icon':row.get('Icon','application-x-executable'),'exec':row.get('Exec','')}
            except (OSError,KeyError,configparser.Error):continue
    if flatpaks is None:
        flatpaks=[]
        if which('flatpak'):
            try:flatpaks=subprocess.check_output(['flatpak','list','--app','--columns=application'],text=True,timeout=5,stderr=subprocess.DEVNULL).splitlines()
            except (OSError,subprocess.SubprocessError):pass
    result=[]
    for id,spec in REGISTRY.items():
        executables=[x for x in spec['executables'].split() if which(x)]
        entries=[v for k,v in desktop.items() if any(k.lower().split('.')[-1]==e or v['exec'].split(' ',1)[0].split('/')[-1]==e for e in spec['executables'].split())]
        sandbox=[app for app in flatpaks if FLATPAKS.get(app)==id]
        configured=bool(spec['config'] and (store.config/spec['config']).exists())
        installed=bool(executables or entries or sandbox)
        result.append({**spec,'installed':installed,'native':bool(executables or configured or [e for e in entries if not e['exec'].startswith('/usr/bin/flatpak') and not e['exec'].startswith('flatpak')]),
                       'evidence':executables+(['configuration'] if configured else [])+sandbox,
                       'icon':entries[0]['icon'] if entries else spec['executables'].split()[0],
                       'flatpaks':sandbox,'shared':id in SHARED,'status':'Detected' if installed else 'Configuration only' if configured else 'Not installed',
                       'visualTest':'Not visually verified; native format tests only'})
    return result

def conflicts(store):
    paths=['matugen/config.toml','wal','wallust/wallust.toml','Kvantum/kvantum.kvconfig','kdeglobals','caelestia','noctalia','ryoku','omarchy/current/theme','omarchy/themes']
    found=[str(store.config/p) for p in paths if (store.config/p).exists()]
    # Config presence is evidence of a possible owner, not proof an active manager is running.
    return {'possibleOwners':found,'qtPlatform':os.environ.get('QT_QPA_PLATFORMTHEME',''),'qtStyle':os.environ.get('QT_STYLE_OVERRIDE',''),
            'note':'Existing configuration is not proof of an active manager. Review ownership before enabling CEDAR Managed.'}
