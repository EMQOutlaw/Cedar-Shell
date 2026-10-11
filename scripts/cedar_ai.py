#!/usr/bin/env python3
"""cedar-ai: Claude Code and Codex CLI working one goal together, turn by turn.

The two agents alternate in the same checkout. Each keeps its own session
(`claude -p --resume`, `codex exec resume`), and whatever one writes as its
final reply is delivered to the other as its next message. Only one agent runs
at a time, so they never edit the checkout at once. The person who started the
session reads along and can step in between turns.

Three ways to drive it:

  cedar-ai "goal"            a terminal conversation with pauses between rounds
  cedar-ai --events "goal"   JSON lines on stdout, control lines on stdin;
  cedar-ai --socket P "goal" the same stream served over a Unix socket at P,
                             with the session recorded as running; --detach
                             launches that as its own process (a transient
                             systemd user unit when there is one) and exits;
                             this is how the CEDAR AI window drives it
  cedar-ai --serve           one JSON request on stdin (sessions, transcript,
                             tools), one JSON reply on stdout

Sessions live under $XDG_STATE_HOME/cedar-ai/<stamp>-<goal>/ with a readable
transcript, a turns.json the window reads back, state.json and the raw event
stream of every turn.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import queue
import re
import select
import shutil
import signal
import socket
import subprocess
import sys
import textwrap
import threading
from pathlib import Path

STATE_ROOT = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "cedar-ai"
RUNTIME_ROOT = Path(os.environ.get("XDG_RUNTIME_DIR") or f"/tmp/cedar-ai-{os.getuid()}") / "cedar-ai"
RUNNING_FILE = STATE_ROOT / "running.json"
# Environment a detached session carries into its own unit: the tools' location
# and their own configuration and credentials; the user manager supplies the rest.
CARRIED_ENV = ("PATH", "HOME", "SHELL", "LANG", "XDG_STATE_HOME", "XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_CACHE_HOME",
               "XDG_RUNTIME_DIR", "CODEX_HOME", "CLAUDE_CONFIG_DIR", "ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN",
               "ANTHROPIC_BASE_URL", "OPENAI_API_KEY", "OPENAI_BASE_URL", "SSH_AUTH_SOCK", "GIT_SSH_COMMAND", "GNUPGHOME")
DONE = "[DONE]"
NEXT = "[NEXT]"
AGENT_NAMES = ("claude", "codex")
MODES = ("read", "edit", "full")

# ------------------------------------------------------------------ output

class Terminal:
    def open_link(self, session: "Session", path: str, control: "Control") -> None:
        raise SystemExit("cedar-ai: --socket serves the event stream; use it with --events or --detach")

    def close_link(self) -> None:
        pass

    """Human-readable output for a terminal session."""

    def __init__(self) -> None:
        self.color = sys.stdout.isatty() and os.environ.get("NO_COLOR") is None
        self.style = {"claude": "38;5;215", "codex": "38;5;117", "human": "38;5;156", "dim": "2", "bold": "1", "error": "31"}

    def paint(self, text: str, code: str) -> str:
        return f"\033[{code}m{text}\033[0m" if self.color else text

    def session(self, info: dict) -> None:
        print(self.paint(f"cedar-ai · {info['repo']} · mode {info['mode']} · transcript {info['dir']}/transcript.md", self.style["dim"]))
        print(self.paint("goal: ", self.style["bold"]) + info["goal"].strip().replace("\n", " ")[:200])

    def turn_started(self, agent: str, round_no: int) -> None:
        width = min(shutil.get_terminal_size((100, 20)).columns, 100)
        label = f" {agent.upper()} · round {round_no} "
        print()
        print(self.paint("─ " + label + "─" * max(0, width - len(label) - 2), self.style[agent]))

    def activity(self, agent: str, text: str) -> None:
        text = text.replace("\n", " ")
        if len(text) > 110:
            text = text[:107] + "…"
        print(self.paint(f"  {agent} · {text}", self.style["dim"]), flush=True)

    def turn_completed(self, agent: str, round_no: int, text: str, done: bool) -> None:
        for line in text.rstrip("\n").splitlines() or [""]:
            print(f"  {line}")
        print(flush=True)

    def human(self, text: str) -> None:
        pass

    def relay(self, sender: str, receiver: str, round_no: int) -> None:
        print(self.paint(f"  {sender}'s reply handed to {receiver}", self.style["dim"]), flush=True)

    def usage(self, agent: str, turn: dict, total: dict) -> None:
        cost = f" · ${total['cost']:.2f} so far" if total.get("cost") else ""
        print(self.paint(f"  {agent} used {turn['input']:,} in / {turn['output']:,} out this turn"
                         f" ({total['input']:,} / {total['output']:,} this session{cost})", self.style["dim"]), flush=True)

    def limits(self, agent: str, info: dict) -> None:
        print(self.paint(f"  {agent} plan: 5-hour window {round(info['fiveHour'] * 100)}% used · week {round(info['sevenDay'] * 100)}% used", self.style["dim"]), flush=True)

    def error(self, message: str) -> None:
        print(self.paint("cedar-ai: " + message, self.style["error"]), file=sys.stderr, flush=True)

    def finished(self, reason: str, detail: str = "") -> None:
        if reason == "done":
            print(self.paint("both agents answered [DONE]", self.style["bold"]))
        elif reason == "rounds":
            print(self.paint(detail or "round limit reached; resume with --resume-session latest", self.style["dim"]))
        elif reason == "stopped":
            print(self.paint("stopped; resume with --resume-session latest", self.style["dim"]))


class Emitter:
    """One JSON object per line on stdout; the CEDAR AI window reads these.

    Serving a socket, every line also lands in the session's events.jsonl and
    reaches each attached window, so a window that comes back (after the shell
    restarted, say) replays the whole session and then follows it live.
    """

    def __init__(self) -> None:
        self.lock = threading.Lock()
        self.log: Path | None = None
        self.link: "Link | None" = None

    def _emit(self, **event) -> None:
        line = json.dumps(event, ensure_ascii=False) + "\n"
        with self.lock:
            try:
                sys.stdout.write(line)
                sys.stdout.flush()
            except (OSError, ValueError):
                pass  # a detached session's stdout may be gone; the log and the link carry the line
            if self.log is not None:
                with self.log.open("a", encoding="utf-8") as fh:
                    fh.write(line)
            if self.link is not None:
                self.link.broadcast(line)

    def open_link(self, session: "Session", path: str, control: "Control") -> None:
        """Serve this session at a Unix socket and record it as the running one."""
        self.log = session.dir / "events.jsonl"
        if not self.log.exists():
            seed_events(session, self.log)
        self.link = Link(Path(path), control, self.log, self.lock)
        record_running(session, path)

    def close_link(self) -> None:
        if self.link is not None:
            self.link.close()
            self.link = None
        forget_running()

    def session(self, info: dict) -> None:
        self._emit(type="session", **info)

    def turn_started(self, agent: str, round_no: int) -> None:
        self._emit(type="turn.started", agent=agent, round=round_no)

    def activity(self, agent: str, text: str) -> None:
        self._emit(type="activity", agent=agent, text=text[:400])

    def turn_completed(self, agent: str, round_no: int, text: str, done: bool) -> None:
        self._emit(type="turn.completed", agent=agent, round=round_no, text=text, done=done)

    def human(self, text: str) -> None:
        self._emit(type="human", text=text)

    def relay(self, sender: str, receiver: str, round_no: int) -> None:
        self._emit(type="relay", sender=sender, receiver=receiver, round=round_no)

    def usage(self, agent: str, turn: dict, total: dict) -> None:
        self._emit(type="usage", agent=agent, turn=turn, total=total)

    def limits(self, agent: str, info: dict) -> None:
        self._emit(type="limits", agent=agent, **info)

    def error(self, message: str) -> None:
        self._emit(type="error", message=message)

    def finished(self, reason: str, detail: str = "") -> None:
        self._emit(type="finished", reason=reason, detail=detail)


# ----------------------------------------------------------------- control

class Control:
    """Messages and a stop request arriving while an agent runs.

    In events mode a thread reads JSON lines from stdin: {"message": "..."}
    is delivered with the next turn, {"stop": true} ends the session after
    the running agent is killed. In a terminal nothing arrives this way; the
    pause between rounds asks instead.
    """

    def __init__(self, listen: bool, out=None) -> None:
        self.messages: "queue.Queue[str]" = queue.Queue()
        self.stop = threading.Event()
        self.out = out
        if listen:
            threading.Thread(target=self._reader, daemon=True).start()

    def feed(self, line: str) -> None:
        """One control line, from stdin or an attached window."""
        line = line.strip()
        if not line:
            return
        try:
            control = json.loads(line)
        except json.JSONDecodeError:
            return
        if not isinstance(control, dict):
            return
        if control.get("stop"):
            self.stop.set()
        message = control.get("message")
        if isinstance(message, str) and message.strip():
            text = message.strip()[:8000]
            self.messages.put(text)
            if self.out is not None:
                self.out.human(text)  # shown at once, delivered with the next turn

    def _reader(self) -> None:
        for line in sys.stdin:
            self.feed(line)
        # stdin closed: the window went away, so the session ends with it.
        self.stop.set()

    def drain(self) -> list[str]:
        out = []
        while True:
            try:
                out.append(self.messages.get_nowait())
            except queue.Empty:
                return out


class Link:
    """A Unix socket the CEDAR AI window attaches to.

    Each new client first receives everything already in events.jsonl, then
    the live stream; whatever it writes is a control line. The session does
    not care whether anyone is attached: the shell can restart and come back.
    """

    def __init__(self, path: Path, control: Control, log: Path, lock: threading.Lock) -> None:
        self.path = path
        self.control = control
        self.log = log
        self.lock = lock
        self.clients: list[socket.socket] = []
        path.parent.mkdir(parents=True, exist_ok=True)
        os.chmod(path.parent, 0o700)
        if path.exists():
            path.unlink()
        self.server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.server.bind(str(path))
        os.chmod(path, 0o600)
        self.server.listen(8)
        threading.Thread(target=self._accept, daemon=True).start()

    def _accept(self) -> None:
        while True:
            try:
                client, _ = self.server.accept()
            except OSError:
                return
            threading.Thread(target=self._serve, args=(client,), daemon=True).start()

    def _serve(self, client: socket.socket) -> None:
        # Replay under the emitter's lock so no live line lands between history and now.
        with self.lock:
            try:
                history = self.log.read_bytes() if self.log.exists() else b""
                if history:
                    client.sendall(history)
            except OSError:
                client.close()
                return
            self.clients.append(client)
        try:
            with client.makefile("r", encoding="utf-8", errors="replace") as fh:
                for line in fh:
                    self.control.feed(line)
        except (OSError, ValueError):
            pass
        finally:
            with self.lock:
                if client in self.clients:
                    self.clients.remove(client)
            client.close()

    def broadcast(self, line: str) -> None:
        """Called with the emitter's lock held."""
        data = line.encode("utf-8")
        for client in list(self.clients):
            try:
                client.sendall(data)
            except OSError:
                self.clients.remove(client)
                client.close()

    def close(self) -> None:
        try:
            self.server.close()
        except OSError:
            pass
        with self.lock:
            for client in self.clients:
                client.close()
            self.clients = []
        try:
            self.path.unlink()
        except OSError:
            pass


