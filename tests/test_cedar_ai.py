"""cedar_ai.py: prompt framing, command lines, the event stream and the serve mode, with stand-in agents."""
from pathlib import Path
import importlib.util
import json
import os
import stat
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'scripts/cedar_ai.py'
spec = importlib.util.spec_from_file_location('cedar_ai', SCRIPT)
cedar_ai = importlib.util.module_from_spec(spec); spec.loader.exec_module(cedar_ai)

# Stand-ins for the two CLIs. `claude` answers [NEXT] on its first turn and
# [DONE] once resumed; `codex` always answers [DONE]. Both echo one tool event.
FAKE_CLAUDE = '''#!/usr/bin/env python3
import json, os, sys, time
args = sys.argv[1:]
prompt = sys.stdin.read()
time.sleep(float(os.environ.get("FAKE_DELAY", "0")))
resumed = "--resume" in args
print(json.dumps({"type": "assistant", "message": {"content": [{"type": "tool_use", "name": "Read", "input": {"file_path": "VERSION"}}]}}))
print(json.dumps({"type": "rate_limit_event", "rate_limit_info": {"status": "allowed", "unifiedWindows": {"five_hour": {"utilization": 0.08, "resetsAt": 1791678000}, "seven_day": {"utilization": 0.35, "resetsAt": 1791946800}}}}))
text = "Saw it.\\n[DONE]" if resumed else "Read VERSION.\\n[NEXT] codex: confirm."
print(json.dumps({"type": "result", "subtype": "success", "is_error": False, "result": text, "session_id": "claude-session-1",
                  "usage": {"input_tokens": 2, "cache_creation_input_tokens": 100, "cache_read_input_tokens": 1000, "output_tokens": 30}, "total_cost_usd": 0.25}))
'''
FAKE_CODEX = '''#!/usr/bin/env python3
import json, os, sys, time
args = sys.argv[1:]
time.sleep(float(os.environ.get("FAKE_DELAY", "0")))
print(json.dumps({"type": "thread.started", "thread_id": "codex-thread-1"}))
print(json.dumps({"type": "item.started", "item": {"type": "command_execution", "command": "/usr/bin/bash -lc 'cat VERSION'", "status": "in_progress"}}))
print(json.dumps({"type": "item.completed", "item": {"type": "agent_message", "text": "Confirmed.\\n[DONE]"}}))
print(json.dumps({"type": "turn.completed", "usage": {"input_tokens": 500, "cached_input_tokens": 400, "output_tokens": 20, "reasoning_output_tokens": 5}}))
'''


def fake_tools(folder):
    for name, body in (('claude', FAKE_CLAUDE), ('codex', FAKE_CODEX)):
        path = folder / name
        path.write_text(body)
        path.chmod(path.stat().st_mode | stat.S_IEXEC)


class Prompts(unittest.TestCase):
    def test_framing_names_both_agents_and_the_markers(self):
        text = cedar_ai.framing('claude', 'codex', 'Do the thing', Path('/repo'))
        self.assertIn('You are claude', text)
        self.assertIn('[DONE]', text)
        self.assertIn('[NEXT]', text)
        self.assertIn('Do the thing', text)
        self.assertNotIn('commit', text.split('Goal:')[1])

    def test_done_is_read_from_the_last_lines_only(self):
        self.assertTrue(cedar_ai.is_done('work\n[DONE]'))
        self.assertTrue(cedar_ai.is_done('work\n[DONE]\n\n'))
        self.assertFalse(cedar_ai.is_done('[DONE] was mentioned early\nthen more\nand more\nand a [NEXT]'))
        self.assertFalse(cedar_ai.is_done(''))


