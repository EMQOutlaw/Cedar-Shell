"""Shield recovery against stateful command fixtures; never run system commands."""
import copy
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import shield


class ShieldTransactions(unittest.TestCase):
    def setUp(self):
        self.fields = {'802-11-wireless.cloned-mac-address': '', 'ipv6.ip6-privacy': '1',
                       'connection.mdns': '2', 'connection.llmnr': '2'}
        self.live = dict(self.fields)
        self.units = {'avahi-daemon.socket': ('active', 'enabled'), 'avahi-daemon.service': ('active', 'enabled'),
                      'firewalld.service': ('active', 'disabled')}
        self.provider = 'firewalld'
        self.ufw_enabled = False
        self.commands = []
        self.fail_after = None
        self.block_restore = False
        self.connection = {'uuid': 'fixture', 'device': 'fixture0'}
        replacements = [(shield, 'run', {'side_effect': self.command}),
                        (shield, 'default_device', {'return_value': 'fixture0'}),
                        (shield, 'active_connection', {'return_value': self.connection}),
                        (shield, 'nm_fields', {'side_effect': lambda uuid, fields: {key: self.fields[key] for key in fields}}),
                        (shield, 'wifi_profile', {'side_effect': self.wifi}),
                        (shield, 'ipv6_privacy', {'side_effect': self.ipv6}),
                        (shield.capabilities, 'unit_state', {'side_effect': lambda unit: self.units.get(unit, ('inactive', 'not-found'))}),
                        (shield.capabilities, 'privilege', {'return_value': {'helper': 'pkexec', 'agent': True}}),
                        (shield.capabilities, 'firewall', {'side_effect': self.firewall})]
        for module, name, kwargs in replacements:
            active = patch.object(module, name, **kwargs)
            active.start()
            self.addCleanup(active.stop)

    def wifi(self):
        raw = self.fields['802-11-wireless.cloned-mac-address']
        return {'available': True, 'connection': 'fixture', 'connected': True, 'raw': raw,
                'policy': {value: key for key, value in shield.MAC_POLICIES.items()}.get(raw, 'default')}

    def ipv6(self, connection):
        value = self.fields['ipv6.ip6-privacy']
        return {'active': value == '2', 'setting': value, 'kernel': self.live['ipv6.ip6-privacy']}

    def firewall(self):
        unit = self.provider + '.service'
        active, enabled = self.units[unit]
        row = {'provider': self.provider, 'active': active == 'active', 'enabled': enabled == 'enabled',
               'configured': self.ufw_enabled if self.provider == 'ufw' else True}
        return {'provider': self.provider, 'active': row['active'], 'providers': [row]}

    def command(self, argv, **kwargs):
        self.commands.append(argv)
        if self.block_restore:
            raise RuntimeError('fixture recovery denied')
        if argv[:3] == ['nmcli', 'connection', 'modify']:
            self.fields.update(dict(zip(argv[4::2], argv[5::2])))
        elif argv[:3] in (['nmcli', 'device', 'reapply'], ['nmcli', 'connection', 'up']):
            self.live = dict(self.fields)
        elif argv[:2] == ['pkexec', 'systemctl']:
            operation = argv[2]
            for unit in argv[3:]:
                if unit.startswith('--'):
                    continue
                active, enabled = self.units[unit]
                if operation in ('enable', 'disable'):
                    enabled = 'enabled' if operation == 'enable' else 'disabled'
                    if '--now' in argv:
                        active = 'active' if operation == 'enable' else 'inactive'
                elif operation in ('start', 'stop'):
                    active = 'active' if operation == 'start' else 'inactive'
                self.units[unit] = (active, enabled)
        elif argv[:2] == ['pkexec', 'ufw']:
            self.ufw_enabled = argv[-1] == 'enable'
        elif argv[:3] == ['pkexec', '/bin/sh', '-c']:
            enabled = 'ufw --force enable' in argv[3]
            self.ufw_enabled = enabled
            self.units['ufw.service'] = ('active', 'enabled') if enabled else ('inactive', 'disabled')
        elif argv != ['resolvectl', 'status']:
            raise AssertionError('unexpected command: ' + repr(argv))
        if self.fail_after and self.fail_after(argv):
            self.fail_after = None
            raise shield.subprocess.TimeoutExpired(argv, 20)
        if argv == ['resolvectl', 'status']:
            mdns = '+' if self.live['connection.mdns'] == '2' else '-'
            llmnr = '+' if self.live['connection.llmnr'] == '2' else '-'
            return f'Link 2 (fixture0)\n Protocols: {mdns}mDNS {llmnr}LLMNR\n'
        return 'successfully'

    def state(self):
        return copy.deepcopy((self.fields, self.live, self.units, self.ufw_enabled))

    def test_non_boolean_requests_are_refused_before_any_command(self):
        for method in (shield.apply_ipv6, shield.apply_discovery, shield.apply_firewall):
            for value in ('false', 0, None):
                with self.subTest(action=method.__name__, value=value), self.assertRaises(ValueError):
                    method({'enable': value})
        self.assertEqual(self.commands, [])

    def test_wifi_verification_error_restores_exact_empty_default(self):
        before = self.state()
        with patch.object(shield, 'wifi_profile', side_effect=[self.wifi(), OSError('unavailable')]):
            with self.assertRaisesRegex(RuntimeError, 'previous settings were restored'):
                shield.apply_wifi({'policy': 'random'})
        self.assertEqual(self.state(), before)

    def test_wifi_timeout_after_profile_write_is_recovered(self):
        before = self.state()
        self.fail_after = lambda argv: argv[:3] == ['nmcli', 'connection', 'modify']
        with self.assertRaisesRegex(RuntimeError, 'previous settings were restored'):
            shield.apply_wifi({'policy': 'random'})
        self.assertEqual(self.state(), before)

    def test_ipv6_reapply_timeout_restores_saved_and_live_fields(self):
        before = self.state()
        self.fail_after = lambda argv: argv[:3] == ['nmcli', 'device', 'reapply']
        with self.assertRaisesRegex(RuntimeError, 'previous settings were restored'):
            shield.apply_ipv6({'enable': True})
        self.assertEqual(self.state(), before)
        self.assertEqual(sum(argv[:3] == ['nmcli', 'device', 'reapply'] for argv in self.commands), 2)

    def test_ipv6_verification_exception_is_recovered(self):
        before = self.state()
        with patch.object(shield, 'ipv6_privacy', side_effect=[self.ipv6(self.connection), OSError('kernel unavailable'), self.ipv6(self.connection)]):
            with self.assertRaisesRegex(RuntimeError, 'previous settings were restored'):
                shield.apply_ipv6({'enable': True})
        self.assertEqual(self.state(), before)

    def test_profile_switch_is_not_overwritten_by_reapply_or_rollback(self):
        before = dict(self.fields)
        original = self.command
        def switch_after_profile_write(argv, **kwargs):
            result = original(argv, **kwargs)
            if argv[:3] == ['nmcli', 'connection', 'modify']:
                self.connection['uuid'] = 'independently-selected-profile'
            return result
        with patch.object(shield, 'run', side_effect=switch_after_profile_write):
            with self.assertRaisesRegex(RuntimeError, 'active connection changed and was left untouched'):
                shield.apply_ipv6({'enable': True})
        self.assertEqual(self.fields, before)
        self.assertEqual(self.connection['uuid'], 'independently-selected-profile')
        self.assertFalse(any(argv[:3] in (['nmcli', 'device', 'reapply'], ['nmcli', 'connection', 'up']) for argv in self.commands))

    def test_live_ipv6_restore_mismatch_is_reported(self):
        before = self.ipv6(self.connection)
        self.fail_after = lambda argv: argv[:3] == ['nmcli', 'device', 'reapply']
        with patch.object(shield, 'ipv6_privacy', side_effect=[before, {**before, 'kernel': '2'}]):
            with self.assertRaisesRegex(RuntimeError, 'could not be restored'):
                shield.apply_ipv6({'enable': True})

    def test_discovery_partial_avahi_timeout_restores_both_units_and_resolver(self):
        before = self.state()
        self.fail_after = lambda argv: argv[:3] == ['pkexec', 'systemctl', 'disable']
        with self.assertRaisesRegex(RuntimeError, 'previous settings were restored'):
            shield.apply_discovery({'enable': False})
        self.assertEqual(self.state(), before)

    def test_discovery_post_change_verification_error_restores_units(self):
        before = self.state()
        with patch.object(shield, 'discovery', side_effect=OSError('verification failed')):
            with self.assertRaisesRegex(RuntimeError, 'previous settings were restored'):
                shield.apply_discovery({'enable': False})
        self.assertEqual(self.state(), before)

    def test_discovery_stops_socket_activation_even_if_service_is_inactive(self):
        self.units['avahi-daemon.service'] = ('inactive', 'disabled')
        result = shield.apply_discovery({'enable': False})
        self.assertFalse(result['answering'])
        self.assertTrue(all(state == ('inactive', 'disabled') for unit, state in self.units.items() if unit.startswith('avahi')))

    def test_discovery_missing_privilege_leaves_network_untouched(self):
        before = self.state()
        with patch.object(shield.capabilities, 'privilege', return_value={'helper': ''}):
            with self.assertRaisesRegex(RuntimeError, 'nothing was changed'):
                shield.apply_discovery({'enable': False})
        self.assertEqual(self.state(), before)
        self.assertEqual(self.commands, [])

    def test_firewall_failure_restores_independent_active_and_enabled_state(self):
        before = self.state()  # Active at runtime, deliberately disabled at boot.
        self.fail_after = lambda argv: argv[:3] == ['pkexec', 'systemctl', 'disable']
        with self.assertRaisesRegex(RuntimeError, 'previous firewall service state was restored') as failure:
            shield.apply_firewall({'enable': False})
        self.assertIn('Runtime-only rules could not be verified', str(failure.exception))
        self.assertEqual(self.state(), before)
        self.assertNotIn(['pkexec', 'systemctl', 'enable', '--now', 'firewalld.service'], self.commands)

    def test_same_requested_firewall_state_does_not_invert_rollback(self):
        before = self.state()
        self.fail_after = lambda argv: argv[:3] == ['pkexec', 'systemctl', 'enable']
        with self.assertRaisesRegex(RuntimeError, 'previous firewall service state was restored'):
            shield.apply_firewall({'enable': True})
        self.assertEqual(self.state(), before)

    def test_ufw_config_and_systemd_state_restore_independently(self):
        self.provider = 'ufw'
        self.ufw_enabled = True
        self.units['ufw.service'] = ('active', 'disabled')
        before = self.state()
        self.fail_after = lambda argv: argv[:3] == ['pkexec', '/bin/sh', '-c']
        with self.assertRaisesRegex(RuntimeError, 'previous firewall service state was restored'):
            shield.apply_firewall({'enable': False})
        self.assertEqual(self.state(), before)
        self.assertIn(['pkexec', 'ufw', '--force', 'enable'], self.commands)

    def test_unrecoverable_unit_state_is_refused_before_mutation(self):
        self.units['firewalld.service'] = ('active', 'enabled-runtime')
        with self.assertRaisesRegex(RuntimeError, 'Cannot safely change'):
            shield.apply_firewall({'enable': False})
        self.assertEqual(self.commands, [])

    def test_failed_recovery_does_not_report_restored(self):
        def fail_and_block(argv):
            if argv[:3] == ['nmcli', 'device', 'reapply']:
                self.block_restore = True
                return True
            return False
        self.fail_after = fail_and_block
        with self.assertRaisesRegex(RuntimeError, 'could not be restored') as error:
            shield.apply_ipv6({'enable': True})
        self.assertNotIn('were restored', str(error.exception))

    def test_successful_operations_keep_the_requested_state(self):
        self.assertEqual(shield.apply_wifi({'policy': 'random'})['policy'], 'random')
        self.assertTrue(shield.apply_ipv6({'enable': True})['active'])
        self.assertFalse(shield.apply_firewall({'enable': False})['active'])
        self.assertFalse(shield.apply_discovery({'enable': False})['answering'])


if __name__ == '__main__':
    unittest.main()