def seed_events(session: "Session", log: Path) -> None:
    """A session recorded before it had an event log: its turns, so a window
    attaching later sees the whole exchange."""
    with log.open("w", encoding="utf-8") as fh:
        fh.write(json.dumps(dict(type="session", **session.summary()), ensure_ascii=False) + "\n")
        for turn in session.turns:
            fh.write(json.dumps({"type": "turn.completed", "agent": turn.get("agent", ""), "round": turn.get("round", 0),
                                 "text": turn.get("text", ""), "done": bool(turn.get("done")), "at": turn.get("at", "")}, ensure_ascii=False) + "\n")


def record_running(session: "Session", socket_path: str) -> None:
    STATE_ROOT.mkdir(parents=True, exist_ok=True)
    RUNNING_FILE.write_text(json.dumps({"dir": str(session.dir), "name": session.dir.name, "pid": os.getpid(), "socket": socket_path,
                                        "started": dt.datetime.now().isoformat(timespec="seconds")}) + "\n")


def forget_running() -> None:
    try:
        record = json.loads(RUNNING_FILE.read_text())
        if record.get("pid") == os.getpid():
            RUNNING_FILE.unlink()
    except (OSError, json.JSONDecodeError, AttributeError):
        pass


def live_session() -> dict | None:
    """The running session's record, or None; a record whose process is gone is dropped."""
    try:
        record = json.loads(RUNNING_FILE.read_text())
    except (OSError, json.JSONDecodeError):
        return None
    if not isinstance(record, dict) or not isinstance(record.get("pid"), int):
        return None
    try:
        os.kill(record["pid"], 0)
    except ProcessLookupError:
        try:
            RUNNING_FILE.unlink()
        except OSError:
            pass
        return None
    except PermissionError:
        pass
    return record


