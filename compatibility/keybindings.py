"""Conflict-preserving shortcut integration. Clipboard stays application-local."""
import json
from pathlib import Path
import re
import shlex
from .support import ROOT, d

BITS = {'SUPER': 64, 'CTRL': 4, 'ALT': 8, 'SHIFT': 1}


def defaults():
    rows = [
        ('launcher', 'SUPER + Space', 'exec', 'ipc menu toggle apps', None),
        ('terminal', 'SUPER + T', 'exec', 'launch terminal', None),
        ('browser', 'SUPER + W', 'exec', 'launch browser', None),
        ('files', 'SUPER + E', 'exec', 'launch files', None),
        ('close', 'SUPER + Q', 'killactive', '', 'hl.dsp.window.close()'),
        ('fullscreen', 'SUPER + F', 'fullscreen', '0', 'hl.dsp.window.fullscreen({mode="fullscreen"})'),
        ('floating', 'SUPER + ALT + Space', 'togglefloating', '', 'hl.dsp.window.float({action="toggle"})'),
        ('scratchpad', 'SUPER + S', 'togglespecialworkspace', 'special', 'hl.dsp.workspace.toggle_special("special")'),
        ('send-scratchpad', 'SUPER + ALT + S', 'movetoworkspace', 'special:special', 'hl.dsp.window.move({workspace="special:special"})'),
        ('quick-settings', 'SUPER + Comma', 'exec', 'ipc control toggle', None),
    ]
    for direction, short in [('Left', 'l'), ('Right', 'r'), ('Up', 'u'), ('Down', 'd')]:
        rows += [('focus-' + direction.lower(), 'SUPER + ' + direction, 'movefocus', short,
                  'hl.dsp.focus({direction="' + short + '"})'),
                 ('move-' + direction.lower(), 'SUPER + SHIFT + ' + direction, 'movewindow', short,
                  'hl.dsp.window.move({direction="' + short + '"})')]
    for number in range(1, 11):
        rows += [('workspace-' + str(number), 'SUPER + ' + str(number % 10), 'workspace', str(number),
                  'hl.dsp.focus({workspace="' + str(number) + '"})'),
                 ('send-workspace-' + str(number), 'SUPER + SHIFT + ' + str(number % 10), 'movetoworkspace', str(number),
                  'hl.dsp.window.move({workspace="' + str(number) + '"})')]
    return [dict(action=a, key=k, dispatcher=dispatch, argument=arg, lua=lua) for a, k, dispatch, arg, lua in rows]


def combo(value):
    if not isinstance(value, str):
        raise d.Refused('Shortcut assignments must be strings or null')
    parts = [v.strip() for v in value.split('+')]
    key = parts[-1]
    mods = parts[:-1]
    if not key or not re.fullmatch('[A-Za-z0-9_]+', key) or len(set(mods)) != len(mods) or any(m not in BITS for m in mods):
        raise d.Refused('Invalid shortcut: ' + value)
    if key.lower() in ('c', 'x', 'v') and mods == ['SUPER']:
        raise d.Refused('Global Super+C/X/V clipboard emulation is not supported; use application shortcuts.')
    return sum(BITS[m] for m in mods), key.lower()


def plan(live, assignments=None):
    assignments = assignments or {}
    if set(assignments) - {r['action'] for r in defaults()}:
        raise d.Refused('Unknown shortcut action in assignments')
    rows, seen = [], set()
    for default in defaults():
        row = dict(default)
        value = assignments.get(row['action'], row['key'])
        if value is None:
            row.update(disposition='Preserve', reason='Explicitly skipped'); rows.append(row); continue
        row['key'] = value
        identity = combo(value)
        if identity in seen:
            raise d.Refused('Two CEDAR actions have the same shortcut: ' + value)
        seen.add(identity)
        conflicts = [b for b in live if (b.get('modmask') == identity[0] and str(b.get('key', '')).lower() == identity[1])
                     or b.get('catch_all') or b.get('ignore_mods') or b.get('keycode', 0) != 0]
        row.update(disposition='Preserve' if conflicts else 'Add', conflicts=conflicts,
                   reason='Existing binding retained; reassign CEDAR in assignments JSON' if conflicts else 'Unoccupied shortcut')
        rows.append(row)
    return {'rows': rows, 'clipboard': 'Super+C/X/V are not bound globally. wl-clipboard transfers selections; it cannot implement universal application cut/copy/paste.'}


def render(report, suffix, root=ROOT):
    lines = ['-- CEDAR compatibility bindings' if suffix == '.lua' else '# CEDAR compatibility bindings']
    for row in report['rows']:
        if row['disposition'] != 'Add':
            continue
        dispatch, arg = row['dispatcher'], row['argument']
        if dispatch == 'exec':
            args = shlex.split(arg)
            script = 'desktop_runtime.py' if args[0] == 'launch' else 'distribution.py'
            arg = shlex.join(['python3', str(root / 'scripts' / script), *args])
            if any(c in arg for c in ('\n', '\r', '$', '`', '#', ',')):
                raise d.Refused('Runtime path needs manual command quoting review')
        if suffix == '.lua':
            action = 'hl.dsp.exec_cmd(' + json.dumps(arg) + ')' if dispatch == 'exec' else row['lua']
            lines.append('hl.bind(' + json.dumps(row['key']) + ', ' + action + ', {description=' + json.dumps('CEDAR ' + row['action']) + '})')
        else:
            parts = [part.strip() for part in row['key'].split('+')]
            lines.append('bindd = ' + ' '.join(parts[:-1]) + ', ' + parts[-1] + ', CEDAR ' + row['action'] + ', ' + dispatch + ', ' + arg)
    return '\n'.join(lines) + '\n'


def files(main, folder, report, root=ROOT):
    main, folder = Path(main), Path(folder)
    if main.suffix not in ('.lua', '.conf'):
        raise d.Refused('Unsupported Hyprland configuration syntax')
    from portable_providers import safe_target
    target = folder / ('bindings' + main.suffix)
    for path in (main, target):
        safe_target(path)
    if target.exists():
        raise d.Refused('Managed bindings already exist; restore their recorded migration first')
    text = main.read_text()
    if 'CEDAR COMPATIBILITY BINDINGS' in text:
        raise d.Refused('Existing or incomplete managed binding include; use migration history to restore')
    if any(c in str(target) for c in ('\n', '\r', '#', '$', '*', '?', '[', ']', '"', '\\')):
        raise d.Refused('Include path requires manual review')
    comment = '--' if main.suffix == '.lua' else '#'
    include = 'dofile(' + json.dumps(str(target)) + ')' if main.suffix == '.lua' else 'source = ' + str(target)
    text += '\n' + comment + ' CEDAR COMPATIBILITY BINDINGS START\n' + include + '\n' + comment + ' CEDAR COMPATIBILITY BINDINGS END\n'
    return [{'path': str(target), 'before': d.info(target), 'content': render(report, main.suffix, root), 'mode': 0o600},
            {'path': str(main), 'before': d.info(main), 'content': text, 'mode': main.stat().st_mode & 0o777}]
