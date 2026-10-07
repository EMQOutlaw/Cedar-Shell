#!/usr/bin/env python3
"""Observe Feral GameMode over D-Bus and print one JSON line per change.

{"clients": N, "available": true|false}. Event-driven: a GLib main loop with a
PropertiesChanged subscription and a name-owner watch; no polling. Runs only
while the shell knows GameMode is installed, and exits with it.
"""
import json
import sys

try:
    import gi
    gi.require_version('Gio', '2.0')
    from gi.repository import Gio, GLib
except (ImportError, ValueError):
    print(json.dumps(dict(available=False, clients=0, reason='Python GLib bindings are not installed.')), flush=True)
    sys.exit(0)

NAME, PATH, IFACE = 'com.feralinteractive.GameMode', '/com/feralinteractive/GameMode', 'com.feralinteractive.GameMode'


def emit(available, clients):
    print(json.dumps(dict(available=available, clients=int(clients))), flush=True)


def main():
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)

    def read():
        try:
            reply = bus.call_sync(NAME, PATH, 'org.freedesktop.DBus.Properties', 'Get', GLib.Variant('(ss)', (IFACE, 'ClientCount')),
                                  GLib.VariantType('(v)'), Gio.DBusCallFlags.NONE, 2000, None)
            emit(True, reply.unpack()[0])
        except GLib.Error:
            emit(False, 0)

    def changed(connection, sender, path, iface, signal, params):
        body = params.unpack()
        if body and body[0] == IFACE and 'ClientCount' in (body[1] or {}):
            emit(True, body[1]['ClientCount'])

    bus.signal_subscribe(NAME, 'org.freedesktop.DBus.Properties', 'PropertiesChanged', PATH, None, Gio.DBusSignalFlags.NONE, changed)
    Gio.bus_watch_name(Gio.BusType.SESSION, NAME, Gio.BusNameWatcherFlags.NONE, lambda *_: read(), lambda *_: emit(False, 0))
    GLib.MainLoop().run()


if __name__ == '__main__':
    main()