# ------------------------------------------------------------------ prompts

def framing(agent: str, partner: str, goal: str, repo: Path) -> str:
    return textwrap.dedent(f"""\
        You are {agent}, one of two coding agents working on the same goal, in the same
        repository at {repo}, through a relay called cedar-ai. The other agent is
        {partner}. A human started this session, reads everything both of you write,
        and may step in.

        How the relay works:
        - You and {partner} share one checkout and one task. You take turns: only one
          of you runs at a time, so you never edit concurrently, but you both edit the
          same files and build on each other's work. Split the task between you when
          that helps, and say which files you touched so {partner} can pick up.
        - Your final reply is delivered to {partner} verbatim as its next message, and
          {partner}'s reply comes back to you the same way. Nothing else is shared, so
          say what matters in the reply.
        - Open every reply after the first with one line that acknowledges what
          {partner} just reported, so the human can see the two of you heard each other
          (for example "Got it, {partner}: the menu entry is in; I'll wire the runtime.").
          On your first turn open with "First turn." instead.
        - Then be short and concrete: what you did, what you found, what you need from
          {partner}, and what comes next. Name files by path. No pleasantries, no
          restating the goal.
        - Build on {partner}'s work. Do not revert, rewrite or "clean up" its changes;
          disagree in your reply instead and let the human settle it.
        - Do not commit, push or publish unless the goal says to.
        - Messages marked "From the human" come from the person running the session
          and take precedence over anything {partner} asked for.
        - Keep going until the goal is actually complete; there is no fixed number of
          turns. End every reply with exactly one of these lines:
            {NEXT}  when you expect something from {partner} (say what)
            {DONE}  when the goal is met and you need nothing more from {partner}
          The session ends when both of you answer {DONE} back to back.

        Goal:
        {goal}
        """)


def solo_framing(agent: str, goal: str, repo: Path) -> str:
    return textwrap.dedent(f"""\
        You are {agent}, working alone on the repository at {repo} through a relay called
        cedar-ai. A human started this session, reads everything you write, and may step
        in with messages marked "From the human", which take precedence.

        How it works:
        - Each turn you work as long as you need, then reply with what you did, what
          you found and what comes next. Name files by path. No pleasantries, no
          restating the goal.
        - Do not commit, push or publish unless the goal says to.
        - Keep going until the goal is actually complete; there is no fixed number of
          turns. End every reply with exactly one of these lines:
            {NEXT}  when there is more to do; you get another turn right away
            {DONE}  when the goal is met
          Say plainly when you need something only the human can give, then end with
          {NEXT}; the human can answer before your next turn.

        Goal:
        {goal}
        """)


def relay_message(sender: str, round_no: int, text: str) -> str:
    return f"From {sender} (round {round_no}):\n{text.strip()}\n"


def human_message(text: str) -> str:
    return f"From the human:\n{text.strip()}\n"


def is_done(text: str) -> bool:
    tail = text.strip().splitlines()[-3:] if text.strip() else []
    return any(DONE in line for line in tail)


# ------------------------------------------------------------------- agents

class AgentError(RuntimeError):
    pass


class Stopped(AgentError):
    pass


CLAUDE_EFFORTS = ("low", "medium", "high", "xhigh", "max")
CODEX_EFFORTS = ("minimal", "low", "medium", "high", "xhigh")
CLAUDE_MODELS = ("fable", "opus", "sonnet", "haiku")


