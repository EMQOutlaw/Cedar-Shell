"""Network presentation must follow a real underlay, independent of profile order."""
import importlib.util
from pathlib import Path
import unittest
spec = importlib.util.spec_from_file_location('connections', Path(__file__).resolve().parents[1]/'scripts/connections.py')
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)

def device(name, kind, state=100):
    return dict(path='/device/'+name, name=name, type=kind, state=state)
def connection(name, kind, dev, state=2, default=False):
    return dict(path='/active/'+name, name=name, type=kind, devices=['/device/'+dev], state=state, default=default, default6=False)

class NetworkSelection(unittest.TestCase):
    def setUp(self):
        self.devices=[device('lo',32), device('ether',1), device('wireless',2),device('tunnel',16)]
        self.lo=connection('lo','loopback','lo')
        self.eth=connection('Office cable','802-3-ethernet','ether',default=True)
        self.wifi=connection('Home','802-11-wireless','wireless',default=True)
        self.vpn=connection('VPN','wireguard','tunnel',default=True)
        self.ap=dict(ssid='Fixture Wi-Fi',device='/device/wireless',active=True,strength=82)
    def status(self, rows, primary='', connectivity=0, devices=None):
        return m.link_status({'PrimaryConnection':primary,'Connectivity':connectivity},rows,self.devices if devices is None else devices,[self.ap])
    def test_loopback_first_never_selected(self):
        s=self.status([self.lo,self.eth]);self.assertEqual(s['kind'],'wired');self.assertEqual(s['label'],'Wired connection')
    def test_primary_wins_over_profile_order(self):
        for rows in ([self.wifi,self.eth],[self.eth,self.wifi]):
            self.assertEqual(self.status(rows,self.eth['path'])['kind'],'wired')
            self.assertEqual(self.status(rows,self.wifi['path'])['label'],'Fixture Wi-Fi')
    def test_vpn_preserves_underlay(self):
        for kind in ('vpn','wireguard'):
            self.vpn['type']=kind
            s=self.status([self.vpn,self.lo,self.eth],self.eth['path'])
            self.assertEqual(s['kind'],'wired');self.assertEqual(len(s['vpns']),1)
    def test_tunnel_alone_is_not_wifi(self):
        s=self.status([self.vpn]);self.assertEqual(s['state'],'disconnected');self.assertEqual(s['kind'],'unknown');self.assertEqual(len(s['vpns']),1)
    def test_connecting_does_not_displace_live_connection(self):
        self.wifi['state']=1
        self.assertEqual(self.status([self.wifi,self.eth],self.wifi['path'])['kind'],'wired')
        self.assertEqual(self.status([self.wifi])['state'],'connecting')
    def test_preparing_device_and_disconnected(self):
        self.assertEqual(self.status([],devices=[device('wireless',2,60)])['state'],'connecting')
        self.assertEqual(self.status([],devices=[device('wireless',2,30)])['state'],'disconnected')
    def test_unmanaged_and_unavailable_adapters(self):
        for state in (0,10,20):
            self.assertEqual(self.status([],devices=[device('ether',1,state)])['state'],'unavailable')
    def test_loopback_only_and_unknown_virtual(self):
        self.assertEqual(self.status([self.lo],devices=[self.devices[0]])['state'],'unavailable')
        bridge=connection('Bridge','bridge','bridge')
        self.assertEqual(self.status([bridge],devices=[device('bridge',13)])['state'],'disconnected')
        s=self.status([bridge],bridge['path'],devices=[device('bridge',13)])
        self.assertEqual(s['state'],'connected');self.assertEqual(s['kind'],'unknown')
    def test_link_and_internet_are_separate(self):
        for code,expected in ((0,'unknown'),(1,'none'),(2,'portal'),(3,'limited'),(4,'verified'),(999,'unknown')):
            s=self.status([self.eth],connectivity=code)
            self.assertEqual(s['state'],'connected');self.assertEqual(s['internet'],expected)
    def test_ipv6_default_fallback(self):
        self.eth['default']=False;self.wifi['default']=False;self.wifi['default6']=True
        self.assertEqual(self.status([self.eth,self.wifi])['kind'],'wifi')
    def test_deactivated_connection_and_unknown_device(self):
        self.eth['state']=4
        self.assertEqual(self.status([self.eth])['state'],'disconnected')
        self.eth['state']=2;self.eth['devices']=['/vanished']
        self.assertEqual(self.status([self.eth])['state'],'disconnected')

if __name__=='__main__':unittest.main()