class Commands(unittest.TestCase):
    def agents(self, mode):
        out = cedar_ai.Emitter(); control = cedar_ai.Control(listen=False)
        return (cedar_ai.Claude(Path('.'), mode, None, [], 10, out, control),
                cedar_ai.Codex(Path('.'), mode, None, [], 10, out, control))

    def test_claude_prompt_goes_over_stdin_and_rules_are_one_argument(self):
        claude, _ = self.agents('edit')
        cmd = claude.command('PROMPT')
        self.assertNotIn('PROMPT', cmd)
        rules = cmd[cmd.index('--allowedTools') + 1]
        self.assertIn('Bash(git diff:*)', rules.split(','))
        self.assertEqual(cmd[cmd.index('--permission-mode') + 1], 'acceptEdits')

    def test_claude_read_mode_has_no_edit_tools(self):
        claude, _ = self.agents('read')
        rules = claude.command('x')[claude.command('x').index('--allowedTools') + 1]
        self.assertNotIn('Edit', rules.split(','))
        self.assertNotIn('--permission-mode', claude.command('x'))

    def test_codex_resume_drops_color_and_keeps_the_sandbox(self):
        _, codex = self.agents('read')
        fresh = codex.command('P')
        self.assertIn('--color', fresh)
        self.assertEqual(fresh[-1], 'P')
        codex.session = 'THREAD'
        resumed = codex.command('P')
        self.assertEqual(resumed[:3], ['codex', 'exec', 'resume'])
        self.assertNotIn('--color', resumed)
        self.assertEqual(resumed[-2:], ['THREAD', 'P'])
        self.assertIn('sandbox_mode="read-only"', resumed)

    def test_model_and_effort_reach_each_tool_in_its_own_words(self):
        out = cedar_ai.Emitter(); control = cedar_ai.Control(listen=False)
        claude = cedar_ai.Claude(Path('.'), 'read', 'opus', [], 10, out, control, 'max')
        cmd = claude.command('x')
        self.assertEqual(cmd[cmd.index('--model') + 1], 'opus')
        self.assertEqual(cmd[cmd.index('--effort') + 1], 'max')
        codex = cedar_ai.Codex(Path('.'), 'read', 'gpt-6-astra', [], 10, out, control, 'xhigh')
        cmd = codex.command('x')
        self.assertEqual(cmd[cmd.index('-m') + 1], 'gpt-6-astra')
        self.assertIn('model_reasoning_effort="xhigh"', cmd)
        plain = cedar_ai.Codex(Path('.'), 'read', None, [], 10, out, control, None).command('x')
        self.assertNotIn('-m', plain)
        self.assertFalse([a for a in plain if 'model_reasoning_effort' in a])

    def test_model_choices_come_from_the_tools_not_from_guesses(self):
        with tempfile.TemporaryDirectory(prefix='cedar-ai-') as tmp:
            home = Path(tmp)
            (home / 'models_cache.json').write_text(json.dumps({'models': [
                {'slug': 'gpt-x', 'display_name': 'GPT-X', 'visibility': 'list', 'default_reasoning_level': 'low',
                 'supported_reasoning_levels': [{'effort': 'low'}, {'effort': 'high'}, {'effort': 'bogus'}]},
                {'slug': 'hidden', 'visibility': 'hide'}]}))
            (home / 'config.toml').write_text('model = "gpt-x"\nmodel_reasoning_effort = "high"\n')
            with patch.dict(os.environ, {'CODEX_HOME': str(home)}):
                choices = cedar_ai.model_choices()
            self.assertEqual([m['id'] for m in choices['codexModels']], ['gpt-x'])
            self.assertEqual(choices['codexModels'][0]['efforts'], ['low', 'high'])
            self.assertEqual(choices['codexDefault'], {'model': 'gpt-x', 'effort': 'high'})
            self.assertEqual([m['id'] for m in choices['claudeModels']], ['fable', 'opus', 'sonnet', 'haiku'])
            with patch.dict(os.environ, {'CODEX_HOME': str(home / 'missing')}):
                empty = cedar_ai.model_choices()
            self.assertEqual(empty['codexModels'], [])
            self.assertEqual(empty['codexDefault'], {'model': '', 'effort': ''})

    def test_shell_wrapper_is_stripped_from_activity(self):
        self.assertEqual(cedar_ai.strip_shell_wrapper("/usr/bin/bash -lc 'cat VERSION'"), 'cat VERSION')
        self.assertEqual(cedar_ai.strip_shell_wrapper('ls -la'), 'ls -la')


