#!/usr/bin/env python3
"""CEDAR's keybind set, from one definition.

`data/keybinds.json` is the single source: the groups, keys, descriptions and
what each key does, in both Hyprland syntaxes. This script renders it to
`themes/keybinds.lua` and `themes/keybinds.conf`, and the keybind reference
(Super+K) reads the same file, so the shortcuts on the keyboard, the files the
installer ships and the reference the shell shows never drift apart.

  python3 scripts/keybinds.py --check   files match the definition (exit 1 otherwise)
  python3 scripts/keybinds.py --write   regenerate both files and record them as shipped
  python3 scripts/keybinds.py --list    the expanded set, one line per key
"""
from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFINITION = ROOT / 'data' / 'keybinds.json'
TARGETS = {'lua': ROOT / 'themes' / 'keybinds.lua', 'conf': ROOT / 'themes' / 'keybinds.conf'}
# Every version of TARGETS that has shipped, so the installer can tell an
# untouched old copy (replace it) from one the user edited (keep it).
SHIPPED = ROOT / 'data' / 'keybinds-shipped.json'
MODS = ('SUPER', 'CTRL', 'ALT', 'SHIFT')
FLAGS = ('locked', 'repeating', 'mouse', 'release')


def load(path: Path = DEFINITION) -> dict:
    spec = json.loads(path.read_text(encoding='utf-8'))
    if not isinstance(spec, dict) or not isinstance(spec.get('groups'), list):
        raise ValueError('keybinds.json: expected an object with a groups list')
    return spec


def fill(text: str, var: dict) -> str:
    for name, value in var.items():
        text = text.replace('{' + name + '}', str(value))
    if re.search(r'\{[a-z]+\}', text):
        raise ValueError('unfilled placeholder in ' + text)
    return text


def rows(spec: dict) -> list[dict]:
    """The expanded set: one row per press or release, in definition order."""
    out = []
    for group in spec['groups']:
        for entry in group['entries']:
            flags = entry.get('flags', [])
            unknown = [f for f in flags if f not in FLAGS]
            if unknown:
                raise ValueError('unknown flag ' + ', '.join(unknown) + ' on ' + ' / '.join(entry['keys']))
            for var in entry.get('vars') or [{}]:
                description = fill(entry.get('each') or entry['description'], var)
                for keys in entry['keys']:
                    out.append({'group': group['id'], 'keys': fill(keys, var), 'description': description,
                                'lua': fill(entry['lua'], var), 'conf': fill(entry['conf'], var), 'flags': list(flags)})
                    if entry.get('release'):
                        out.append({**out[-1], 'lua': fill(entry['release']['lua'], var),
                                    'conf': fill(entry['release']['conf'], var),
                                    'flags': [f for f in flags if f not in ('repeating', 'release')] + ['release']})
    return out


def split(keys: str) -> tuple[list[str], str]:
    parts = [p.strip() for p in keys.split('+')]
    if not parts or not parts[-1]:
        raise ValueError('empty key in ' + keys)
    mods = [m.upper() for m in parts[:-1]]
    if any(m not in MODS for m in mods) or len(set(mods)) != len(mods):
        raise ValueError('bad modifiers in ' + keys)
    return mods, parts[-1]


def normalize(keys: str) -> str:
    """Canonical spelling for comparing combinations: modifiers in a fixed order, key upper-cased."""
    mods, key = split(keys)
    return ' + '.join([m for m in MODS if m in mods] + [key.upper()])


def lua_string(value: str) -> str:
    if any(ord(c) > 126 or ord(c) < 32 for c in value):
        raise ValueError('only printable ASCII goes into keybinds.lua: ' + value)
    return '"' + value.replace('\\', '\\\\').replace('"', '\\"') + '"'


LUA_HEAD = '''-- CEDAR keybinds for Hyprland's Lua configuration.
--
-- Generated from data/keybinds.json by scripts/keybinds.py; edit the
-- definition and run `python3 scripts/keybinds.py --write`. The installer
-- copies this file to ~/.config/cedar/hypr/keybinds.lua and CEDAR's
-- generated.lua loads it. Every bind first unbinds the same keys, so it wins
-- over an earlier binding on that combination and leaves every other binding
-- alone. Personal changes go in user.lua (loaded last) or Settings > Keybinds.
-- The shell actions reach the CEDAR that owns the `cedar` Quickshell profile
-- (release or checkout) over IPC; the app bindings open the terminal, browser
-- and file manager chosen in CEDAR Settings.

local home = os.getenv("HOME") or ""
local data = os.getenv("XDG_DATA_HOME") or (home .. "/.local/share")

-- Quickshell matches a running instance by its config path. The live shell is
-- whatever owns the `cedar` profile (the installed release, or a checkout
-- linked there), so address it by profile, run its scripts, and fall back to
-- the release only when no profile exists. Mirrors shell_selector in
-- scripts/distribution.py.
local config = os.getenv("XDG_CONFIG_HOME") or (home .. "/.config")
local root = data .. "/cedar/current"
local qs = 'qs -p "$(readlink -f ' .. root .. '/shell.qml)"' 
do
  local profile = io.open(config .. "/quickshell/cedar/shell.qml", "r")
  if profile then profile:close(); qs = "qs -c cedar"; root = config .. "/quickshell/cedar" end
end
local runtime = root .. "/scripts/desktop_runtime.py"

local function ipc(args) return hl.dsp.exec_cmd(qs .. " ipc call " .. args) end
local function launch(kind) return hl.dsp.exec_cmd("python3 " .. runtime .. " launch " .. kind) end
local function clipboard(kind) return hl.dsp.exec_cmd("python3 " .. runtime .. " clipboard " .. kind) end

local bound = {}
local function bind(keys, action, description, flags)
  local options = {}
  for key, value in pairs(flags or {}) do options[key] = value end
  options.description = description
  if not bound[keys] then hl.unbind(keys); bound[keys] = true end
  hl.bind(keys, action, options)
end
'''

