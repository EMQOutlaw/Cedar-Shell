#!/usr/bin/env python3
"""CEDAR-owned desktop actions. No desktop distribution is a prerequisite.

The Omarchy branch is an explicit compatibility choice, never auto-selected
because an executable or a directory happens to exist.
"""
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
COLORS = ('background', 'surface', 'elevated', 'border', 'green', 'brightGreen',
          'teal', 'amber', 'ember', 'text', 'muted')


def omarchy():
    return os.environ.get('CEDAR_ADAPTER') == 'omarchy' or os.environ.get('CEDAR_OMARCHY_SESSION') == '1'


def config():
    return xdg('CONFIG', '.config') / 'cedar'


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
    for directory in roots:
        try:
            for path in directory.iterdir():
                if path.is_file() and path.suffix.lower() in {'.png', '.jpg', '.jpeg', '.webp', '.bmp'}:
                    resolved = str(path.resolve())
                    items[resolved] = {'path': resolved, 'name': path.stem.replace('_', ' ').replace('-', ' ').title()}
        except OSError:
            continue
    return {'selected': selected, 'items': sorted(items.values(), key=lambda row: row['name'].casefold())}


def set_wallpaper(value):
    path = Path(value).expanduser().resolve(strict=True)
    if not path.is_file() or path.suffix.lower() not in {'.png', '.jpg', '.jpeg', '.webp', '.bmp'}:
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
    items = [{'name': 'cedar', 'label': 'CEDAR', 'preview': (ROOT / 'themes/backgrounds/field-station.png').as_uri()}]
    for path in sorted((config() / 'themes').glob('*.json')):
        try:
            value = read_json(path)
            validate_palette(value)
            items.append({'name': path.stem, 'label': str(value.get('name', path.stem))[:80], 'preview': ''})
        except (OSError, ValueError, TypeError):
            continue
    return items


def validate_palette(value):
    if not isinstance(value, dict) or not isinstance(value.get('colors'), dict):
        raise ValueError('Theme needs a colors object.')
    colors = value['colors']
    if not colors or any(key not in COLORS or not isinstance(color, str) or not re.fullmatch(r'#[0-9a-fA-F]{6}', color) for key, color in colors.items()):
        raise ValueError('Theme colors must use named CEDAR tokens and six-digit hex colors.')
    return colors


def set_theme(name):
    if name not in [item['name'] for item in themes()]:
        raise ValueError('That CEDAR theme is not installed.')
    colors = {} if name == 'cedar' else validate_palette(read_json(config() / 'themes' / (name + '.json')))
    atomic(config() / 'theme.json', (json.dumps({'name': name, 'colors': colors}, indent=2) + '\n').encode())


def ipc(*args):
    # Explicit source path also works beside a top-level Quickshell shell.qml.
    source = os.environ.get('CEDAR_SHELL_PATH', str(ROOT / 'shell.qml'))
    return run(['qs', 'ipc', '-p', source, 'call', *args])


def launch(role):
    if role == 'browser':
        argv = ['xdg-open', 'https://duckduckgo.com']
    elif role == 'files':
        argv = ['xdg-open', str(Path.home())]
    elif role == 'editor':
        app = run(['xdg-mime', 'query', 'default', 'text/plain'])
        if not app:
            raise RuntimeError('Choose an editor in Settings → Default Applications.')
        argv = ['gtk-launch', app]
    elif role == 'terminal':
        if shutil.which('xdg-terminal-exec'):
            argv = ['xdg-terminal-exec']
        else:
            choices = [shlex.split(os.environ.get('TERMINAL', ''))] + [[name] for name in ('foot', 'kitty', 'alacritty', 'ghostty', 'wezterm', 'xterm')]
            argv = next((a for a in choices if a and shutil.which(a[0])), None)
            if not argv:
                raise RuntimeError('Choose an installed terminal in Settings → Applications.')
    else:
        raise ValueError('Unknown application role.')
    subprocess.Popen(argv, start_new_session=True, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def main(args):
    name = args[0] if args else ''
    surfaces = {'settings': ('settings', 'toggle'), 'field-station': ('hud', 'toggle'),
                'quick': ('control', 'toggle'), 'power': ('power', 'toggle'),
                'lock': ('lock', 'lock'), 'wallpapers': ('wallpapers', 'toggle'),
                'themes': ('themes', 'toggle'), 'signals': ('core', 'toggle')}
    if name in surfaces:
        ipc(*surfaces[name])
    elif name == 'canopy' and len(args) == 2:
        ipc('canopy', 'show', args[1])
    elif name == 'launch' and len(args) == 2:
        launch(args[1])
    elif name == 'wallpaper' and len(args) == 2:
        set_wallpaper(args[1])
    else:
        raise ValueError('Unknown CEDAR desktop action.')


if __name__ == '__main__':
    try:
        main(sys.argv[1:])
    except (ValueError, OSError, RuntimeError, subprocess.SubprocessError) as error:
        print('CEDAR: ' + str(error), file=sys.stderr)
        sys.exit(1)
