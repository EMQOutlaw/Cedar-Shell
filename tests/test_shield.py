"""shield.py: /proc/net listener parsing and classification, resolvectl parsing, provider mapping."""
from pathlib import Path
import importlib.util
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('shield', ROOT / 'scripts/shield.py')
shield = importlib.util.module_from_spec(spec); spec.loader.exec_module(shield)

TCP = """  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode
   0: 0100007F:0035 00000000:0000 0A 00000000:00000000 00:00000000 00000000   977        0 12345 1 0 100 0 0 10 0
   1: 00000000:0016 00000000:0000 0A 00000000:00000000 00:00000000 00000000     0        0 12346 1 0 100 0 0 10 0
   2: 010200C0:1F90 00000000:0000 0A 00000000:00000000 00:00000000 00000000  1000        0 12347 1 0 100 0 0 10 0
   3: 010200C0:C350 020200C0:01BB 01 00000000:00000000 00:00000000 00000000  1000        0 12348 1 0 100 0 0 10 0
"""
TCP6 = """  sl  local_address                         remote_address                        st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode
   0: 00000000000000000000000001000000:0277 00000000000000000000000000000000:0000 0A 00000000:00000000 00:00000000 00000000  1000        0 22222 1 0 100 0 0 10 0
   1: 00000000000000000000000000000000:1F90 00000000000000000000000000000000:0000 0A 00000000:00000000 00:00000000 00000000  1000        0 22223 1 0 100 0 0 10 0
"""
RESOLVECTL = """Global
         Protocols: -LLMNR -mDNS -DNSOverTLS DNSSEC=no/unsupported
  resolv.conf mode: stub
Fallback DNS Servers: 9.9.9.9#dns.quad9.net

Link 2 (eno1)
    Current Scopes: DNS
         Protocols: +DefaultRoute -LLMNR -mDNS +DNSOverTLS DNSSEC=no/unsupported
Current DNS Server: 1.1.1.1#cloudflare-dns.com
       DNS Servers: 1.1.1.1#cloudflare-dns.com 1.0.0.1#cloudflare-dns.com

Link 3 (wlp8s0)
    Current Scopes: none
         Protocols: -DefaultRoute -LLMNR -mDNS DNSOverTLS=opportunistic
       DNS Servers: 9.9.9.9#dns.quad9.net
"""

class Listeners(unittest.TestCase):
    def test_tcp_listeners_only_and_classified(self):
        rows = shield.parse_proc_net(TCP, 'tcp')
        self.assertEqual([(ip, port) for ip, port, _ in rows], [('127.0.0.1', 53), ('0.0.0.0', 22), ('192.0.2.1', 8080)])
        self.assertEqual([shield.scope_of(ip) for ip, _, _ in rows], ['local', 'all', 'lan'])

    def test_ipv6_addresses(self):
        rows = shield.parse_proc_net(TCP6, 'tcp6')
        self.assertEqual([(ip, port, shield.scope_of(ip)) for ip, port, _ in rows], [('::1', 631, 'local'), ('::', 8080, 'all')])

    def test_exposure_counts_from_a_fixture_tree(self):
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp); (base / 'tcp').write_text(TCP); (base / 'tcp6').write_text(TCP6)
            result = shield.exposure(base)
            self.assertEqual((result['local'], result['lan'], result['all'], result['exposed']), (2, 1, 2, 3))
            self.assertEqual(result['listeners'][0]['scope'], 'all', 'exposed listeners sort first')

class Dns(unittest.TestCase):
    def test_resolvectl_blocks(self):
        blocks = shield.parse_resolvectl(RESOLVECTL)
        self.assertFalse(blocks['global']['dot'])
        self.assertTrue(blocks['eno1']['dot'])
        self.assertEqual(blocks['eno1']['servers'], ['1.1.1.1#cloudflare-dns.com', '1.0.0.1#cloudflare-dns.com'])
        self.assertEqual(blocks['eno1']['dotMode'], 'strict')
        self.assertTrue(blocks['wlp8s0']['dot'], 'opportunistic counts as DNS-over-TLS')
        self.assertEqual(blocks['wlp8s0']['dotMode'], 'opportunistic')
        self.assertEqual(blocks['global']['dotMode'], 'off')

    def test_provider_mapping(self):
        self.assertEqual(shield.provider_for(['1.1.1.1#cloudflare-dns.com']), 'cloudflare')
        self.assertEqual(shield.provider_for(['9.9.9.9#dns.quad9.net']), 'quad9')
        self.assertEqual(shield.provider_for(['192.0.2.1']), 'custom')
        self.assertEqual(shield.provider_for([]), 'network')

    def test_mac_policy_map_round_trips(self):
        for policy, raw in shield.MAC_POLICIES.items():
            self.assertEqual({v: k for k, v in shield.MAC_POLICIES.items()}[raw], policy)

    def test_firewall_commands_per_provider(self):
        self.assertIn('ufw --force enable', shield.firewall_commands('ufw', True)[2])
        self.assertEqual(shield.firewall_commands('firewalld', False), ['systemctl', 'disable', '--now', 'firewalld.service'])
        with self.assertRaises(RuntimeError): shield.firewall_commands('none', True)

if __name__ == '__main__':
    unittest.main()