class Agent:
    name = ""

    def __init__(self, repo: Path, mode: str, model: str | None, extra: list[str], timeout: int, out, control: Control,
                 effort: str | None = None):
        self.repo = repo
        self.mode = mode
        self.model = model
        self.effort = effort
        self.extra = extra
        self.timeout = timeout
        self.out = out
        self.control = control
        self.session: str | None = None
        self.stderr = ""
        self.last_usage: dict | None = None   # {input, output, cached, cost} for the turn just run

    def command(self, prompt: str) -> list[str]:
        raise NotImplementedError

    def run(self, prompt: str, raw_log: Path) -> str:
        raise NotImplementedError

    def _spawn(self, cmd: list[str], stdin_text: str | None) -> subprocess.Popen:
        env = dict(os.environ)
        env.pop("CLAUDECODE", None)  # a relay started inside Claude Code is not a nested session
        proc = subprocess.Popen(
            cmd, cwd=self.repo, stdin=subprocess.PIPE if stdin_text is not None else subprocess.DEVNULL,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env,
        )
        if stdin_text is not None and proc.stdin is not None:
            proc.stdin.write(stdin_text)
            proc.stdin.close()
        return proc

    def _finish(self, proc: subprocess.Popen, raw: list[str]) -> None:
        try:
            _, err = proc.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            _, err = proc.communicate()
        self.stderr = (err or "").strip()
        # A process killed by Stop is not a failure, even before it said anything.
        if proc.returncode not in (0, None) and not raw and not self.control.stop.is_set():
            raise AgentError(f"{self.name} exited {proc.returncode}: {self.stderr[-800:]}")

    def _stream(self, cmd: list[str], raw_log: Path, stdin_text: str | None = None):
        """Yield parsed JSON events; kill the process on timeout or stop."""
        proc = self._spawn(cmd, stdin_text)
        started = dt.datetime.now()
        raw: list[str] = []
        try:
            assert proc.stdout is not None
            while True:
                if self.control.stop.is_set():
                    proc.kill()
                    raise Stopped(f"{self.name} stopped")
                # timeout 0 means a turn takes as long as the work takes; Stop still ends it.
                remaining = self.timeout - (dt.datetime.now() - started).total_seconds() if self.timeout > 0 else 1
                if remaining <= 0:
                    proc.kill()
                    raise AgentError(f"{self.name} exceeded {self.timeout}s and was stopped")
                ready, _, _ = select.select([proc.stdout], [], [], min(remaining, 1))
                if not ready:
                    continue
                line = proc.stdout.readline()
                if not line:
                    break
                raw.append(line)
                line = line.strip()
                if not line:
                    continue
                try:
                    yield json.loads(line)
                except json.JSONDecodeError:
                    continue
        finally:
            raw_log.write_text("".join(raw))
            self._finish(proc, raw)


class Claude(Agent):
    name = "claude"

    def command(self, prompt: str) -> list[str]:
        cmd = ["claude", "-p", "--output-format", "stream-json", "--verbose"]
        read_tools = ["Read", "Glob", "Grep",
                      "Bash(git log:*)", "Bash(git diff:*)", "Bash(git status:*)", "Bash(git show:*)"]
        edit_tools = read_tools + ["Edit", "Write", "MultiEdit", "NotebookEdit",
                                   "Bash(git add:*)", "Bash(git commit:*)",
                                   "Bash(python3:*)", "Bash(node:*)", "Bash(npm test:*)",
                                   "Bash(ls:*)", "Bash(cat:*)", "Bash(qmllint:*)", "Bash(qs:*)"]
        if self.mode == "read":
            cmd += ["--allowedTools", ",".join(read_tools)]
        elif self.mode == "edit":
            cmd += ["--permission-mode", "acceptEdits", "--allowedTools", ",".join(edit_tools)]
        elif self.mode == "full":
            cmd += ["--dangerously-skip-permissions"]
        if self.model:
            cmd += ["--model", self.model]
        if self.effort:
            cmd += ["--effort", self.effort]
        if self.session:
            cmd += ["--resume", self.session]
        cmd += self.extra
        return cmd  # the prompt travels over stdin: --allowedTools is variadic

    def run(self, prompt: str, raw_log: Path) -> str:
        reply = ""
        self.last_usage = None
        for event in self._stream(self.command(prompt), raw_log, stdin_text=prompt):
            kind = event.get("type")
            if kind == "assistant":
                for part in event.get("message", {}).get("content", []):
                    if part.get("type") == "tool_use":
                        self.out.activity(self.name, describe_claude_tool(part))
            elif kind == "rate_limit_event":
                limits = claude_limits(event.get("rate_limit_info") or {})
                if limits:
                    remember_limits(self.name, limits)
                    self.out.limits(self.name, limits)
            elif kind == "result":
                self.session = event.get("session_id") or self.session
                reply = event.get("result") or ""
                usage = event.get("usage") or {}
                if isinstance(usage, dict):
                    self.last_usage = {
                        "input": int(usage.get("input_tokens") or 0) + int(usage.get("cache_creation_input_tokens") or 0),
                        "cached": int(usage.get("cache_read_input_tokens") or 0),
                        "output": int(usage.get("output_tokens") or 0),
                        "cost": float(event.get("total_cost_usd") or 0),
                    }
                if event.get("is_error") and not reply:
                    raise AgentError(f"claude reported {event.get('subtype')}")
        if not reply:
            raise AgentError("claude returned no reply" + (f": {self.stderr[-400:]}" if self.stderr else ""))
        return reply


def claude_limits(info: dict) -> dict | None:
    """Claude Code's plan windows from its rate_limit_event: utilization 0..1 and reset times."""
    windows = info.get("unifiedWindows") or {}
    five, week = windows.get("five_hour") or {}, windows.get("seven_day") or {}
    if "utilization" not in five and "utilization" not in week:
        return None
    return {
        "fiveHour": float(five.get("utilization") or 0), "fiveHourResets": int(five.get("resetsAt") or 0),
        "sevenDay": float(week.get("utilization") or 0), "sevenDayResets": int(week.get("resetsAt") or 0),
        "status": str(info.get("status") or ""), "at": dt.datetime.now().isoformat(timespec="seconds"),
    }


def remember_limits(agent: str, limits: dict) -> None:
    """Keep the last plan reading per agent beside the sessions, so the window can show it before a run."""
    path = STATE_ROOT / "limits.json"
    try:
        current = json.loads(path.read_text()) if path.exists() else {}
    except (OSError, json.JSONDecodeError):
        current = {}
    if not isinstance(current, dict):
        current = {}
    current[agent] = limits
    try:
        STATE_ROOT.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(current) + "\n")
    except OSError:
        pass


