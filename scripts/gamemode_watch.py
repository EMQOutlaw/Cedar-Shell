#!/usr/bin/env python3
"""Observe Feral GameMode over D-Bus and print one JSON line per change.

{"clients": N, "available": true|false, "games": [...]}. `games` lists the
executables GameMode has registered (basenames, without common suffixes) so
the preparation panel can say what it is preparing for. Event-driven: a GLib
main loop with a PropertiesChanged subscription and a name-owner watch; no
polling. Runs only while the shell knows GameMode is installed, and exits
with it.
"""
import json
import os
import sys

try:
    import gi
    gi.require_version('Gio', '2.0')
    from gi.repository import Gio, GLib
except (ImportError, ValueError):
    print(json.dumps(dict(available=False, clients=0, reason='Python GLib bindings are not installed.')), flush=True)
    sys.exit(0)

NAME, PATH, IFACE = 'com.feralinteractive.GameMode', '/com/feralinteractive/GameMode', 'com.feralinteractive.GameMode'
SUFFIXES = ('.exe', '.x86_64', '.x86', '.x64', '.bin', '.sh', '.AppImage')


def game_name(executable):
    """A short, readable name from the executable path GameMode reports."""
    name = os.path.basename(str(executable or '')).strip()
    for suffix in SUFFIXES:
        if name.lower().endswith(suffix.lower()):
            name = name[:-len(suffix)]
    return name


def emit(available, clients, games=()):
    print(json.dumps(dict(available=available, clients=int(clients), games=[g for g in games if g])), flush=True)


def main():
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)

    def games():
        """Registered games: ListGames gives (pid, object path); each game
        object carries its Executable. A game that vanished mid-read is skipped."""
        names = []
        try:
            reply = bus.call_sync(NAME, PATH, IFACE, 'ListGames', None, GLib.VariantType('(a(io))'), Gio.DBusCallFlags.NONE, 2000, None)
        except GLib.Error:
            return names
        for _pid, path in reply.unpack()[0]:
            try:
                exe = bus.call_sync(NAME, path, 'org.freedesktop.DBus.Properties', 'Get', GLib.Variant('(ss)', (IFACE + '.Game', 'Executable')),
                                    GLib.VariantType('(v)'), Gio.DBusCallFlags.NONE, 2000, None)
                names.append(game_name(exe.unpack()[0]))
            except GLib.Error:
                continue
        return names

    def read():
        try:
            reply = bus.call_sync(NAME, PATH, 'org.freedesktop.DBus.Properties', 'Get', GLib.Variant('(ss)', (IFACE, 'ClientCount')),
                                  GLib.VariantType('(v)'), Gio.DBusCallFlags.NONE, 2000, None)
            count = reply.unpack()[0]
            emit(True, count, games() if count else ())
        except GLib.Error:
            emit(False, 0)

    def changed(connection, sender, path, iface, signal, params):
        body = params.unpack()
        if body and body[0] == IFACE and 'ClientCount' in (body[1] or {}):
            count = body[1]['ClientCount']
            emit(True, count, games() if count else ())

    bus.signal_subscribe(NAME, 'org.freedesktop.DBus.Properties', 'PropertiesChanged', PATH, None, Gio.DBusSignalFlags.NONE, changed)
    Gio.bus_watch_name(Gio.BusType.SESSION, NAME, Gio.BusNameWatcherFlags.NONE, lambda *_: read(), lambda *_: emit(False, 0))
    GLib.MainLoop().run()


if __name__ == '__main__':
    main()
