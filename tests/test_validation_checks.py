"""Installer validation diagnostics and process cleanup, without Qt or a desktop."""
import fcntl
import json
import os
from pathlib import Path
import signal
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import distribution as d


class ValidationChecks(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='cedar validation 雨 ')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def test_qt_validation_forces_software_without_changing_parent_environment(self):
        fake_qs = self.root / 'qs'
        fake_qs.write_text(
            '#!' + sys.executable + '\n'
            'import json, os\n'
            'print(json.dumps({key: os.environ.get(key) for key in '
            '["QT_QUICK_BACKEND", "QSG_RHI_BACKEND", "CEDAR_FIXTURE_SENTINEL"]}))\n'
        )
        fake_qs.chmod(0o755)
        inherited = {'QT_QUICK_BACKEND': 'rhi', 'QSG_RHI_BACKEND': 'software',
                     'CEDAR_FIXTURE_SENTINEL': 'retained'}
        with patch.dict(os.environ, inherited):
            for explicit_env in (None, dict(os.environ)):
                with self.subTest(explicit_env=explicit_env is not None):
                    actual = json.loads(d.validation_command([str(fake_qs)], timeout=2, env=explicit_env))
                    self.assertEqual(actual['QT_QUICK_BACKEND'], 'software')
                    self.assertIsNone(actual['QSG_RHI_BACKEND'])
                    self.assertEqual(actual['CEDAR_FIXTURE_SENTINEL'], 'retained')
                    for key, value in inherited.items():
                        self.assertEqual(os.environ[key], value)
                    if explicit_env is not None:
                        self.assertEqual(explicit_env['QT_QUICK_BACKEND'], 'rhi')

    def test_nonzero_exit_preserves_stdout_only_diagnostic(self):
        fixture = self.root / 'qml-load-failure.py'
        fixture.write_text('print("ReferenceError: fixtureControl is not defined", flush=True)\nraise SystemExit(7)\n')
        with self.assertRaises(d.Refused) as raised:
            d.validation_command([sys.executable, str(fixture)], timeout=2)
        message = str(raised.exception)
        self.assertIn(fixture.name, message)
        self.assertIn('7', message)
        self.assertIn('ReferenceError: fixtureControl is not defined', message)

    def _descendant_fixture(self, parent_action):
        """The lock proves child lifetime even when a killed process is a zombie."""
        lock = self.root / 'descendant.lock'
        ready = self.root / 'descendant.ready'
        child_pid = self.root / 'descendant.pid'
        child = self.root / 'validation-child.py'
        child.write_text(
            'import fcntl, os, pathlib, sys, time\n'
            'lock = open(sys.argv[1], "w")\n'
            'fcntl.flock(lock, fcntl.LOCK_EX)\n'
            'pathlib.Path(sys.argv[3]).write_text(str(os.getpid()))\n'
            'pathlib.Path(sys.argv[2]).write_text("ready")\n'
            'print("descendant acquired lock", flush=True)\n'
            'time.sleep(30)\n'
        )
        parent = self.root / 'validation-parent.py'
        parent.write_text(
            'import pathlib, subprocess, sys, time\n'
            'subprocess.Popen([sys.executable, sys.argv[1], *sys.argv[2:]])\n'
            'deadline = time.monotonic() + 5\n'
            'while not pathlib.Path(sys.argv[3]).exists():\n'
            '    if time.monotonic() > deadline: raise RuntimeError("fixture child did not start")\n'
            '    time.sleep(0.005)\n'
            'print("validation reached fixture stage", flush=True)\n'
            'print("fixture diagnostic on stderr", file=sys.stderr, flush=True)\n'
            + parent_action + '\n'
        )

        def cleanup_child():
            # The test remains tidy when a regression leaves this specific child alive.
            if not child_pid.exists():
                return
            with lock.open('a') as handle:
                try:
                    fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
                except BlockingIOError:
                    try:
                        os.kill(int(child_pid.read_text()), signal.SIGKILL)
                    except ProcessLookupError:
                        pass

        self.addCleanup(cleanup_child)
        return [sys.executable, str(parent), str(child), str(lock), str(ready), str(child_pid)], lock, ready

    def _assert_descendant_stopped(self, lock, ready):
        self.assertTrue(ready.exists(), 'The descendant must start for this check to exercise cleanup')
        # SIGKILL delivery can finish just after the parent is reaped.
        deadline = time.monotonic() + 2
        with lock.open('a') as handle:
            while True:
                try:
                    fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    return
                except BlockingIOError:
                    if time.monotonic() >= deadline:
                        self.fail('Validation left its descendant running after returning')
                    time.sleep(0.01)

    def test_timeout_preserves_partial_diagnostics_and_stops_descendant(self):
        argv, lock, ready = self._descendant_fixture('time.sleep(30)')
        started = time.monotonic()
        with self.assertRaises(d.Refused) as raised:
            d.validation_command(argv, timeout=1)
        self.assertLess(time.monotonic() - started, 5, 'Timeout cleanup must itself be bounded')
        message = str(raised.exception)
        self.assertIn('validation-parent.py', message)
        self.assertRegex(message.lower(), r'timed out|timeout|exceeded')
        self.assertIn('validation reached fixture stage', message)
        self.assertIn('fixture diagnostic on stderr', message)
        self._assert_descendant_stopped(lock, ready)

    def test_successful_parent_stops_descendant_holding_output_pipes(self):
        argv, lock, ready = self._descendant_fixture('raise SystemExit(0)')
        started = time.monotonic()
        output = d.validation_command(argv, timeout=2)
        self.assertLess(time.monotonic() - started, 5)
        self.assertIn('validation reached fixture stage', output)
        self._assert_descendant_stopped(lock, ready)

    def test_failed_parent_stops_descendant_and_reports_actual_exit(self):
        argv, lock, ready = self._descendant_fixture('raise SystemExit(9)')
        with self.assertRaises(d.Refused) as raised:
            d.validation_command(argv, timeout=2)
        message = str(raised.exception)
        self.assertIn('validation reached fixture stage', message)
        self.assertIn('fixture diagnostic on stderr', message)
        self.assertIn('9', message)
        self.assertNotRegex(message.lower(), r'timed out|timeout')
        self._assert_descendant_stopped(lock, ready)


if __name__ == '__main__':
    unittest.main()
