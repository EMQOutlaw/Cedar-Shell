"""Isolated lock protocol fixtures: never contact a compositor or suspend."""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('lock_bridge', ROOT / 'scripts/lock_bridge.py')
b = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(b)


def native(**changes):
    return {**dict(externalLock=False, lockReady=True, locked=False, lockSecure=False,
                   stage=3, screenCount=2), **changes}


def stock(**changes):
    return {**dict(locked=False, requested=False, secure=False, sessionLocked=False,
                   passwordPam=True, realScreens=2), **changes}


class World:
    def __init__(self, cedar=None, omarchy=None):
        self.cedar = native() if cedar is None else cedar
        self.stock = omarchy
        self.calls = []
        self.reply = ''
        self.cedar_inventory = [{'id': 'cedar123'}]
        self.stock_inventory = [] if omarchy is None else [{'id': 'stock456'}]

    def run(self, argv, deadline, env):
        args = argv[1:]
        self.calls.append((args, deadline))
        if args[:2] == ['list', '-j']:
            value = self.cedar_inventory if args[2:4] == ['-c', 'cedar'] else self.stock_inventory
        elif args[:3] == ['ipc', '--id', 'stock456']:
            value = self.stock if args[-1] == 'status' else 'ok'
        elif args[:3] == ['ipc', '--id', 'cedar123']:
            value = self.cedar if args[-1] == 'sessionInfo' else self.reply
        else:
            raise AssertionError(args)
        if isinstance(value, Exception):
            raise value
        return value if isinstance(value, str) else json.dumps(value)

    def call(self, method):
        return b.Bridge('/fixture/qs', '/fixture/omarchy', {}, .5, runner=self.run, clock=lambda: 100).call(method)


