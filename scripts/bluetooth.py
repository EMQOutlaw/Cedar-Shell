#!/usr/bin/env python3
"""One Bluetooth action; pairing challenges use the same local JSON pipe."""
import json
import select
import sys

def emit(value):
    print(json.dumps(value), flush=True)

def main():
    import dbus
    import dbus.service
    from dbus.mainloop.glib import DBusGMainLoop
    from gi.repository import GLib
    DBusGMainLoop(set_as_default=True)
    bus = dbus.SystemBus()
    request = json.loads(sys.stdin.readline())
    path = request['path']
    objects = dbus.Interface(bus.get_object('org.bluez','/'), 'org.freedesktop.DBus.ObjectManager').GetManagedObjects()
    if path not in objects or 'org.bluez.Device1' not in objects[path]:
        raise ValueError('This Bluetooth device is no longer available.')
    device = dbus.Interface(bus.get_object('org.bluez',path), 'org.bluez.Device1')
    action = request['action']
    if action != 'pair':
        if action == 'connect': device.Connect(timeout=30)
        elif action == 'disconnect': device.Disconnect(timeout=15)
        elif action == 'trust':
            dbus.Interface(bus.get_object('org.bluez',path),'org.freedesktop.DBus.Properties').Set('org.bluez.Device1','Trusted',dbus.Boolean(request['value']))
        elif action == 'forget':
            adapter = objects[path]['org.bluez.Device1']['Adapter']
            dbus.Interface(bus.get_object('org.bluez',adapter),'org.bluez.Adapter1').RemoveDevice(path)
        else: raise ValueError('Unknown Bluetooth action.')
        emit({'ok':True}); return

    class Rejected(dbus.DBusException):
        _dbus_error_name = 'org.bluez.Error.Rejected'

    class Agent(dbus.service.Object):
        def challenge(self, kind, message):
            emit({'prompt':kind, 'message':message})
            if not select.select([sys.stdin],[],[],45)[0]: raise Rejected('Pairing confirmation timed out.')
            reply = json.loads(sys.stdin.readline())
            if not reply.get('accept'): raise Rejected('Pairing cancelled.')
            return reply.get('value','')
        @dbus.service.method('org.bluez.Agent1',in_signature='',out_signature='')
        def Release(self): pass
        @dbus.service.method('org.bluez.Agent1',in_signature='o',out_signature='s')
        def RequestPinCode(self, device): return self.challenge('pin','Enter the PIN shown on the device.')
        @dbus.service.method('org.bluez.Agent1',in_signature='o',out_signature='u')
        def RequestPasskey(self, device):
            value=self.challenge('passkey','Enter the six-digit passkey.')
            if not value.isdigit() or not 0 <= int(value) <= 999999: raise Rejected('Invalid passkey.')
            return dbus.UInt32(int(value))
        @dbus.service.method('org.bluez.Agent1',in_signature='ou',out_signature='')
        def RequestConfirmation(self, device, passkey): self.challenge('confirm', f'Does the device show {int(passkey):06d}?')
        @dbus.service.method('org.bluez.Agent1',in_signature='o',out_signature='')
        def RequestAuthorization(self, device): self.challenge('confirm','Allow this device to pair?')
        @dbus.service.method('org.bluez.Agent1',in_signature='os',out_signature='')
        def AuthorizeService(self, device, service): self.challenge('confirm','Allow the device to use this Bluetooth service?')
        @dbus.service.method('org.bluez.Agent1',in_signature='os',out_signature='')
        def DisplayPinCode(self, device, pin): emit({'prompt':'display','message':'Enter this PIN on the device: '+str(pin)})
        @dbus.service.method('org.bluez.Agent1',in_signature='ouq',out_signature='')
        def DisplayPasskey(self, device, passkey, entered): emit({'prompt':'display','message':f'Enter {int(passkey):06d} on the device ({entered} digits entered).'})
        @dbus.service.method('org.bluez.Agent1',in_signature='',out_signature='')
        def Cancel(self): emit({'prompt':'','message':'Pairing cancelled.'})

    agent = Agent(bus,'/org/cedar/Pairing')
    manager = dbus.Interface(bus.get_object('org.bluez','/org/bluez'),'org.bluez.AgentManager1')
    manager.RegisterAgent('/org/cedar/Pairing','KeyboardDisplay')
    loop = GLib.MainLoop()
    def done(*args): emit({'ok':True}); loop.quit()
    def failed(error): emit({'ok':False,'error':str(error)}); loop.quit()
    device.Pair(reply_handler=done,error_handler=failed,timeout=90)
    loop.run()
    manager.UnregisterAgent('/org/cedar/Pairing')

if __name__ == '__main__':
    try: main()
    except Exception as error: emit({'ok':False,'error':str(error)})