def known_limits() -> dict:
    path = STATE_ROOT / "limits.json"
    try:
        value = json.loads(path.read_text()) if path.exists() else {}
        return value if isinstance(value, dict) else {}
    except (OSError, json.JSONDecodeError):
        return {}


def describe_claude_tool(part: dict) -> str:
    name = part.get("name", "?")
    inp = part.get("input", {}) or {}
    if name in ("Read", "Edit", "Write", "MultiEdit"):
        return f"{name} {inp.get('file_path', '')}"
    if name == "Bash":
        return f"$ {inp.get('command', '')}"
    if name in ("Glob", "Grep"):
        return f"{name} {inp.get('pattern', '')} {inp.get('path', '')}".rstrip()
    if name == "Agent":
        return f"Agent: {inp.get('description', '')}"
    return name


class Codex(Agent):
    name = "codex"

    def command(self, prompt: str) -> list[str]:
        cmd = ["codex", "exec"]
        if self.session:
            cmd += ["resume"]
        cmd += ["--json", "--skip-git-repo-check"]
        if not self.session:
            cmd += ["--color", "never"]  # `exec resume` does not accept it
        if self.mode == "read":
            cmd += ["-c", 'sandbox_mode="read-only"']
        elif self.mode == "edit":
            cmd += ["-c", 'sandbox_mode="workspace-write"']
        elif self.mode == "full":
            cmd += ["--dangerously-bypass-approvals-and-sandbox"]
        if self.model:
            cmd += ["-m", self.model]
        if self.effort:
            cmd += ["-c", f'model_reasoning_effort="{self.effort}"']
        cmd += self.extra
        if self.session:
            cmd += [self.session]
        cmd += [prompt]
        return cmd

    def run(self, prompt: str, raw_log: Path) -> str:
        messages: list[str] = []
        failure = ""
        self.last_usage = None
        for event in self._stream(self.command(prompt), raw_log):
            kind = event.get("type")
            item = event.get("item") or {}
            if kind == "thread.started":
                self.session = event.get("thread_id") or self.session
            elif kind == "turn.completed" and isinstance(event.get("usage"), dict):
                usage = event["usage"]
                self.last_usage = {
                    "input": int(usage.get("input_tokens") or 0), "cached": int(usage.get("cached_input_tokens") or 0),
                    "output": int(usage.get("output_tokens") or 0) + int(usage.get("reasoning_output_tokens") or 0), "cost": 0.0,
                }
            elif kind == "item.started" and item.get("type") == "command_execution":
                self.out.activity(self.name, "$ " + strip_shell_wrapper(item.get("command", "")))
            elif kind == "item.completed":
                itype = item.get("type")
                if itype == "agent_message":
                    messages.append(item.get("text") or "")
                elif itype == "file_change":
                    for change in item.get("changes") or []:
                        self.out.activity(self.name, f"{change.get('kind', 'edit')} {change.get('path', '')}")
                elif itype == "command_execution" and item.get("exit_code") not in (0, None):
                    self.out.activity(self.name, f"exit {item.get('exit_code')}")
            elif kind == "turn.failed":
                failure = json.dumps(event.get("error") or event)[:400]
            elif kind == "error":
                failure = event.get("message") or json.dumps(event)[:400]
        if failure and not messages:
            raise AgentError(f"codex failed: {failure}")
        if not messages:
            raise AgentError("codex returned no reply" + (f": {self.stderr[-400:]}" if self.stderr else ""))
        return "\n\n".join(m for m in messages if m.strip())


def strip_shell_wrapper(command: str) -> str:
    match = re.match(r"^(?:/usr/bin/)?(?:bash|sh|zsh) -lc (['\"])(.*)\1$", command, re.S)
    return match.group(2) if match else command


# ------------------------------------------------------------------ session

class Session:
    def __init__(self, directory: Path):
        self.dir = directory
        self.raw = directory / "raw"
        self.transcript = directory / "transcript.md"
        self.turns_file = directory / "turns.json"
        self.state_file = directory / "state.json"
        self.state: dict = {}
        self.turns: list[dict] = []

    @classmethod
    def create(cls, goal: str, repo: Path, mode: str, agents: str = "both") -> "Session":
        stamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
        slug = re.sub(r"[^a-z0-9]+", "-", goal.lower()).strip("-")[:40] or "session"
        session = cls(STATE_ROOT / f"{stamp}-{slug}")
        session.raw.mkdir(parents=True)
        session.state = {
            "goal": goal, "repo": str(repo), "mode": mode, "agents": agents, "started": stamp,
            "claude_session": None, "codex_thread": None, "rounds": 0, "turns": 0, "finished": "",
        }
        session.transcript.write_text(f"# cedar-ai session {stamp}\n\nRepository: {repo}\nMode: {mode}\nAgents: {agents}\n\n## Goal\n\n{goal}\n")
        session.save()
        return session

    @classmethod
    def load(cls, ref: str) -> "Session":
        path = Path(ref)
        if ref == "latest":
            candidates = sorted(p for p in STATE_ROOT.iterdir() if (p / "state.json").exists()) if STATE_ROOT.exists() else []
            if not candidates:
                raise SystemExit("cedar-ai: no sessions recorded yet")
            path = candidates[-1]
        elif not path.exists():
            path = STATE_ROOT / ref
        session = cls(path)
        session.state = json.loads(session.state_file.read_text())
        try:
            session.turns = json.loads(session.turns_file.read_text())
        except (OSError, json.JSONDecodeError):
            session.turns = []
        return session

    def save(self) -> None:
        self.state_file.write_text(json.dumps(self.state, indent=2) + "\n")
        self.turns_file.write_text(json.dumps(self.turns, ensure_ascii=False) + "\n")

    def record(self, heading: str, text: str) -> None:
        with self.transcript.open("a") as fh:
            fh.write(f"\n## {heading}\n\n{text.strip()}\n")

    def add_turn(self, agent: str, round_no: int, text: str, done: bool) -> None:
        self.turns.append({"agent": agent, "round": round_no, "text": text, "done": done,
                           "at": dt.datetime.now().isoformat(timespec="seconds")})

    def add_usage(self, agent: str, turn: dict) -> dict:
        """Add one turn's tokens (and Claude's reported cost) to the session's totals for that agent."""
        usage = self.state.setdefault("usage", {})
        total = usage.get(agent) or {"input": 0, "cached": 0, "output": 0, "cost": 0.0, "turns": 0}
        for key in ("input", "cached", "output"):
            total[key] = int(total.get(key, 0)) + int(turn.get(key, 0))
        total["cost"] = round(float(total.get("cost", 0)) + float(turn.get("cost", 0)), 4)
        total["turns"] = int(total.get("turns", 0)) + 1
        usage[agent] = total
        return total

    def summary(self) -> dict:
        return {"dir": str(self.dir), "name": self.dir.name, "goal": self.state.get("goal", ""),
                "repo": self.state.get("repo", ""), "mode": self.state.get("mode", ""),
                "agents": self.state.get("agents", "both"), "models": self.state.get("models") or {},
                "usage": self.state.get("usage") or {},
                "started": self.state.get("started", ""), "rounds": self.state.get("rounds", 0),
                "turns": self.state.get("turns", 0), "finished": self.state.get("finished", "")}


