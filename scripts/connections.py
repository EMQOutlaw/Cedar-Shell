#!/usr/bin/env python3
"""NetworkManager controls. Requests (including secrets) arrive over stdin only."""
import json
import os
import subprocess
import sys
import time
import uuid

NM = 'org.freedesktop.NetworkManager'
BASE = '/org/freedesktop/NetworkManager'


def link_status(manager, connections, devices, networks):
    """Select the primary underlay, never a loopback or VPN profile.

    NM's PrimaryConnection identifies the VPN endpoint's underlay when a VPN
    owns the default route. Default/default6 then physical links are fallbacks.
    Internet verification remains a separate NetworkManager property.
    """
    by_path = {d['path']: d for d in devices if d['type'] != 32 and d['name'] != 'lo'}
    links, vpns = [], []
    for connection in connections:
        c = dict(connection)
        if c.get('vpn') or c['type'] in ('vpn', 'wireguard'):
            if c['state'] == 2:
                vpns.append({'name': c['name'], 'path': c['path']})
            continue
        if c['type'] == 'loopback' or c['state'] not in (1, 2):
            continue
        attached = [by_path[p] for p in c['devices'] if p in by_path]
        if not attached:
            continue
        physical = next((d for d in attached if d['type'] in (1, 2, 8)), attached[0])
        c['kind'] = {1: 'wired', 2: 'wifi', 8: 'mobile'}.get(physical['type'], 'unknown')
        c['device'] = physical['path']
        # A local virtual bridge without a route is not desktop connectivity.
        if c['kind'] == 'unknown' and not (c['default'] or c['default6'] or c['path'] == manager.get('PrimaryConnection')):
            continue
        links.append(c)
    links.sort(key=lambda c: (c['state'] != 2, c['path'] != manager.get('PrimaryConnection'),
                             not (c['default'] or c['default6']), c['kind'] == 'unknown', c['path']))
    current = links[0] if links else None
    state = 'connected' if current and current['state'] == 2 else 'connecting' if current else 'disconnected'
    # A device can be preparing/asking for credentials before an active
    # connection object has appeared in the next D-Bus snapshot.
    if not current and any(d['type'] in (1, 2, 8) and 40 <= d['state'] <= 90 for d in by_path.values()):
        state = 'connecting'
    if not current and (not by_path or all(d['state'] <= 20 for d in by_path.values())):
        state = 'unavailable'
    kind = current['kind'] if current else 'unknown'
    ap = next((a for a in networks if a['active'] and current and a['device'] == current['device']), None)
    label = ap['ssid'] if kind == 'wifi' and ap else {'wired': 'Wired connection', 'wifi': 'Wi-Fi', 'mobile': 'Mobile network'}.get(kind, 'Network connection')
    if state != 'connected':
        label = {'connecting': 'Connecting…', 'disconnected': 'Network disconnected', 'unavailable': 'Network unavailable'}[state]
    return {'state': state, 'kind': kind, 'label': label, 'strength': ap['strength'] if ap else None,
            'vpns': vpns, 'connection': current['path'] if current else '',
            'internet': {0: 'unknown', 1: 'none', 2: 'portal', 3: 'limited', 4: 'verified'}.get(int(manager.get('Connectivity', 0)), 'unknown')}

