#!/usr/bin/env python3
"""CEDAR-owned desktop actions. No desktop distribution is a prerequisite.

The Omarchy branch is an explicit compatibility choice, never auto-selected
because an executable or a directory happens to exist.
"""
from datetime import datetime
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
from distribution import atomic, read_json, xdg

ROOT = Path(__file__).resolve().parents[1]
IMAGE_SUFFIXES = {'.png', '.jpg', '.jpeg', '.webp', '.bmp'}
COLORS = ('background', 'surface', 'elevated', 'border', 'green', 'brightGreen',
          'teal', 'amber', 'ember', 'text', 'muted', 'blue', 'violet',
          'brightEmber', 'brightAmber', 'brightBlue', 'brightViolet', 'brightTeal',
          'white', 'paper', 'paperEdge', 'paperUnder', 'ink', 'inkSelection',
          'rule', 'ruleMajor', 'marginRule')


def omarchy():
    return os.environ.get('CEDAR_ADAPTER') == 'omarchy' or os.environ.get('CEDAR_OMARCHY_SESSION') == '1'


def config():
    return xdg('CONFIG', '.config') / 'cedar'


def settings():
    """CEDAR preferences (settings.json); unreadable or malformed files read as empty."""
    try:
        value = read_json(config() / 'settings.json')
    except (OSError, ValueError):
        return {}
    return value if isinstance(value, dict) else {}


def wallpaper_folder():
    """The user's chosen wallpaper folder, or None when unset or not a directory."""
    value = settings().get('wallpaperFolder', '')
    if not isinstance(value, str) or not value.strip():
        return None
    folder = Path(value.strip()).expanduser()
    if not folder.is_absolute():
        folder = Path.home() / folder
    return folder if folder.is_dir() else None


def folder_images(folder, limit=1000):
    """Images in a user folder and its subfolders, skipping hidden entries and bounded in size."""
    found = []
    for base, directories, files in os.walk(folder):
        directories[:] = sorted(name for name in directories if not name.startswith('.'))
        for name in sorted(files):
            path = Path(base) / name
            if not name.startswith('.') and path.is_file() and path.suffix.lower() in IMAGE_SUFFIXES:
                found.append(path)
                if len(found) >= limit:
                    return found
    return found


def desktop():
    path = config() / 'desktop.json'
    value = read_json(path) if path.exists() else {}
    if not isinstance(value, dict):
        raise ValueError('CEDAR desktop preferences must be a JSON object.')
    return value


def run(argv):
    result = subprocess.run(argv, capture_output=True, text=True, timeout=10)
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip() or 'Action failed: ' + argv[0])
    return result.stdout.strip()


def wallpapers():
    roots = [ROOT / 'themes/backgrounds', config() / 'wallpapers', xdg('DATA', '.local/share') / 'cedar/wallpapers']
    selected = desktop().get('wallpaper', '')
    if omarchy():
        current = xdg('STATE', '.local/state') / 'omarchy/current'
        roots.append(current / 'theme/backgrounds')
        try:
            selected = str((current / 'background').resolve(strict=True))
        except OSError:
            pass
    if selected:
        roots.append(Path(selected).parent)
    items = {}

    def add(path):
        resolved = str(path.resolve())
        items[resolved] = {'path': resolved, 'name': path.stem.replace('_', ' ').replace('-', ' ').title()}

    for directory in roots:
        try:
            for path in directory.iterdir():
                if path.is_file() and path.suffix.lower() in IMAGE_SUFFIXES:
                    add(path)
        except OSError:
            continue
    folder = wallpaper_folder()
    if folder is not None:
        try:
            for path in folder_images(folder):
                add(path)
        except OSError:
            pass
    return {'selected': selected, 'folder': str(folder) if folder is not None else '',
            'items': sorted(items.values(), key=lambda row: row['name'].casefold())}


def set_wallpaper(value):
    path = Path(value).expanduser().resolve(strict=True)
    if not path.is_file() or path.suffix.lower() not in IMAGE_SUFFIXES:
        raise ValueError('Choose a local image file.')
    if omarchy():
        run(['omarchy-theme-bg-set', str(path)])
    else:
        if os.environ.get('CEDAR_BACKGROUND') == 'external':
            raise RuntimeError('The existing desktop owns the wallpaper. Use its wallpaper settings; CEDAR preserves that provider.')
        value = desktop()
        value['wallpaper'] = str(path)
        atomic(config() / 'desktop.json', (json.dumps(value, indent=2) + '\n').encode())