def sessions() -> list[dict]:
    if not STATE_ROOT.exists():
        return []
    found = []
    for path in sorted(STATE_ROOT.iterdir(), reverse=True):
        if (path / "state.json").exists():
            try:
                found.append(Session.load(str(path)).summary())
            except (OSError, json.JSONDecodeError):
                continue
    return found


# --------------------------------------------------------------------- loop

def run_relay(args: argparse.Namespace, out, control: Control) -> int:
    repo = Path(args.repo).resolve()
    if not repo.is_dir():
        out.error(f"repository not found: {repo}")
        return 2

    if args.resume_session:
        session = Session.load(args.resume_session)
        repo = Path(session.state["repo"])
        goal = session.state["goal"]
        if args.mode is None:
            args.mode = session.state.get("mode", "edit")
        if args.agents is None:
            args.agents = session.state.get("agents", "both")
    else:
        goal = args.goal or ""
        if not goal.strip():
            out.error("give a goal, or --resume-session")
            return 2
        if args.mode is None:
            args.mode = "edit"
        if args.agents is None:
            args.agents = "both"
        session = Session.create(goal, repo, args.mode, args.agents)

    if args.socket:
        out.open_link(session, args.socket, control)

    # Both agents take turns; one agent works alone, turn after turn.
    order = list(AGENT_NAMES) if args.agents == "both" else [args.agents]
    if args.agents == "both" and args.first == "codex":
        order.reverse()
    solo = len(order) == 1
    for tool in order:
        if shutil.which(tool) is None:
            out.error(f"{tool} is not on PATH")
            return 2

    # A resumed session keeps the models it started with unless told otherwise.
    chosen = session.state.get("models") or {}
    for name, model_arg, effort_arg in (("claude", "claude_model", "claude_effort"), ("codex", "codex_model", "codex_effort")):
        saved = chosen.get(name) or {}
        model = getattr(args, model_arg) if getattr(args, model_arg) is not None else saved.get("model") or ""
        effort = getattr(args, effort_arg) if getattr(args, effort_arg) is not None else saved.get("effort") or ""
        chosen[name] = {"model": model, "effort": effort}
    session.state["models"] = chosen
    agents = {
        "claude": Claude(repo, args.mode, chosen["claude"]["model"] or None, args.claude_arg or [], args.turn_timeout, out, control, chosen["claude"]["effort"] or None),
        "codex": Codex(repo, args.mode, chosen["codex"]["model"] or None, args.codex_arg or [], args.turn_timeout, out, control, chosen["codex"]["effort"] or None),
    }
    agents["claude"].session = session.state.get("claude_session")
    agents["codex"].session = session.state.get("codex_thread")

    interactive = sys.stdin.isatty() and not args.auto and not args.events
    introduced = {name: bool(agents[name].session) for name in AGENT_NAMES}

    info = session.summary()
    info["resumed"] = bool(args.resume_session)
    out.session(info)

    pending_human = args.message or ""
    if args.resume_session and not pending_human and interactive:
        try:
            pending_human = input(f"message for {'both agents' if not solo else order[0]} to pick the session back up: ").strip()
        except EOFError:
            pending_human = ""
    if pending_human:
        session.record("Human", pending_human)
        out.human(pending_human)

    last_reply: dict[str, str] = {}
    last_sender: str | None = None
    done_streak = 0
    round_no = session.state.get("rounds", 0)
    turns_total = session.state.get("turns", 0)
    # rounds 0: no limit; the agents decide when the goal is complete.
    limit = round_no + args.rounds if args.rounds > 0 else float("inf")

    def persist(finished: str = "") -> None:
        session.state["claude_session"] = agents["claude"].session
        session.state["codex_thread"] = agents["codex"].session
        session.state["rounds"] = round_no
        session.state["turns"] = turns_total
        session.state["finished"] = finished
        session.save()

    try:
        while round_no < limit:
            round_no += 1
            for name in order:
                for message in control.drain():
                    pending_human = (pending_human + "\n\n" + message).strip()
                    session.record("Human", message)
                if control.stop.is_set():
                    persist("stopped")
                    out.finished("stopped")
                    return 0
                agent = agents[name]
                partner = "codex" if name == "claude" else "claude"
                parts: list[str] = []
                if not introduced[name]:
                    parts.append(solo_framing(name, goal, repo) if solo else framing(name, partner, goal, repo))
                    introduced[name] = True
                if pending_human:
                    parts.append(human_message(pending_human))
                if not solo and last_sender == partner and partner in last_reply:
                    relay_round = round_no if name != order[0] else round_no - 1
                    parts.append(relay_message(partner, relay_round, last_reply[partner]))
                    out.relay(partner, name, relay_round)
                elif not parts or (len(parts) == 1 and parts[0].startswith("You are")):
                    parts.append("Begin." if turns_total == 0 else "Continue.")
                prompt = "\n".join(parts)

                out.turn_started(name, round_no)
                turns_total += 1
                raw_log = session.raw / f"{turns_total:03d}-{name}.jsonl"
                try:
                    reply = agent.run(prompt, raw_log)
                except Stopped:
                    turns_total -= 1
                    persist("stopped")
                    out.finished("stopped")
                    return 0
                except AgentError as exc:
                    out.error(str(exc))
                    session.record(f"Round {round_no} · {name} · ERROR", str(exc))
                    persist("error")
                    out.finished("error", str(exc))
                    return 1
                done = is_done(reply)
                out.turn_completed(name, round_no, reply, done)
                session.record(f"Round {round_no} · {name}", reply)
                session.add_turn(name, round_no, reply, done)
                if agent.last_usage:
                    total = session.add_usage(name, agent.last_usage)
                    out.usage(name, agent.last_usage, total)
                last_reply[name] = reply
                last_sender = name
                pending_human = ""
                done_streak = done_streak + 1 if done else 0
                persist()
                if done_streak >= (1 if solo else 2):
                    persist("done")
                    out.finished("done")
                    return 0

            if interactive:
                try:
                    answer = input(f"[Enter] next {'turn' if solo else 'round'} · type a message for the {'agent' if solo else 'agents'} · q to stop: ").strip()
                except EOFError:
                    answer = "q"
                if answer.lower() in ("q", "quit", "exit"):
                    persist("stopped")
                    out.finished("stopped")
                    return 0
                if answer:
                    pending_human = answer
                    session.record("Human", answer)
                    out.human(answer)
    except KeyboardInterrupt:
        print()
        persist("stopped")
        out.finished("stopped")
        return 130

    persist("rounds")
    out.finished("rounds", f"round limit reached ({args.rounds}); resume with --resume-session latest")
    return 0


