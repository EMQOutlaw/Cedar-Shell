"""A bounded action leaves recovery time and finishes before the UI watchdog."""
from pathlib import Path
import re
import subprocess
import sys
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import shield


class ShieldDeadline(unittest.TestCase):
    def setUp(self):
        self.now = 0.0
        clock = patch.object(shield.time, 'monotonic', side_effect=lambda: self.now)
        clock.start()
        self.addCleanup(clock.stop)

    def test_expired_apply_budget_keeps_recovery_reserve(self):
        seen = []
        @shield.transaction
        def action():
            self.now = shield.APPLY_BUDGET_SECONDS + 1
            try:
                shield.run(['fixture-command'])
            except TimeoutError as failure:
                def restore():
                    seen.append(shield.capabilities.bounded_timeout(999))
                    shield.run(['fixture-restore'])
                shield.recover_or_raise('Fixture', failure, restore)
        with patch.object(shield.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, '', '')) as run:
            with self.assertRaisesRegex(RuntimeError, 'previous settings were restored'):
                action()
        self.assertEqual(seen, [shield.RECOVERY_BUDGET_SECONDS - 1])
        self.assertEqual(run.call_count, 1)
        self.assertEqual(run.call_args.args[0], ['fixture-restore'])

    def test_exhausted_recovery_reports_failure_and_starts_no_command(self):
        @shield.transaction
        def action():
            def restore():
                self.now = shield.APPLY_BUDGET_SECONDS + shield.RECOVERY_BUDGET_SECONDS + 1
                shield.run(['must-not-start'])
            shield.recover_or_raise('Fixture', RuntimeError('apply failed'), restore)
        with patch.object(shield.subprocess, 'run') as run:
            with self.assertRaisesRegex(RuntimeError, 'could not be restored'):
                action()
        run.assert_not_called()

    def test_probe_and_action_commands_share_remaining_deadline(self):
        with patch.object(shield.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, '', '')) as run:
            with shield.capabilities.command_deadline(2):
                self.now = 1.5
                shield.run(['action'], timeout=120)
                self.assertEqual(run.call_args.kwargs['timeout'], .5)
                shield.capabilities.run(['probe'])
                self.assertEqual(run.call_args.kwargs['timeout'], .5)
                self.now = 3
                self.assertEqual(shield.capabilities.run(['expired-probe']), (127, ''))
        self.assertEqual(run.call_count, 2)

    def test_privileged_timeout_never_claims_completed_recovery(self):
        @shield.transaction
        def action():
            try:
                shield.run(['pkexec', 'fixture'])
            except subprocess.TimeoutExpired as failure:
                shield.recover_or_raise('Fixture', failure, lambda: None)
        with patch.object(shield.subprocess, 'run', side_effect=subprocess.TimeoutExpired(['pkexec'], 1)):
            with self.assertRaisesRegex(RuntimeError, 'elevated operation may still be running') as failure:
                action()
        self.assertNotIn('settings were restored', str(failure.exception))

    def test_frontend_watchdog_exceeds_backend_budget_and_margin(self):
        source = (ROOT / 'services/Shield.qml').read_text()
        watchdog = int(re.search(r'timeoutMs:\s*(\d+)', source).group(1))
        self.assertGreaterEqual(watchdog, 1000 * (shield.APPLY_BUDGET_SECONDS + shield.RECOVERY_BUDGET_SECONDS + 60))


if __name__ == '__main__':
    unittest.main()