class Network:
    def __init__(self):
        import dbus
        self.dbus = dbus
        self.bus = dbus.SystemBus()
        self.manager = self.interface(BASE, NM)

    def interface(self, path, iface):
        return self.dbus.Interface(self.bus.get_object(NM, path), iface)

    def props(self, path, iface):
        return self.interface(path, 'org.freedesktop.DBus.Properties').GetAll(iface, timeout=3)

    def active_connections(self, manager):
        result = []
        for path in manager.get('ActiveConnections', []):
            try:
                c = self.props(path, NM+'.Connection.Active')
                result.append({'path': str(path), 'profile': str(c.get('Connection', '/')),
                    'name': str(c.get('Id', '')), 'type': str(c.get('Type', '')),
                    'state': int(c.get('State', 0)), 'vpn': bool(c.get('Vpn', False)),
                    'default': bool(c.get('Default', False)), 'default6': bool(c.get('Default6', False)),
                    'devices': [str(d) for d in c.get('Devices', [])]})
            except self.dbus.DBusException:
                continue  # Device/connection vanished during this snapshot.
        return result

    def saved(self, connections=None):
        result = []
        if connections is None:
            connections = self.active_connections(self.props(BASE, NM))
        active = {c['profile']: c['path'] for c in connections if c['state'] in (1, 2)}
        for path in self.interface(BASE+'/Settings', NM+'.Settings').ListConnections():
            try:
                data = self.interface(path, NM+'.Settings.Connection').GetSettings()
                c = data['connection']
                wifi = data.get('802-11-wireless', {})
                result.append({'path': str(path), 'name': str(c['id']), 'type': str(c['type']),
                    'active': active.get(str(path), ''), 'uuid':str(c.get('uuid','')), 'autoconnect':bool(c.get('autoconnect',True)), 'ssid': bytes(wifi.get('ssid', [])).decode('utf-8', 'replace'), 'mode': str(wifi.get('mode', ''))})
            except self.dbus.DBusException:
                continue
        return result

    def snapshot(self, detailed=True):
        settings = self.props(BASE, NM)
        connections = self.active_connections(settings)
        saved = self.saved(connections) if detailed else []
        devices, networks = [], []
        for path in settings['Devices']:
            dev = self.props(path, NM+'.Device')
            item = {'path': str(path), 'name': str(dev['Interface']), 'type': int(dev['DeviceType']), 'state': int(dev['State'])}
            devices.append(item)
            if dev['DeviceType'] != 2 or not detailed:
                continue
            wifi = self.props(path, NM+'.Device.Wireless')
            item['hotspotCapable'] = bool(int(wifi.get('WirelessCapabilities',0)) & 0x40)
            for ap in wifi.get('AccessPoints', []):
                p = self.props(ap, NM+'.AccessPoint')
                ssid = bytes(p['Ssid']).decode('utf-8', 'replace')
                if not ssid:
                    continue
                flags = int(p['RsnFlags']) | int(p['WpaFlags'])
                security = 'enterprise' if flags & 512 else 'sae' if flags & 1024 and not flags & 256 else 'wpa-psk' if flags & 256 else 'unsupported' if int(p['Flags']) & 1 else 'open'
                networks.append({'path': str(ap), 'device': str(path), 'ssid': ssid, 'strength': int(p['Strength']),
                    'security': security, 'active': str(wifi['ActiveAccessPoint']) == str(ap),
                    'saved': next((c['path'] for c in saved if c['ssid'] == ssid), '')})
        # One strongest AP per SSID/security/device; prefer the currently connected AP.
        unique = {}
        for ap in sorted(networks, key=lambda x: (x['active'], x['strength']), reverse=True):
            unique.setdefault((ap['ssid'], ap['security'], ap['device']), ap)
        status = link_status(settings, connections, devices, networks)
        # Active connections ride along in every snapshot, so change detection
        # never depends on the detailed rows that only an open panel samples.
        active = [{'path': c['path'], 'name': c['name'], 'type': c['type'], 'state': c['state'], 'vpn': c['vpn'], 'default': c['default'] or c['default6']}
                  for c in connections if c['state'] in (1, 2)]
        return {'available': True, 'enabled': bool(settings['WirelessEnabled']),
            'hardware': bool(settings['WirelessHardwareEnabled']), 'connectivity': int(settings.get('Connectivity', 0)), 'devices': devices,
            'networks': list(unique.values()), 'saved': saved, 'active': active, 'label': status['label'], 'status': status}

    def wait_active(self, path):
        deadline = time.monotonic() + 35
        while time.monotonic() < deadline:
            try:
                state = int(self.props(path, NM+'.Connection.Active')['State'])
            except self.dbus.DBusException:
                raise RuntimeError('Connection ended before it became active. Check the password or network availability.')
            if state == 2:
                return
            if state == 4:
                raise RuntimeError('Connection failed. Check the password or network availability.')
            time.sleep(.3)
        raise RuntimeError('Connection is still pending. Check its status before retrying.')

    def action(self, req):
        action = req['action']
        if action == 'radio':
            self.interface(BASE, 'org.freedesktop.DBus.Properties').Set(NM, 'WirelessEnabled', self.dbus.Boolean(req['enabled']))
        elif action == 'scan':
            for dev in self.snapshot()['devices']:
                if dev['type'] == 2:
                    self.interface(dev['path'], NM+'.Device.Wireless').RequestScan(self.dbus.Dictionary({}, signature='sv'))
        elif action in ('forget', 'activate', 'deactivate', 'autoconnect'):
            saved = next((x for x in self.saved() if x['path'] == req['path']), None)
            if not saved:
                raise ValueError('This saved connection no longer exists. Refresh the list.')
            if action == 'autoconnect':
                if type(req.get('enabled')) is not bool: raise ValueError('Automatic connection requires true or false.')
                # nmcli modifies this one property without replacing unrelated settings or secrets.
                result=subprocess.run(['nmcli','connection','modify','uuid',saved['uuid'],'connection.autoconnect','yes' if req['enabled'] else 'no'],text=True,capture_output=True,timeout=15)
                if result.returncode: raise RuntimeError(result.stderr.strip() or 'Could not change automatic connection.')
            elif action == 'forget':
                self.interface(saved['path'], NM+'.Settings.Connection').Delete()
            elif action == 'deactivate':
                if saved['active']:
                    self.manager.DeactivateConnection(saved['active'])
            else:
                self.wait_active(self.manager.ActivateConnection(saved['path'], '/', '/'))
        elif action == 'disconnect':
            device = next((d for d in self.snapshot()['devices'] if d['path'] == req['device']), None)
            if not device:
                raise ValueError('Adapter is no longer present.')
            self.interface(device['path'], NM+'.Device').Disconnect()
        elif action == 'connect':
            ap = next((a for a in self.snapshot()['networks'] if a['path'] == req['path']), None)
            if not ap:
                raise ValueError('Network is no longer visible. Scan again.')
            if ap['saved']:
                self.wait_active(self.manager.ActivateConnection(ap['saved'], ap['device'], ap['path']))
                return
            if ap['security'] in ('enterprise', 'unsupported'):
                raise ValueError('Configure this network’s enterprise/WEP credentials in the network editor first.')
            p = self.props(ap['path'], NM+'.AccessPoint')
            c = {'connection': {'id': ap['ssid'], 'uuid': str(uuid.uuid4()), 'type': '802-11-wireless'},
                 '802-11-wireless': {'ssid': self.dbus.ByteArray(bytes(p['Ssid']))},
                 'ipv4': {'method': 'auto'}, 'ipv6': {'method': 'auto'}}
            if ap['security'] != 'open':
                password = req.get('password', '')
                if not password:
                    raise ValueError('Enter the network password.')
                c['802-11-wireless-security'] = {'key-mgmt': ap['security'], 'psk': password}
            _, active = self.manager.AddAndActivateConnection(c, ap['device'], ap['path'])
            self.wait_active(active)
        elif action == 'hotspot':
            device = next((d for d in self.snapshot()['devices'] if d['type'] == 2 and d['path'] == req['device']), None)
            if not device:
                raise ValueError('Select a Wi-Fi adapter.')
            if not device.get('hotspotCapable'):
                raise ValueError('This adapter does not report access-point support.')
            if req.get('approveDisconnect') is not True:
                raise ValueError('Starting a hotspot can disconnect this adapter. Confirm that change first.')
            password, ssid = req.get('password', ''), req.get('ssid', '').strip()
            if not 8 <= len(password) <= 63 or not 1 <= len(ssid.encode()) <= 32:
                raise ValueError('Hotspot needs a name of 1–32 bytes and a password of 8–63 characters.')
            c = {'connection': {'id': 'CEDAR hotspot', 'uuid': str(uuid.uuid4()), 'type': '802-11-wireless', 'autoconnect': False},
                 '802-11-wireless': {'ssid': self.dbus.ByteArray(ssid.encode()), 'mode': 'ap'},
                 '802-11-wireless-security': {'key-mgmt': 'wpa-psk', 'psk': password},
                 'ipv4': {'method': 'shared'}, 'ipv6': {'method': 'disabled'}}
            _, active = self.manager.AddAndActivateConnection(c, device['path'], '/')
            self.wait_active(active)
        else:
            raise ValueError('Unknown network action.')