# -------------------------------------------------------------------- serve

def model_choices() -> dict:
    """What each tool can run: Claude's aliases and effort levels, Codex's listed
    models (from its own cache) with their reasoning levels, and Codex's
    configured default. Nothing is invented: without the cache, Codex's list is
    empty and the window offers only the default."""
    codex_home = Path(os.environ.get("CODEX_HOME", Path.home() / ".codex"))
    codex_models: list[dict] = []
    try:
        cache = json.loads((codex_home / "models_cache.json").read_text())
        for entry in cache.get("models", []) if isinstance(cache, dict) else []:
            if not isinstance(entry, dict) or entry.get("visibility") != "list" or not entry.get("slug"):
                continue
            levels = []
            for level in entry.get("supported_reasoning_levels") or []:
                value = level.get("effort") or level.get("level") or level.get("id") if isinstance(level, dict) else level
                if isinstance(value, str) and value in CODEX_EFFORTS and value not in levels:
                    levels.append(value)
            codex_models.append({"id": entry["slug"], "label": entry.get("display_name") or entry["slug"],
                                 "efforts": levels or list(CODEX_EFFORTS), "defaultEffort": entry.get("default_reasoning_level") or ""})
    except (OSError, json.JSONDecodeError, AttributeError, TypeError):
        codex_models = []
    codex_default = {"model": "", "effort": ""}
    try:
        for line in (codex_home / "config.toml").read_text().splitlines():
            match = re.match(r'^\s*(model|model_reasoning_effort)\s*=\s*"([^"]*)"', line)
            if match:
                codex_default["model" if match.group(1) == "model" else "effort"] = match.group(2)
    except OSError:
        pass
    return {
        "claudeModels": [{"id": alias, "label": alias.capitalize()} for alias in CLAUDE_MODELS],
        "claudeEfforts": list(CLAUDE_EFFORTS),
        "codexModels": codex_models,
        "codexEfforts": list(CODEX_EFFORTS),
        "codexDefault": codex_default,
    }


def serve() -> int:
    """One JSON request on stdin, one {ok, data|error} reply on stdout."""
    try:
        request = json.loads(sys.stdin.readline() or "{}")
    except json.JSONDecodeError:
        request = {}
    action = request.get("action") if isinstance(request, dict) else None
    try:
        if action == "sessions":
            data = {"sessions": sessions()[:50], "root": str(STATE_ROOT), "running": live_session()}
        elif action == "running":
            data = {"running": live_session()}
        elif action == "kill":
            live = live_session()
            if live:
                os.kill(live["pid"], signal.SIGTERM)
            data = {"killed": bool(live)}
        elif action == "transcript":
            target = Path(str(request.get("dir") or "")).resolve()
            if STATE_ROOT.resolve() not in target.parents:
                raise ValueError("not a cedar-ai session")
            session = Session.load(str(target))
            data = {"session": session.summary(), "turns": session.turns}
        elif action == "tools":
            data = {tool: shutil.which(tool) or "" for tool in ("claude", "codex")}
            data.update(model_choices())
            data["limits"] = known_limits()
        else:
            raise ValueError("unknown action")
        sys.stdout.write(json.dumps({"ok": True, "data": data}) + "\n")
    except Exception as exc:  # noqa: BLE001 - the reply carries the reason
        sys.stdout.write(json.dumps({"ok": False, "error": str(exc)}) + "\n")
    return 0


# --------------------------------------------------------------------- main