CONF_HEAD = '''# CEDAR keybinds for Hyprland's hyprlang configuration.
#
# Generated from data/keybinds.json by scripts/keybinds.py; edit the
# definition and run `python3 scripts/keybinds.py --write`. The installer
# copies this file to ~/.config/cedar/hypr/keybinds.conf and CEDAR's
# generated.conf sources it. Every bind first unbinds the same keys, so it
# wins over an earlier binding on that combination and leaves every other
# binding alone. Personal changes go in user.conf (sourced last) or
# Settings > Keybinds. Shell actions go to the CEDAR release through its IPC;
# the app bindings open the terminal, browser and file manager chosen in
# CEDAR Settings.

# `cedar ipc` addresses the shell that owns the `cedar` Quickshell profile
# (release or checkout) and falls back to the release path.
$cedarShell = ~/.local/bin/cedar ipc
$cedarRuntime = python3 ~/.local/share/cedar/current/scripts/desktop_runtime.py
$cedarLaunch = $cedarRuntime launch
'''


def lua_flags(flags: list[str]) -> str:
    if not flags:
        return ''
    return ', { ' + ', '.join(f + ' = true' for f in flags) + ' }'


def render_lua(spec: dict) -> str:
    lines = [LUA_HEAD]
    for group in spec['groups']:
        lines.append('-- ' + group['title'])
        for row in rows(spec):
            if row['group'] != group['id']:
                continue
            lines.append('bind(' + lua_string(row['keys']) + ', ' + row['lua'] + ', ' + lua_string(row['description']) + lua_flags(row['flags']) + ')')
        lines.append('')
    return '\n'.join(lines).rstrip('\n') + '\n'


def conf_keys(keys: str) -> str:
    mods, key = split(keys)
    return ' '.join(mods) + ', ' + key


def render_conf(spec: dict) -> str:
    lines = [CONF_HEAD]
    bound = set()
    for group in spec['groups']:
        lines.append('# ' + group['title'])
        for row in rows(spec):
            if row['group'] != group['id']:
                continue
            keys = conf_keys(row['keys'])
            combo = normalize(row['keys'])
            if combo not in bound:
                lines.append('unbind = ' + keys)
                bound.add(combo)
            if 'mouse' in row['flags']:
                lines.append('bindm = ' + keys + ', ' + row['conf'])
                continue
            letters = ''.join(l for f, l in (('locked', 'l'), ('repeating', 'e'), ('release', 'r')) if f in row['flags'])
            description = row['description'].replace(',', ' ')
            if '#' in description or '\n' in description:
                raise ValueError('a conf description cannot hold # or a newline: ' + description)
            lines.append('bind' + letters + 'd = ' + keys + ', ' + description + ', ' + row['conf'])
        lines.append('')
    return '\n'.join(lines).rstrip('\n') + '\n'


def render(spec: dict, syntax: str) -> str:
    return render_lua(spec) if syntax == 'lua' else render_conf(spec)


def check(spec: dict | None = None) -> list[str]:
    """Which rendered files differ from the definition (empty when in sync)."""
    spec = spec or load()
    return [name for name, path in TARGETS.items() if not path.is_file() or path.read_text(encoding='utf-8') != render(spec, name)]


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def shipped(path: Path = SHIPPED) -> dict:
    return json.loads(path.read_text(encoding='utf-8')) if path.is_file() else {}


def unrecorded(path: Path = SHIPPED) -> list[str]:
    """Rendered files whose digest is missing from data/keybinds-shipped.json."""
    known = shipped(path)
    return [name for name, target in TARGETS.items() if not target.is_file() or digest(target) not in known.get(name, [])]


def record(path: Path = SHIPPED) -> None:
    known = shipped(path)
    for name, target in TARGETS.items():
        versions = known.setdefault(name, [])
        if digest(target) not in versions:
            versions.append(digest(target))
    path.write_text(json.dumps(known, indent=2) + '\n', encoding='utf-8')


def duplicates(spec: dict) -> list[str]:
    seen, out = {}, []
    for row in rows(spec):
        combo = normalize(row['keys'])
        binding = (combo, 'release' in row['flags'])
        if binding in seen:
            out.append(combo)
        seen.setdefault(binding, row['description'])
    return out


def main(argv: list[str]) -> int:
    spec = load()
    if '--list' in argv:
        for row in rows(spec):
            print(f"{row['keys']:28} {row['group']:13} {row['description']}" + (('  [' + ' '.join(row['flags']) + ']') if row['flags'] else ''))
        return 0
    bad = duplicates(spec)
    if bad:
        print('keybinds.json binds these combinations twice: ' + ', '.join(bad), file=sys.stderr)
        return 1
    if '--write' in argv:
        for name, path in TARGETS.items():
            path.write_text(render(spec, name), encoding='utf-8')
            print('wrote ' + str(path.relative_to(ROOT)))
        record()
        return 0
    stale = check(spec)
    if stale:
        print('out of date: ' + ', '.join(str(TARGETS[n].relative_to(ROOT)) for n in stale) + ' (run scripts/keybinds.py --write)', file=sys.stderr)
        return 1
    missing = unrecorded()
    if missing:
        print('not in data/keybinds-shipped.json: ' + ', '.join(missing) + ' (run scripts/keybinds.py --write)', file=sys.stderr)
        return 1
    print('themes/keybinds.lua and themes/keybinds.conf match data/keybinds.json')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
