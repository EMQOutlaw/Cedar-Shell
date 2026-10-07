#!/usr/bin/env python3
"""Gaming Mode's outside-the-shell steps. One JSON request on stdin, one reply.

compositor capture   -> the current Hyprland runtime values Gaming Mode may change
compositor apply     -> set the requested values with `hyprctl keyword`, then read
                        them back; the reply is what the compositor reports, not
                        what was asked for
gamemode             -> Feral GameMode's client count over D-Bus (observed only)

hyprctl is the supported interface for runtime options; nothing here reloads
the configuration, touches files, or needs privileges.
"""
import json
import os
import subprocess
import sys

OPTIONS = {'blur': 'decoration:blur:enabled', 'animations': 'animations:enabled'}


def lua_config(values):
    """`hl.config` table for Hyprland's Lua parser: {'blur': False} ->
    hl.config({ decoration = { blur = { enabled = false } } })."""
    parts = []
    for key, wanted in values.items():
        path = OPTIONS[key].split(':')
        inner = 'true' if wanted else 'false'
        for name in reversed(path):
            inner = name + ' = ' + ('{ ' + inner + ' }' if name != path[-1] else inner)
        parts.append(inner)
    return 'hl.config({ ' + ', '.join(parts) + ' })'


def run(argv, timeout=6):
    p = subprocess.run(argv, capture_output=True, text=True, timeout=timeout, check=False, env={**os.environ, 'LC_ALL': 'C'})
    if p.returncode:
        raise RuntimeError((p.stderr or p.stdout).strip() or 'hyprctl failed')
    return p.stdout.strip()


def getoption(name):
    data = json.loads(run(['hyprctl', '-j', 'getoption', name]))
    if 'bool' in data:
        return bool(data['bool'])
    if 'int' in data:
        return bool(data['int'])
    raise RuntimeError('Unexpected option shape for ' + name)


def capture():
    return {key: getoption(name) for key, name in OPTIONS.items()}


def apply(values):
    """Set each requested option, then report what Hyprland now says. A value
    that did not take shows up as a mismatch for the shell to report."""
    for key, wanted in values.items():
        if key not in OPTIONS or not isinstance(wanted, bool):
            raise ValueError('Unknown compositor option: ' + str(key))
    # Hyprland with a Lua configuration refuses `keyword`; `eval` with an
    # hl.config table is its runtime interface. Legacy configs still take keyword.
    try:
        out = run(['hyprctl', 'eval', lua_config(values)])
        if out.strip().lower() != 'ok':
            raise RuntimeError(out.strip())
    except RuntimeError as error:
        if 'eval' in str(error).lower() and 'unknown' in str(error).lower() or 'invalid' in str(error).lower():
            for key, wanted in values.items():
                out = run(['hyprctl', 'keyword', OPTIONS[key], 'true' if wanted else 'false'])
                if out and out.strip().lower() != 'ok':
                    raise RuntimeError(out.strip())
        else:
            raise
    return capture()


def gamemode():
    try:
        import gi
        gi.require_version('Gio', '2.0')
        from gi.repository import Gio, GLib
    except (ImportError, ValueError):
        return dict(available=False, clients=0, reason='Python GLib bindings are not installed.')
    try:
        bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        reply = bus.call_sync('com.feralinteractive.GameMode', '/com/feralinteractive/GameMode', 'org.freedesktop.DBus.Properties', 'Get',
                              GLib.Variant('(ss)', ('com.feralinteractive.GameMode', 'ClientCount')), GLib.VariantType('(v)'),
                              Gio.DBusCallFlags.NONE, 2000, None)
        return dict(available=True, clients=int(reply.unpack()[0]))
    except GLib.Error as error:  # name not owned: GameMode is installed but idle, or absent
        return dict(available=False, clients=0, reason=error.message)


def main():
    try:
        req = json.loads(sys.stdin.readline() or '{}')
        action = req.get('action')
        if action == 'compositor':
            mode = req.get('mode')
            if mode == 'capture':
                data = capture()
            elif mode == 'apply':
                data = apply(req.get('values') or {})
            else:
                raise ValueError('Unknown compositor mode')
        elif action == 'gamemode':
            data = gamemode()
        else:
            raise ValueError('Unknown gaming action')
        print(json.dumps(dict(ok=True, data=data)))
    except Exception as error:  # noqa: BLE001
        print(json.dumps(dict(ok=False, error=str(error))))


if __name__ == '__main__':
    main()