class Relay(unittest.TestCase):
    def run_relay(self, tmp, *args):
        tools = tmp / 'bin'; tools.mkdir(exist_ok=True); fake_tools(tools)
        repo = tmp / 'repo'; repo.mkdir(exist_ok=True); (repo / 'VERSION').write_text('0.0.0\n')
        env = {**os.environ, 'PATH': str(tools) + os.pathsep + os.environ.get('PATH', ''), 'XDG_STATE_HOME': str(tmp / 'state')}
        # Event mode treats a closed stdin as the window going away, so the
        # control pipe stays open until the relay has finished on its own.
        out_path = tmp / 'events.out'; err_path = tmp / 'events.err'
        with out_path.open('w') as out, err_path.open('w') as err:
            proc = subprocess.Popen([sys.executable, str(SCRIPT), '--repo', str(repo), *args], env=env, stdin=subprocess.PIPE, stdout=out, stderr=err, text=True)
            try:
                code = proc.wait(timeout=60)
            finally:
                proc.stdin.close()
        return subprocess.CompletedProcess(proc.args, code, out_path.read_text(), err_path.read_text())

    def test_events_mode_relays_until_both_agents_are_done(self):
        with tempfile.TemporaryDirectory(prefix='cedar-ai-') as tmp:
            result = self.run_relay(Path(tmp), '--events', '--mode', 'read', '--rounds', '3', 'Read VERSION and agree on it')
            self.assertEqual(result.returncode, 0, result.stderr)
            events = [json.loads(line) for line in result.stdout.splitlines() if line.strip()]
            kinds = [e['type'] for e in events]
            self.assertEqual(kinds[0], 'session')
            self.assertEqual(events[0]['mode'], 'read')
            turns = [e for e in events if e['type'] == 'turn.completed']
            self.assertEqual([(t['agent'], t['round'], t['done']) for t in turns], [('claude', 1, False), ('codex', 1, True), ('claude', 2, True)])
            self.assertTrue(any(e['type'] == 'activity' and e['agent'] == 'claude' and e['text'] == 'Read VERSION' for e in events))
            self.assertTrue(any(e['type'] == 'activity' and e['agent'] == 'codex' and e['text'] == '$ cat VERSION' for e in events))
            # Each reply is handed to the other agent, and the stream says so before that agent's turn.
            relays = [(e['sender'], e['receiver'], e['round']) for e in events if e['type'] == 'relay']
            self.assertEqual(relays, [('claude', 'codex', 1), ('codex', 'claude', 1)])
            self.assertLess(kinds.index('relay'), kinds.index('turn.started', kinds.index('turn.completed')))
            self.assertEqual(events[0]['agents'], 'both')
            # Usage as the tools report it: Claude's tokens and cost, Codex's tokens; totals accumulate per agent.
            usage = [(e['agent'], e['turn']['input'], e['turn']['output'], e['total']['turns'], e['total']['cost']) for e in events if e['type'] == 'usage']
            self.assertEqual(usage, [('claude', 102, 30, 1, 0.25), ('codex', 500, 25, 1, 0.0), ('claude', 102, 30, 2, 0.5)])
            limits = [e for e in events if e['type'] == 'limits']
            self.assertEqual((limits[0]['agent'], limits[0]['fiveHour'], limits[0]['sevenDay']), ('claude', 0.08, 0.35))
            self.assertEqual(events[-1], {'type': 'finished', 'reason': 'done', 'detail': ''})
            session_dir = Path(events[0]['dir'])
            served = subprocess.run([sys.executable, str(SCRIPT), '--serve'], input='{"action": "tools"}\n', env={**os.environ, 'XDG_STATE_HOME': str(Path(tmp) / 'state')}, capture_output=True, text=True, timeout=30)
            self.assertEqual(json.loads(served.stdout)['data']['limits']['claude']['sevenDay'], 0.35)
            state = json.loads((session_dir / 'state.json').read_text())
            self.assertEqual((state['claude_session'], state['codex_thread'], state['finished'], state['turns']), ('claude-session-1', 'codex-thread-1', 'done', 3))
            self.assertEqual(state['usage']['claude'], {'input': 204, 'cached': 2000, 'output': 60, 'cost': 0.5, 'turns': 2})
            self.assertEqual(state['usage']['codex']['output'], 25)
            self.assertEqual(len(json.loads((session_dir / 'turns.json').read_text())), 3)
            self.assertIn('## Round 1 · codex', (session_dir / 'transcript.md').read_text())
            self.assertEqual(sorted(p.name for p in (session_dir / 'raw').iterdir()), ['001-claude.jsonl', '002-codex.jsonl', '003-claude.jsonl'])

    def test_round_limit_pauses_and_serve_lists_the_session(self):
        with tempfile.TemporaryDirectory(prefix='cedar-ai-') as tmp:
            result = self.run_relay(Path(tmp), '--events', '--rounds', '1', '--first', 'codex', 'Goal')
            self.assertEqual(result.returncode, 0, result.stderr)
            events = [json.loads(line) for line in result.stdout.splitlines() if line.strip()]
            turns = [e for e in events if e['type'] == 'turn.completed']
            self.assertEqual([t['agent'] for t in turns], ['codex', 'claude'])
            self.assertEqual(events[-1]['reason'], 'rounds')
            env = {**os.environ, 'XDG_STATE_HOME': str(Path(tmp) / 'state')}
            served = subprocess.run([sys.executable, str(SCRIPT), '--serve'], input='{"action": "sessions"}\n', env=env, capture_output=True, text=True, timeout=30)
            reply = json.loads(served.stdout)
            self.assertTrue(reply['ok'])
            self.assertEqual(len(reply['data']['sessions']), 1)
            self.assertEqual(reply['data']['sessions'][0]['finished'], 'rounds')
            transcript = subprocess.run([sys.executable, str(SCRIPT), '--serve'], input=json.dumps({'action': 'transcript', 'dir': reply['data']['sessions'][0]['dir']}) + '\n', env=env, capture_output=True, text=True, timeout=30)
            self.assertEqual([t['agent'] for t in json.loads(transcript.stdout)['data']['turns']], ['codex', 'claude'])
            outside = subprocess.run([sys.executable, str(SCRIPT), '--serve'], input=json.dumps({'action': 'transcript', 'dir': tmp}) + '\n', env=env, capture_output=True, text=True, timeout=30)
            self.assertFalse(json.loads(outside.stdout)['ok'])

    def test_one_agent_works_alone_until_it_says_done(self):
        with tempfile.TemporaryDirectory(prefix='cedar-ai-') as tmp:
            # No round limit: the stand-in says NEXT once, then DONE on its resumed turn.
            result = self.run_relay(Path(tmp), '--events', '--agents', 'claude', '--claude-model', 'sonnet', '--claude-effort', 'low', 'Goal')
            self.assertEqual(result.returncode, 0, result.stderr)
            events = [json.loads(line) for line in result.stdout.splitlines() if line.strip()]
            self.assertEqual(events[0]['agents'], 'claude')
            self.assertEqual(events[0]['models']['claude'], {'model': 'sonnet', 'effort': 'low'})
            turns = [(e['agent'], e['round'], e['done']) for e in events if e['type'] == 'turn.completed']
            self.assertEqual(turns, [('claude', 1, False), ('claude', 2, True)])
            self.assertFalse([e for e in events if e['type'] == 'relay'])
            self.assertEqual(events[-1]['reason'], 'done')
            session_dir = Path(events[0]['dir'])
            state = json.loads((session_dir / 'state.json').read_text())
            self.assertEqual((state['agents'], state['codex_thread'], state['turns']), ('claude', None, 2))
            self.assertEqual(state['models'], {'claude': {'model': 'sonnet', 'effort': 'low'}, 'codex': {'model': '', 'effort': ''}})
            # Codex is never run, so its absence is not an error for a Claude-only session.
            env = {**os.environ, 'PATH': str(Path(tmp) / 'bin'), 'XDG_STATE_HOME': str(Path(tmp) / 'state')}
            (Path(tmp) / 'bin' / 'codex').unlink()
            resumed = subprocess.run([sys.executable, str(SCRIPT), '--events', '--resume-session', str(session_dir), '--rounds', '1', '-m', 'Once more'],
                                     env=env, capture_output=True, text=True, timeout=60, stdin=subprocess.PIPE)
            kinds = [json.loads(line)['type'] for line in resumed.stdout.splitlines() if line.strip()]
            self.assertIn('human', kinds)
            self.assertNotIn('error', kinds)

    def test_solo_framing_is_for_one_agent(self):
        text = cedar_ai.solo_framing('codex', 'Do the thing', Path('/repo'))
        self.assertIn('working alone', text)
        self.assertNotIn('claude', text.lower())
        self.assertIn('[DONE]', text)
        paired = cedar_ai.framing('claude', 'codex', 'Do the thing', Path('/repo'))
        self.assertIn('acknowledges what', paired)
        self.assertIn('same files', paired)

    def test_missing_tools_are_reported_not_guessed(self):
        with tempfile.TemporaryDirectory(prefix='cedar-ai-') as tmp:
            repo = Path(tmp) / 'repo'; repo.mkdir()
            env = {**os.environ, 'PATH': tmp, 'XDG_STATE_HOME': str(Path(tmp) / 'state')}
            result = subprocess.run([sys.executable, str(SCRIPT), '--events', '--repo', str(repo), 'Goal'], env=env, capture_output=True, text=True, timeout=30, stdin=subprocess.DEVNULL)
            self.assertEqual(result.returncode, 2)
            self.assertIn('is not on PATH', json.loads(result.stdout.splitlines()[0])['message'])
            served = subprocess.run([sys.executable, str(SCRIPT), '--serve'], input='{"action": "tools"}\n', env=env, capture_output=True, text=True, timeout=30)
            data = json.loads(served.stdout)['data']
            self.assertEqual((data['claude'], data['codex'], data['limits']), ('', '', {}))