def themes():
    """Bundled palettes first; a valid personal palette can override its namesake."""
    base = read_json(ROOT / 'themes/palettes/cedar.json')['colors']
    items = {'cedar': {'name': 'cedar', 'label': 'CEDAR', 'mode': 'dark',
                      'preview': (ROOT / 'themes/backgrounds/field-station.png').as_uri(),
                      'colors': {}, 'palette': base}}
    for directory in (ROOT / 'themes/palettes', config() / 'themes'):
        for path in sorted(directory.glob('*.json')):
            # CEDAR always remains an available reset to the shipped default.
            if path.stem == 'cedar':
                continue
            try:
                value = read_json(path)
                colors = validate_palette(value)
                items[path.stem] = {'name': path.stem,
                    'label': str(value.get('name', path.stem))[:80],
                    'mode': value.get('mode', 'dark'), 'preview': '',
                    'colors': colors, 'palette': {**base, **colors}}
            except (OSError, ValueError, TypeError):
                continue
    return list(items.values())


def theme(name):
    # Resolve only listed entries; never construct a filesystem path from input.
    for item in themes():
        if item['name'] == name:
            return item
    raise ValueError('That CEDAR theme is not installed.')


def validate_palette(value):
    if not isinstance(value, dict) or not isinstance(value.get('colors'), dict):
        raise ValueError('Theme needs a colors object.')
    colors = value['colors']
    if value.get('mode', 'dark') not in ('light', 'dark'):
        raise ValueError('Theme mode must be light or dark.')
    if not colors or any(key not in COLORS or not isinstance(color, str) or not re.fullmatch(r'#[0-9a-fA-F]{6}', color) for key, color in colors.items()):
        raise ValueError('Theme colors must use named CEDAR tokens and six-digit hex colors.')
    return colors


def set_theme(name):
    chosen = theme(name)
    value = {key: chosen[key] for key in ('name', 'mode', 'colors')}
    atomic(config() / 'theme.json', (json.dumps(value, indent=2) + '\n').encode())


def shell_sources():
    # Quickshell registers an instance under the path it was launched with. A
    # profile reached through ~/.config/quickshell/<name>, a symlink to the
    # checkout, answers at that unresolved path and not at the resolved one, so
    # the unresolved location is tried first and the checkout root second.
    override = os.environ.get('CEDAR_SHELL_PATH')
    if override:
        return [override]
    literal = Path(__file__).absolute().parents[1] / 'shell.qml'
    return list(dict.fromkeys([str(literal), str(ROOT / 'shell.qml')]))


def ipc(*args):
    # Explicit source path also works beside a top-level Quickshell shell.qml.
    failure = None
    for source in shell_sources():
        try:
            return run(['qs', 'ipc', '-p', source, 'call', *args])
        except RuntimeError as error:
            if 'No running instances' not in str(error):
                raise
            failure = error
    raise failure


TERMINAL_FLAGS = {'alacritty': ['-e'], 'ghostty': ['-e'], 'xterm': ['-e'], 'wezterm': ['start', '--']}


def terminal_argv(command=()):
    """Argv that opens a terminal, running `command` inside it when given.

    xdg-terminal-exec, foot and kitty take the command as positional
    arguments; alacritty, ghostty and xterm need -e; wezterm needs start --.
    """
    if shutil.which('xdg-terminal-exec'):
        argv = ['xdg-terminal-exec']
    else:
        choices = [shlex.split(os.environ.get('TERMINAL', ''))] + [[name] for name in ('foot', 'kitty', 'alacritty', 'ghostty', 'wezterm', 'xterm')]
        argv = next((a for a in choices if a and shutil.which(a[0])), None)
        if not argv:
            raise RuntimeError('Choose an installed terminal in Settings → Applications.')
    command = list(command)
    if command:
        argv = argv + TERMINAL_FLAGS.get(Path(argv[0]).name, []) + command
    return argv


def configured_argv(role):
    """The launch argv Settings → Applications chose for a role, or None.

    Mirrors Config.appArgv in the shell: a desktop-entry target first, then the
    legacy free-text command, so the keybinds open the same application as the
    bar's buttons.
    """
    saved = settings()
    targets = saved.get('applicationTargets')
    target = targets.get(role) if isinstance(targets, dict) else None
    if isinstance(target, dict) and target.get('kind') == 'desktop-entry' and isinstance(target.get('id'), str) and target['id']:
        return ['gtk-launch', target['id']]
    legacy = saved.get(role)
    if isinstance(legacy, str) and legacy.strip():
        return shlex.split(legacy)
    return None


def default_browser_argv():
    """The system's default browser with no page, falling back to a blank tab."""
    app = run(['xdg-mime', 'query', 'default', 'x-scheme-handler/https']) or run(['xdg-settings', 'get', 'default-web-browser'])
    if app:
        return ['gtk-launch', app]
    return ['xdg-open', 'about:blank']