class LockProtocol(unittest.TestCase):
    def test_unlocked_native_status_uses_live_ipc_and_pins_identity(self):
        world = World()
        state = json.loads(world.call('status'))
        self.assertFalse(state['secure'])
        self.assertFalse(state['requested'])
        self.assertEqual(state['provider'], 'cedar')
        self.assertTrue(state['ready'])
        self.assertNotIn('passwordPam', state)
        self.assertEqual(world.calls[-1][0], ['ipc', '--id', 'cedar123', 'call', '--', 'shell', 'sessionInfo'])
        self.assertTrue(all(100 < deadline <= 100.5 for _, deadline in world.calls))

    def test_requested_ui_flag_is_never_proof_of_secure_lock(self):
        state = json.loads(World(native(locked=True)).call('status'))
        self.assertTrue(state['requested'])
        self.assertTrue(state['pending'])
        self.assertFalse(state['secure'])
        self.assertFalse(state['sessionLocked'])

    def test_native_secure_requires_readiness_and_compositor_acknowledgement(self):
        for ready in (False, True):
            with self.subTest(ready=ready):
                state = json.loads(World(native(locked=True, lockSecure=True, lockReady=ready)).call('status'))
                self.assertIs(state['secure'], ready)
                self.assertIs(state['sessionLocked'], ready)

    def test_external_native_data_never_claims_secure_coverage(self):
        world = World(native(externalLock=True, locked=True, lockSecure=True), stock())
        state = json.loads(world.call('status'))
        self.assertNotIn('provider', state)
        self.assertFalse(state['secure'])
        world.call('lock')
        self.assertEqual(world.calls[-1][0][-4:], ['call', '--', 'lock', 'lock'])
        self.assertEqual(world.calls[-1][0][2], 'stock456')

    def test_stock_boot_lock_has_precedence_when_pending_or_secure(self):
        for state in (stock(locked=True, requested=True), stock(locked=True, requested=True, secure=True, sessionLocked=True)):
            world = World(native(), state)
            answer = json.loads(world.call('status'))
            self.assertEqual(answer, state)
            self.assertFalse(any('cedar' in args for args, _ in world.calls))
            self.assertEqual(world.call('lock'), 'ok')
            self.assertFalse(any(args[-2:] == ['lock', 'lock'] for args, _ in world.calls))

    def test_unreadable_stock_owner_does_not_start_competing_native_locker(self):
        for problem in (b.Unavailable('timeout'), '{broken', {'secure': 'false'}):
            world = World(omarchy=problem)
            with self.assertRaises((b.Unavailable, b.InvalidState)):
                world.call('lock')
            self.assertFalse(any('cedar' in args for args, _ in world.calls))

    def test_ambiguous_owner_inventory_fails_closed(self):
        for provider in ('cedar_inventory', 'stock_inventory'):
            world = World()
            setattr(world, provider, [{'id': 'first'}, {'id': 'second'}])
            with self.assertRaisesRegex(b.InvalidState, 'ambiguous'):
                world.call('lock')
            self.assertFalse(any(args[-2:] == ['lock', 'lock'] for args, _ in world.calls))

    def test_missing_cedar_falls_back_to_available_stock_locker(self):
        world = World(omarchy=stock())
        world.cedar_inventory = []
        self.assertEqual(world.call('lock'), 'ok')
        self.assertEqual(world.calls[-1][0][2], 'stock456')

    def test_unreadable_known_cedar_owner_never_starts_competing_stock_locker(self):
        world = World(b.Unavailable('gone'), stock())
        with self.assertRaises(b.Unavailable):
            world.call('lock')
        self.assertFalse(any(args[-2:] == ['lock', 'lock'] for args, _ in world.calls))

    def test_no_shell_never_claims_success(self):
        world = World()
        world.cedar_inventory = []
        with self.assertRaises(b.Unavailable):
            world.call('lock')

    def test_malformed_native_state_never_falls_back_or_claims_secure(self):
        for value in ('', '0', 'true', '[]', '{broken', native(lockSecure='true'),
                      native(locked=1), native(lockSecure=True, locked=False),
                      native(screenCount=True), native(stage='3')):
            with self.subTest(value=value):
                world = World(value, stock())
                with self.assertRaises(b.InvalidState):
                    world.call('lock')
                self.assertFalse(any(args[-2:] == ['lock', 'lock'] for args, _ in world.calls))

    def test_native_not_ready_fails_without_inventing_pam_status_or_requesting_lock(self):
        world = World(native(lockReady=False))
        self.assertEqual(world.call('lock'), 'failed')
        self.assertFalse(any(args[-2:] == ['lock', 'lock'] for args, _ in world.calls))

    def test_successful_native_void_lock_request_becomes_ok(self):
        world = World()
        self.assertEqual(world.call('lock'), 'ok')
        self.assertEqual(world.calls[-1][0], ['ipc', '--id', 'cedar123', 'call', '--', 'lock', 'lock'])

    def test_failed_native_request_never_becomes_ok(self):
        for reply in ('Target not found.', 'Function not found.', 'true', '0', 'failed', b.Unavailable('timeout')):
            with self.subTest(reply=reply):
                world = World()
                world.reply = reply
                with self.assertRaises((b.InvalidState, b.Unavailable)):
                    world.call('lock')

    def test_islocked_remains_requested_state_for_screensaver_callers(self):
        self.assertEqual(World().call('isLocked'), 'false')
        self.assertEqual(World(native(locked=True)).call('isLocked'), 'true')