if __name__ == '__main__':
    unittest.main()


class Detached(unittest.TestCase):
    """A session served at a socket: it outlives the window, replays itself to a
    window that attaches later, takes messages and a stop over the socket, and
    is recorded as running while it runs."""

    def setting(self, tmp, delay='0'):
        tools = tmp / 'bin'; tools.mkdir(exist_ok=True); fake_tools(tools)
        repo = tmp / 'repo'; repo.mkdir(exist_ok=True); (repo / 'VERSION').write_text('0.0.0\n')
        (tmp / 'run').mkdir(exist_ok=True)
        env = {**os.environ, 'PATH': str(tools) + os.pathsep + os.environ.get('PATH', ''), 'XDG_STATE_HOME': str(tmp / 'state'),
               'XDG_RUNTIME_DIR': str(tmp / 'run'), 'FAKE_DELAY': delay, 'CEDAR_AI_LAUNCHER': 'fork'}
        return repo, env

    @staticmethod
    def wait_for(predicate, seconds=15):
        import time
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            if predicate():
                return True
            time.sleep(0.05)
        return False

    @staticmethod
    def attach(path):
        import socket as sockets
        client = sockets.socket(sockets.AF_UNIX, sockets.SOCK_STREAM)
        client.connect(str(path))
        return client

    @staticmethod
    def read_events(client, until, seconds=30):
        """Events from the socket until one of type `until` arrives."""
        import time
        client.settimeout(seconds)
        buffer = b''; events = []
        start = time.monotonic()
        while time.monotonic() - start < seconds:
            chunk = client.recv(65536)
            if not chunk:
                break
            buffer += chunk
            while b'\n' in buffer:
                line, buffer = buffer.split(b'\n', 1)
                if line.strip():
                    events.append(json.loads(line))
                    if events[-1]['type'] == until:
                        return events
        return events

    def test_socket_session_replays_takes_messages_and_records_itself(self):
        with tempfile.TemporaryDirectory(prefix='cedar-ai-') as tmp:
            tmp = Path(tmp); repo, env = self.setting(tmp, delay='1.2')
            # A session recorded by the plain event mode, before it had an event log
            # (its control pipe stays open until it finishes on its own).
            quiet = {**env, 'FAKE_DELAY': '0'}
            with (tmp / 'first.out').open('w') as out, (tmp / 'first.err').open('w') as err:
                first = subprocess.Popen([sys.executable, str(SCRIPT), '--events', '--repo', str(repo), '--mode', 'read', '--rounds', '1', 'Agree on VERSION'],
                                         env=quiet, stdin=subprocess.PIPE, stdout=out, stderr=err, text=True)
                try:
                    self.assertEqual(first.wait(timeout=60), 0, (tmp / 'first.err').read_text())
                finally:
                    first.stdin.close()
            session_dir = Path(json.loads((tmp / 'first.out').read_text().splitlines()[0])['dir'])
            self.assertFalse((session_dir / 'events.jsonl').exists())
            sock = tmp / 'run' / 'relay.sock'
            proc = subprocess.Popen([sys.executable, str(SCRIPT), '--socket', str(sock), '--resume-session', str(session_dir), '--rounds', '3', '-m', 'Go on'],
                                    env=env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            try:
                running_file = tmp / 'state' / 'cedar-ai' / 'running.json'
                self.assertTrue(self.wait_for(lambda: sock.exists() and running_file.exists()), 'socket and running record')
                record = json.loads(running_file.read_text())
                self.assertEqual((record['pid'], record['socket'], record['dir']), (proc.pid, str(sock), str(session_dir)))
                served = subprocess.run([sys.executable, str(SCRIPT), '--serve'], input='{"action": "sessions"}\n', env=env, capture_output=True, text=True, timeout=30)
                self.assertEqual(json.loads(served.stdout)['data']['running']['pid'], proc.pid)
                client = self.attach(sock)
                client.sendall(b'{"message": "Hello from the window"}\n')
                events = self.read_events(client, 'finished')
                kinds = [e['type'] for e in events]
                # The seeded history comes first: the earlier run's two turns, then the live session.
                self.assertEqual(kinds[0], 'session')
                seeded = [e for e in events[:3] if e['type'] == 'turn.completed']
                self.assertEqual([(t['agent'], t['round']) for t in seeded], [('claude', 1), ('codex', 1)])
                self.assertTrue(events[3]['type'] == 'session' and events[3]['resumed'])
                humans = [e['text'] for e in events if e['type'] == 'human']
                self.assertEqual(humans, ['Go on', 'Hello from the window'])
                self.assertEqual(events[-1]['reason'], 'done')
                self.assertEqual(len([e for e in events if e['type'] == 'turn.completed']), 4)
                client.close()
                self.assertEqual(proc.wait(timeout=30), 0)
                self.assertFalse(running_file.exists(), 'running record cleared')
                self.assertFalse(sock.exists(), 'socket removed')
                logged = [json.loads(l) for l in (session_dir / 'events.jsonl').read_text().splitlines()]
                self.assertEqual([e['type'] for e in logged], kinds)
                self.assertIn('Hello from the window', (session_dir / 'transcript.md').read_text())
            finally:
                if proc.poll() is None:
                    proc.kill()

    def test_kill_through_serve_stops_a_running_session(self):
        with tempfile.TemporaryDirectory(prefix='cedar-ai-') as tmp:
            tmp = Path(tmp); repo, env = self.setting(tmp, delay='8')
            sock = tmp / 'run' / 'relay.sock'
            proc = subprocess.Popen([sys.executable, str(SCRIPT), '--socket', str(sock), '--repo', str(repo), '--mode', 'read', 'Take your time'],
                                    env=env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            try:
                running_file = tmp / 'state' / 'cedar-ai' / 'running.json'
                self.assertTrue(self.wait_for(lambda: running_file.exists()))
                killed = subprocess.run([sys.executable, str(SCRIPT), '--serve'], input='{"action": "kill"}\n', env=env, capture_output=True, text=True, timeout=30)
                self.assertTrue(json.loads(killed.stdout)['data']['killed'])
                self.assertEqual(proc.wait(timeout=20), 0)
                session_dir = Path(json.loads(running_file.read_text())['dir']) if running_file.exists() else None
                self.assertIsNone(session_dir, 'running record cleared after the stop')
                sessions = json.loads(subprocess.run([sys.executable, str(SCRIPT), '--serve'], input='{"action": "sessions"}\n', env=env, capture_output=True, text=True, timeout=30).stdout)
                self.assertEqual(sessions['data']['sessions'][0]['finished'], 'stopped')
                self.assertIsNone(sessions['data']['running'])
            finally:
                if proc.poll() is None:
                    proc.kill()

    def test_detach_starts_the_session_apart_and_says_where_to_attach(self):
        with tempfile.TemporaryDirectory(prefix='cedar-ai-') as tmp:
            tmp = Path(tmp); repo, env = self.setting(tmp, delay='1.5')
            launched = subprocess.run([sys.executable, str(SCRIPT), '--events', '--detach', '--repo', str(repo), '--mode', 'read', '--rounds', '1', 'Apart'],
                                      env=env, capture_output=True, text=True, timeout=30, stdin=subprocess.DEVNULL)
            self.assertEqual(launched.returncode, 0, launched.stderr)
            event = json.loads(launched.stdout.strip())
            self.assertEqual(event['type'], 'launched')
            sock = Path(event['socket'])
            self.assertTrue(sock.parent == tmp / 'run' / 'cedar-ai')
            running_file = tmp / 'state' / 'cedar-ai' / 'running.json'
            self.assertTrue(self.wait_for(lambda: sock.exists() and running_file.exists()), 'the detached session came up after the launcher exited')
            record = json.loads(running_file.read_text())
            self.assertEqual(record['pid'], event['pid'])
            os.kill(record['pid'], 0)  # alive, with the launcher long gone
            client = self.attach(sock)
            events = self.read_events(client, 'finished')
            self.assertEqual(events[-1]['reason'], 'rounds')
            client.close()
            self.assertTrue(self.wait_for(lambda: not running_file.exists()), 'running record cleared')