AP_PREFIX = BASE + '/AccessPoint/'

def relevant(path, expanded):
    """Access-point property churn (signal strength) only matters while a
    network list is on screen. Everything else (devices, active connections,
    settings, the service itself) always produces a fresh snapshot."""
    return expanded or not str(path or '').startswith(AP_PREFIX)


def watch():
    from dbus.mainloop.glib import DBusGMainLoop
    from gi.repository import GLib
    import dbus
    DBusGMainLoop(set_as_default=True)
    bus=dbus.SystemBus()
    loop=GLib.MainLoop()
    state={'sequence':0,'pending':0,'expanded':False}
    generation=uuid.uuid4().hex
    def publish():
        state['pending']=0
        try: data=Network().snapshot(state['expanded'])
        except dbus.DBusException: data={'available':False,'devices':[],'networks':[],'saved':[],'active':[],'label':'Network unavailable'}
        state['sequence']+=1
        line=json.dumps({'schema':1,'generation':generation,'sequence':state['sequence'],'kind':'snapshot','data':data})
        if len(line.encode())>4*1024*1024: loop.quit(); return False
        print(line,flush=True)
        return False
    def changed(*args,**kwargs):
        if not relevant(kwargs.get('path'),state['expanded']):return
        if not state['pending']:state['pending']=GLib.timeout_add(200 if state['expanded'] else 600,publish)
    # Subscribe before the first snapshot. Events queued while sampling schedule
    # another complete revision; reconnects establish fresh service objects.
    matches=[bus.add_signal_receiver(changed,bus_name=NM,path_keyword='path'),
             bus.add_signal_receiver(changed,signal_name='NameOwnerChanged',dbus_interface='org.freedesktop.DBus',arg0=NM)]
    os.set_blocking(sys.stdin.fileno(),False)
    buffer=bytearray()
    def incoming(fd,condition):
        data=os.read(fd,4096)
        if not data:loop.quit();return False
        buffer.extend(data)
        if len(buffer)>65536:loop.quit();return False
        while b'\n' in buffer:
            line,_,tail=buffer.partition(b'\n');buffer[:]=tail
            try:
                request=json.loads(line)
                if request.get('action')=='expanded':state['expanded']=request.get('value') is True
                elif request.get('action')!='refresh':continue
                changed()
            except (ValueError,AttributeError):loop.quit();return False
        return True
    GLib.io_add_watch(sys.stdin.fileno(),GLib.IO_IN|GLib.IO_HUP,incoming)
    changed()
    try:loop.run()
    finally:
        for match in matches:match.remove()
        if state['pending']:GLib.source_remove(state['pending'])


def main():
    req = {}
    try:
        req = json.loads(sys.stdin.readline())
        network = Network()
        if req.get('action', 'snapshot') != 'snapshot':
            network.action(req)
        print(json.dumps({'ok': True, 'data': network.snapshot()}))
    except Exception as e:
        # A service may include supplied values in errors. Never echo a secret.
        message = str(e)
        if req.get('password'):
            message = message.replace(req['password'], '[redacted]')
        print(json.dumps({'ok': False, 'error': message}))

if __name__ == '__main__':
    if sys.argv[1:]==['--watch']: watch()
    else: main()
