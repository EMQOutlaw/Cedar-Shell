"""Tailscale and Proton VPN are never brought up together; each helper refuses the other."""
import importlib.util
import json
from pathlib import Path
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]


def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / f'scripts/{name}.py')
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    return module


ts = load('tailscale')
proton = load('protonvpn')

RUNNING = json.dumps({
    'BackendState': 'Running', 'Health': [],
    'CurrentTailnet': {'Name': 'example.github', 'MagicDNSSuffix': 'tail1234.ts.net'},
    'Self': {'HostName': 'Desk', 'DNSName': 'desk-1.tail1234.ts.net.',
             'TailscaleIPs': ['fd7a:115c:a1e0::1', '100.76.244.71'], 'Online': True},
    'Peer': {'a': {'HostName': 'laptop', 'DNSName': 'laptop.tail1234.ts.net.', 'Online': True, 'ExitNode': True},
             'b': {'HostName': 'phone', 'DNSName': 'phone-1.tail1234.ts.net.', 'Online': False}}})
STOPPED = json.dumps({'BackendState': 'Stopped', 'Self': {'HostName': 'x', 'TailscaleIPs': []}, 'Peer': None})
NEEDS_LOGIN = json.dumps({'BackendState': 'NeedsLogin'})


class Status(unittest.TestCase):
    def test_running_status_is_summarised(self):
        s = ts.parse_status(RUNNING)
        self.assertTrue(s['up']); self.assertFalse(s['needsLogin'])
        self.assertEqual(s['hostname'], 'desk-1'); self.assertEqual(s['ip'], '100.76.244.71')
        self.assertEqual(s['tailnet'], 'example.github')
        self.assertEqual((s['peers'], s['peersOnline']), (2, 1)); self.assertEqual(s['exitNode'], 'laptop')

    def test_stopped_and_empty_and_garbage_never_raise(self):
        self.assertFalse(ts.parse_status(STOPPED)['up']); self.assertEqual(ts.parse_status(STOPPED)['peers'], 0)
        for raw in ('', 'not json', '[]', '42'):
            s = ts.parse_status(raw); self.assertEqual(s['state'], 'NoState'); self.assertFalse(s['up']); self.assertEqual(s['ip'], '')
        self.assertTrue(ts.parse_status(NEEDS_LOGIN)['needsLogin'])

    def test_snapshot_reports_a_silent_daemon(self):
        with mock.patch.object(ts.shutil, 'which', return_value='/usr/bin/tailscale'), \
             mock.patch.object(ts, 'cli', return_value=(1, '', 'failed to connect to local tailscaled')):
            data = ts.snapshot()
        self.assertTrue(data['installed']); self.assertFalse(data['running']); self.assertIn('tailscaled', data['error'])
        with mock.patch.object(ts.shutil, 'which', return_value=None):
            self.assertEqual(ts.snapshot()['installed'], False)

    def test_proton_connection_is_recognised_by_name(self):
        for names, expected in ((['Home', 'ProtonVPN JP-FREE#1'], True), (['pvpn-killswitch'], True), (['Home', 'tailscale0', 'wg-home'], False), ([], False)):
            with mock.patch.object(ts, 'active_connection_names', return_value=names):
                self.assertEqual(ts.proton_connected(), expected, names)


class Exclusion(unittest.TestCase):
    def test_tailscale_up_refuses_while_proton_is_connected(self):
        calls = []
        with mock.patch.object(ts.shutil, 'which', return_value='/usr/bin/tailscale'), \
             mock.patch.object(ts, 'proton_connected', return_value=True), \
             mock.patch.object(ts, 'cli', side_effect=lambda *a, **k: calls.append(a) or (0, STOPPED, '')):
            with self.assertRaisesRegex(RuntimeError, 'Proton VPN is connected'):
                ts.action({'action': 'up'})
        self.assertEqual(calls, [])

    def test_tailscale_up_sends_signed_out_users_to_a_terminal(self):
        with mock.patch.object(ts.shutil, 'which', return_value='/usr/bin/tailscale'), \
             mock.patch.object(ts, 'proton_connected', return_value=False), \
             mock.patch.object(ts, 'cli', return_value=(0, NEEDS_LOGIN, '')):
            with self.assertRaisesRegex(RuntimeError, 'signed out'):
                ts.action({'action': 'up'})

    def test_tailscale_up_and_down_run_the_cli(self):
        calls = []
        def fake(*args, **kw):
            calls.append(args)
            return (0, RUNNING if args[0] == 'status' else '', '')
        with mock.patch.object(ts.shutil, 'which', return_value='/usr/bin/tailscale'), \
             mock.patch.object(ts, 'proton_connected', return_value=False), mock.patch.object(ts, 'cli', side_effect=fake):
            self.assertTrue(ts.action({'action': 'up'})['status']['up'])
            ts.action({'action': 'down'})
        self.assertIn(('up', '--timeout=45s'), calls); self.assertIn(('down',), calls)

    def test_tailscale_passes_the_cli_refusal_through(self):
        with mock.patch.object(ts.shutil, 'which', return_value='/usr/bin/tailscale'), \
             mock.patch.object(ts, 'cli', return_value=(1, '', 'Access denied: down requires the operator.')):
            with self.assertRaisesRegex(RuntimeError, 'Access denied'):
                ts.action({'action': 'down'})

    def test_proton_connect_refuses_while_tailscale_is_up(self):
        calls = []
        with mock.patch.object(proton.shutil, 'which', return_value='/usr/bin/protonvpn'), \
             mock.patch.object(proton, 'tailscale_up', return_value=True), \
             mock.patch.object(proton, 'cli', side_effect=lambda *a, **k: calls.append(a) or (0, '', '')):
            with self.assertRaisesRegex(RuntimeError, 'Tailscale is up'):
                proton.action({'action': 'connect', 'target': 'fastest'})
            # Disconnecting is never blocked: it only ever reduces the overlap.
            proton.action({'action': 'disconnect'})
        self.assertNotIn(('connect',), calls); self.assertIn(('disconnect',), calls)

    def test_proton_connect_proceeds_when_tailscale_is_down_or_absent(self):
        calls = []
        with mock.patch.object(proton.shutil, 'which', return_value='/usr/bin/protonvpn'), \
             mock.patch.object(proton, 'tailscale_up', return_value=False), \
             mock.patch.object(proton, 'cli', side_effect=lambda *a, **k: calls.append(a) or (0, '', '')):
            proton.action({'action': 'connect', 'target': 'country', 'country': 'jp'})
        self.assertIn(('connect', '--country', 'JP'), calls)

    def test_tailscale_up_probe_tolerates_a_missing_or_silent_cli(self):
        with mock.patch.object(proton.shutil, 'which', return_value=None):
            self.assertFalse(proton.tailscale_up())
        silent = mock.Mock(stdout='', returncode=1)
        with mock.patch.object(proton.shutil, 'which', return_value='/usr/bin/tailscale'), \
             mock.patch.object(proton.subprocess, 'run', return_value=silent):
            self.assertFalse(proton.tailscale_up())
        with mock.patch.object(proton.shutil, 'which', return_value='/usr/bin/tailscale'), \
             mock.patch.object(proton.subprocess, 'run', return_value=mock.Mock(stdout=RUNNING, returncode=0)):
            self.assertTrue(proton.tailscale_up())


if __name__ == '__main__':
    unittest.main()