def parse(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="cedar-ai",
        description="Let Claude Code and Codex CLI work a goal together, turn by turn, in one checkout.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=textwrap.dedent("""\
            examples:
              cedar-ai "Add a Capture submenu to menus/cedar-menu.jsonc that screenshots with grim"
              cedar-ai --mode read --rounds 2 "Review the latest merge for visual regressions"
              cedar-ai --resume-session latest -m "Codex, now write the test"
              cedar-ai --list
            """),
    )
    parser.add_argument("goal", nargs="?", help="what the two agents should accomplish")
    parser.add_argument("--repo", default=os.getcwd(), help="checkout both agents work in (default: cwd)")
    parser.add_argument("--mode", choices=MODES, default=None,
                        help="read: no edits; edit: edits plus git/python/node (default); full: no sandbox at all")
    parser.add_argument("--agents", choices=("both", "claude", "codex"), default=None,
                        help="both agents taking turns (default), or one agent working alone")
    parser.add_argument("--first", choices=AGENT_NAMES, default="claude", help="who speaks first (default: claude)")
    parser.add_argument("--rounds", type=int, default=0,
                        help="rounds (each agent speaks once per round) before pausing; 0 means until the goal is done (default)")
    parser.add_argument("--auto", action="store_true", help="never pause for the human between rounds")
    parser.add_argument("--turn-timeout", type=int, default=0, help="seconds one agent may take per turn; 0 means as long as it needs (default)")
    parser.add_argument("--claude-model", help="model for Claude Code: an alias (fable, opus, sonnet, haiku) or a full name (default: its configured model)")
    parser.add_argument("--claude-effort", choices=CLAUDE_EFFORTS, help="effort for Claude Code (default: its configured level)")
    parser.add_argument("--codex-model", help="model for Codex, e.g. gpt-6-astra (default: its configured model)")
    parser.add_argument("--codex-effort", choices=CODEX_EFFORTS, help="reasoning effort for Codex (default: its configured level)")
    parser.add_argument("--claude-arg", action="append", metavar="ARG", help="extra flag for claude (repeatable)")
    parser.add_argument("--codex-arg", action="append", metavar="ARG", help="extra flag for codex (repeatable)")
    parser.add_argument("--resume-session", metavar="DIR|latest", help="continue a recorded session")
    parser.add_argument("-m", "--message", help="a message from you delivered with the next turn")
    parser.add_argument("--events", action="store_true", help="JSON lines on stdout, control lines on stdin (no pauses)")
    parser.add_argument("--serve", action="store_true", help="answer one JSON request on stdin (sessions, transcript, tools, running, kill)")
    parser.add_argument("--socket", metavar="PATH", help="serve the event stream at a Unix socket and record the session as running")
    parser.add_argument("--detach", action="store_true", help="run the session as its own process (apart from the window) and print where to attach")
    parser.add_argument("--list", action="store_true", help="list recorded sessions")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse(sys.argv[1:] if argv is None else argv)
    if args.serve:
        return serve()
    if args.list:
        found = sessions()
        if not found:
            print("no sessions yet")
        for s in found:
            print(f"{s['name']}  rounds={s['rounds']}  {s['finished'] or 'open':8}  {s['goal'].replace(chr(10), ' ')[:70]}")
        return 0
    if args.rounds < 0:
        args.rounds = 0
    if args.detach:
        return detach(args)
    events = bool(args.events or args.socket)
    out = Emitter() if events else Terminal()
    # Over a socket the control lines come from attached windows; stdin is not
    # read, so a window going away never ends the session. Stop, or SIGTERM, does.
    control = Control(listen=events and not args.socket, out=out if events else None)
    if args.socket:
        signal.signal(signal.SIGTERM, lambda *_: control.stop.set())
    try:
        return run_relay(args, out, control)
    finally:
        out.close_link()


def detach(args: argparse.Namespace) -> int:
    """Launch this same command as its own process, apart from whoever asked,
    and print one line saying where to attach. A transient systemd user unit
    keeps it out of the shell's control group, so restarting the shell leaves
    it running; without systemd it is started in its own session instead."""
    stamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    sock = Path(args.socket) if args.socket else RUNTIME_ROOT / f"{stamp}.sock"
    sock.parent.mkdir(parents=True, exist_ok=True)
    os.chmod(sock.parent, 0o700)
    passed = sys.argv[1:]
    rest: list[str] = []
    skip = False
    for arg in passed:
        if skip:
            skip = False
            continue
        if arg == "--detach":
            continue
        if arg == "--socket":
            skip = True
            continue
        if arg.startswith("--socket="):
            continue
        rest.append(arg)
    command = [sys.executable, str(Path(__file__).resolve()), "--socket", str(sock), *rest]
    unit = f"cedar-ai-{stamp}"
    launcher = os.environ.get("CEDAR_AI_LAUNCHER", "")
    if launcher != "fork" and shutil.which("systemd-run"):
        run = ["systemd-run", "--user", "--collect", "--quiet", f"--unit={unit}", f"--property=WorkingDirectory={os.getcwd()}"]
        for key in CARRIED_ENV:
            if os.environ.get(key):
                run.append(f"--setenv={key}={os.environ[key]}")
        result = subprocess.run(run + command, stdin=subprocess.DEVNULL, capture_output=True, text=True)
        if result.returncode == 0:
            print(json.dumps({"type": "launched", "socket": str(sock), "unit": unit, "pid": 0}))
            return 0
        sys.stderr.write(f"cedar-ai: systemd-run failed ({result.stderr.strip()[-300:]}); starting the session in its own process group\n")
    log = sock.with_suffix(".log")
    env = dict(os.environ)
    env.pop("CLAUDECODE", None)
    with log.open("ab") as fh:
        proc = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=fh, stderr=subprocess.STDOUT, start_new_session=True, env=env)
    print(json.dumps({"type": "launched", "socket": str(sock), "unit": "", "pid": proc.pid}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