def launch(role, command=()):
    if command and role != 'terminal':
        raise ValueError('Only the terminal role runs a command.')
    if role not in ('browser', 'files', 'editor', 'terminal'):
        raise ValueError('Unknown application role.')
    configured = None if command else configured_argv(role)
    if configured:
        argv = configured
    elif role == 'browser':
        argv = default_browser_argv()
    elif role == 'files':
        argv = ['xdg-open', str(Path.home())]
    elif role == 'editor':
        app = run(['xdg-mime', 'query', 'default', 'text/plain'])
        if not app:
            raise RuntimeError('Choose an editor in Settings → Default Applications.')
        argv = ['gtk-launch', app]
    else:
        argv = terminal_argv(command)
    subprocess.Popen(argv, start_new_session=True, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


# Unified copy, cut and paste: Super+C/X/V send the focused window the
# shortcut it understands. Terminals read Ctrl+C as an interrupt, so they get
# Ctrl+Shift+C and Ctrl+Shift+V, and cut does not exist there.
TERMINAL_CLASSES = {'foot', 'footclient', 'org.codeberg.dnkl.foot', 'kitty', 'alacritty', 'org.wezfurlong.wezterm', 'wezterm',
                    'com.mitchellh.ghostty', 'ghostty', 'xterm', 'urxvt', 'st', 'st-256color', 'konsole', 'org.kde.konsole',
                    'gnome-terminal-server', 'org.gnome.terminal', 'org.gnome.ptyxis', 'tilix', 'terminator', 'xfce4-terminal',
                    'termite', 'rio', 'contour', 'org.contourterminal.contour', 'blackbox', 'com.raggesilver.blackbox', 'warp', 'dev.warp.warp'}
CLIPBOARD_KEYS = {'copy': 'c', 'cut': 'x', 'paste': 'v'}


def active_window_class():
    # Do not guess a normal application when the compositor query fails:
    # sending Ctrl+C to an unidentified terminal would interrupt its process.
    window = hyprctl('activewindow')
    return str(window.get('class') or window.get('initialClass') or '') if isinstance(window, dict) else ''


def is_terminal_class(name):
    name = name.lower()
    if not name:
        return False
    if name in TERMINAL_CLASSES:
        return True
    configured = configured_argv('terminal')
    return bool(configured) and Path(configured[0]).name.lower() == name


def clipboard(action):
    """Send the focused window its own copy, cut or paste shortcut."""
    if action not in CLIPBOARD_KEYS:
        raise ValueError('Unified clipboard actions are copy, cut and paste.')
    terminal = is_terminal_class(active_window_class())
    if terminal and action == 'cut':
        return False  # terminals have no cut; nothing is sent
    mods = 'CTRL SHIFT' if terminal else 'CTRL'
    key = CLIPBOARD_KEYS[action]
    if (xdg('CONFIG', '.config') / 'hypr' / 'hyprland.lua').is_file():
        fields = 'mods = ' + json.dumps(mods) + ', key = ' + json.dumps(key)
        # A paired down/up avoids stuck synthetic keys on Lua Hyprland.
        # Keep the release in the compositor so Python exiting cannot omit it.
        expression = ('hl.dispatch(hl.dsp.send_key_state({ ' + fields + ', state = "down" })); '
                      'hl.timer(function() hl.dispatch(hl.dsp.send_key_state({ ' + fields + ', state = "up" })) end, '
                      '{ timeout = 50, type = "oneshot" })')
        argv = ['hyprctl', 'dispatch', expression]
    else:
        argv = ['hyprctl', 'dispatch', 'sendshortcut', mods + ', ' + key + ',']
    result = subprocess.run(argv, capture_output=True, text=True, timeout=10)
    if result.returncode != 0 or 'error' in (result.stdout + result.stderr).lower():
        raise RuntimeError('Hyprland did not send the shortcut: ' + (result.stdout + result.stderr).strip()[-200:])
    return True


CAPTURE_MODES = ('region', 'window', 'output', 'all')


def pictures_dir():
    """The user's Pictures folder from user-dirs.dirs, else ~/Pictures."""
    home = Path.home()
    try:
        for line in (xdg('CONFIG', '.config') / 'user-dirs.dirs').read_text().splitlines():
            match = re.fullmatch(r'\s*XDG_PICTURES_DIR="(.*)"\s*', line)
            if match:
                value = match.group(1).replace('$HOME', str(home))
                if value.startswith('/'):
                    return Path(value)
    except OSError:
        pass
    return home / 'Pictures'


def hyprctl(*args):
    value = json.loads(run(['hyprctl', '-j', *args]))
    if not value:
        raise RuntimeError('Hyprland reported nothing to capture.')
    return value


def capture_geometry(mode):
    """grim's `x,y wxh` for a capture mode; None when the user cancelled a region."""
    if mode == 'region':
        picked = subprocess.run(['slurp', '-d'], capture_output=True, text=True, timeout=120)
        if picked.returncode:
            return None
        return picked.stdout.strip() or None
    if mode == 'window':
        window = hyprctl('activewindow')
        if not window.get('address'):
            raise RuntimeError('No window has focus.')
        (x, y), (w, h) = window['at'], window['size']
        return '%d,%d %dx%d' % (x, y, w, h)
    if mode == 'output':
        monitor = next((m for m in hyprctl('monitors') if m.get('focused')), None)
        if monitor is None:
            raise RuntimeError('No monitor has focus.')
        scale = float(monitor.get('scale') or 1)
        return '%d,%d %dx%d' % (monitor['x'], monitor['y'], round(monitor['width'] / scale), round(monitor['height'] / scale))
    return ''


def capture(mode):
    """Screenshot with grim: save under Pictures/Screenshots, copy to the clipboard, notify.

    The file is the result; the clipboard copy and the notification are best
    effort and never report a saved capture as failed.
    """
    if mode not in CAPTURE_MODES:
        raise ValueError('Capture modes: ' + ', '.join(CAPTURE_MODES) + '.')
    if not shutil.which('grim'):
        raise RuntimeError('Install grim to take screenshots.')
    if mode == 'region' and not shutil.which('slurp'):
        raise RuntimeError('Install slurp to capture a region.')
    geometry = capture_geometry(mode)
    if geometry is None:
        return ''
    folder = pictures_dir() / 'Screenshots'
    folder.mkdir(parents=True, exist_ok=True)
    path = capture_path(folder)
    run(['grim', *(['-g', geometry] if geometry else []), str(path)])
    quiet = {'stdout': subprocess.DEVNULL, 'stderr': subprocess.DEVNULL, 'timeout': 10}
    if shutil.which('wl-copy'):
        try:
            with open(path, 'rb') as image:
                subprocess.run(['wl-copy', '--type', 'image/png'], stdin=image, **quiet)
        except (OSError, subprocess.SubprocessError):
            pass
    if shutil.which('notify-send'):
        try:
            subprocess.run(['notify-send', '-a', 'cedar', '-i', str(path), '-h', 'string:image-path:' + str(path),
                            'Screenshot saved', str(path)], **quiet)
        except (OSError, subprocess.SubprocessError):
            pass
    return str(path)


def capture_path(folder):
    """A fresh screenshot-<timestamp>.png; a second capture in the same second gets -2, -3, ..."""
    stem = datetime.now().strftime('screenshot-%Y-%m-%d_%H-%M-%S')
    path = folder / (stem + '.png')
    counter = 2
    while path.exists():
        path = folder / ('%s-%d.png' % (stem, counter))
        counter += 1
    return path


def main(args):
    name = args[0] if args else ''
    surfaces = {'settings': ('settings', 'toggle'), 'field-station': ('hud', 'toggle'),
                'quick': ('control', 'toggle'), 'power': ('power', 'toggle'),
                'lock': ('lock', 'lock'), 'wallpapers': ('wallpapers', 'toggle'),
                'themes': ('themes', 'toggle'), 'signals': ('core', 'toggle'),
                'notes': ('notes', 'toggle')}
    if name in surfaces:
        ipc(*surfaces[name])
    elif name == 'settings' and len(args) == 2:
        ipc('settings', 'show', args[1])
    elif name == 'shield':
        ipc('shield', 'open')
    elif name == 'station':
        ipc('station', 'page', args[1]) if len(args) == 2 else ipc('station', 'open')
    elif name == 'focus':
        ipc('focus', 'start', args[1]) if len(args) == 2 else ipc('focus', 'open')
    elif name == 'profiles':
        ipc('profiles', 'activate', args[1]) if len(args) == 2 else ipc('profiles', 'open')
    elif name == 'canopy' and len(args) == 2:
        ipc('canopy', 'open', args[1])
    elif name == 'launch' and len(args) >= 2:
        # `launch terminal CMD ARGS...` opens the terminal running CMD.
        launch(args[1], args[2:])
    elif name == 'wallpaper' and len(args) == 2:
        set_wallpaper(args[1])
    elif name == 'clipboard' and len(args) == 2:
        clipboard(args[1])
    elif name == 'capture':
        saved = capture(args[1] if len(args) == 2 else 'region')
        if saved:
            print(saved)
    else:
        raise ValueError('Unknown CEDAR desktop action.')


if __name__ == '__main__':
    try:
        main(sys.argv[1:])
    except (ValueError, OSError, RuntimeError, subprocess.SubprocessError) as error:
        print('CEDAR: ' + str(error), file=sys.stderr)
        sys.exit(1)