class ProcessBoundaries(unittest.TestCase):
    def test_timeout_parser_accepts_caller_formats_with_hard_cap(self):
        for value, seconds in [('0.500', .5), ('2s', 2), ('500ms', .5), ('.25s', .25),
                               ('600s', 2), ('garbage', 2), ('0', 2), ('-1', 2)]:
            self.assertEqual(b.timeout_seconds(value), seconds)

    def test_legacy_shim_paths_and_redirect_environment_are_removed(self):
        env = b.clean_environment({'PATH': '/old/scripts/shim:/new/scripts/lock-shim:/usr/bin',
                                   'CEDAR_SHELL_PATH': '/stale/shell.qml', 'CEDAR_QS_BIN': '/old/shim/qs',
                                   'QS_CONFIG_PATH': '/wrong/shell.qml', 'WAYLAND_DISPLAY': 'fixture'})
        self.assertEqual(env['PATH'], '/usr/bin')
        self.assertNotIn('CEDAR_SHELL_PATH', env)
        self.assertNotIn('CEDAR_QS_BIN', env)
        self.assertNotIn('QS_CONFIG_PATH', env)

    def test_zero_exit_textual_ipc_errors_are_unavailable(self):
        for value in b.IPC_ERRORS:
            with self.subTest(value=value), self.assertRaises(b.Unavailable):
                b.bounded_command([sys.executable, '-c', 'print(' + repr(value) + ')'], time.monotonic() + 1, os.environ)

    def test_stdout_cannot_exceed_response_limit(self):
        with self.assertRaisesRegex(b.InvalidState, 'size limit'):
            b.bounded_command([sys.executable, '-c', 'import os; os.write(1, b"x" * 65536)'], time.monotonic() + 1, os.environ)

    def test_stalled_ipc_is_killed_before_late_side_effect(self):
        with tempfile.TemporaryDirectory() as tmp:
            marker = Path(tmp) / 'late'
            code = 'import time; from pathlib import Path; time.sleep(.4); Path(' + repr(str(marker)) + ').write_text("late")'
            start = time.monotonic()
            with self.assertRaises(b.Unavailable):
                b.bounded_command([sys.executable, '-c', code], start + .1, os.environ)
            self.assertLess(time.monotonic() - start, .35)
            time.sleep(.45)
            self.assertFalse(marker.exists())

    def test_unrelated_commands_exec_stock_with_original_quiet_arguments(self):
        env = {'PATH': '/usr/bin', 'OMARCHY_PATH': '/fixture/omarchy', 'WAYLAND_DISPLAY': 'fixture'}
        with patch.dict(os.environ, env, clear=True), patch.object(b.os, 'execve', side_effect=SystemExit) as execute:
            with self.assertRaises(SystemExit):
                b.main(['-q', 'shell', 'ping'])
        self.assertEqual(execute.call_args.args[:2], ('/fixture/omarchy/bin/omarchy-shell', ['/fixture/omarchy/bin/omarchy-shell', '-q', 'shell', 'ping']))

    def test_quiet_failure_suppresses_output_and_preserves_stock_exit_contract(self):
        with patch.object(b.shutil, 'which', return_value=None), contextlib.redirect_stdout(io.StringIO()) as out, contextlib.redirect_stderr(io.StringIO()) as err:
            self.assertEqual(b.main(['-q', 'lock', 'status']), 0)
        self.assertEqual(out.getvalue() + err.getvalue(), '')


class ExecutableFixture(unittest.TestCase):
    def test_wrapper_and_real_process_protocol_without_desktop_access(self):
        with tempfile.TemporaryDirectory(prefix='cedar-lock-bridge-') as tmp:
            base = Path(tmp)
            fake = base / 'qs'
            fake.write_text('#!' + sys.executable + '\n' + '''import json, sys
args = sys.argv[1:]
if args[:2] == ['list', '-j']:
    print(json.dumps([{'id':'native123'}] if args[2:4] == ['-c','cedar'] else []))
elif args[-2:] == ['shell', 'sessionInfo']:
    print(json.dumps({'externalLock':False,'lockReady':True,'locked':False,'lockSecure':False,'stage':3,'screenCount':1}))
elif args[-2:] != ['lock','lock']:
    raise SystemExit(90)
''')
            fake.chmod(0o700)
            env = {**os.environ, 'PATH': str(base) + os.pathsep + os.defpath,
                   'OMARCHY_PATH': str(base / 'omarchy'), 'WAYLAND_DISPLAY': 'fixture',
                   'OMARCHY_SHELL_IPC_TIMEOUT': '0.500'}
            for method in ('status', 'lock'):
                result = subprocess.run(['/bin/sh', str(ROOT / 'scripts/lock-shim/omarchy-shell'), 'lock', method],
                                        env=env, capture_output=True, text=True, timeout=2)
                self.assertEqual(result.returncode, 0, result.stderr)
                if method == 'status':
                    state = json.loads(result.stdout)
                    self.assertFalse(state['secure'])
                    self.assertEqual(state['provider'], 'cedar')
                else:
                    self.assertEqual(result.stdout, 'ok\n')


if __name__ == '__main__':
    unittest.main()
