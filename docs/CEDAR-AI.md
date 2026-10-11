# CEDAR AI

Two coding agents, Claude Code and Codex CLI, working one goal together,
turn by turn, in one checkout, or either one on its own. The window opens on
Super+Shift+A, from Go (“CEDAR AI” under CEDAR, and as an application beside
Shield), with `cedar ai` from the installed command, from `cedar-ai` in a
terminal, or over IPC. The relay itself is `scripts/cedar_ai.py`; the shell
is a presentation over it, and a session is not tied to the shell: it runs as
its own process, and the window attaches to it.

## How a session runs

- Both agents run headless (`claude -p` and `codex exec`) and keep their own
  session, so each remembers the whole conversation and its own work.
- They share the goal and the checkout. They alternate: only one runs at a
  time, so they never edit the checkout at once, but they edit the same files
  and build on each other's work. Whatever one writes as its final reply is
  handed to the other as its next message, verbatim, and the conversation
  shows each hand-off. Each agent opens its reply by acknowledging what the
  other just reported, so you can see they heard each other.
- Or one agent works alone (Agents: Claude or Codex), turn after turn, with
  the same goal, access and messages from you.
- A session runs until the goal is done: every reply ends with `[NEXT]` (more
  to do) or `[DONE]`, and it stops when both agents say `[DONE]` back to back
  (one agent alone: once), or when you stop it. A turn has no time limit. If
  you set a round count instead, it pauses after that many rounds and can be
  picked back up.
- A message from you is delivered with the next turn as “From the human” and
  outranks whatever the other agent asked for.
- Neither agent commits or pushes unless the goal says to.
- A session started from the window runs apart from the shell, as a transient
  systemd user unit (`cedar-ai-<stamp>`) where there is one, otherwise in its
  own process group. It serves its event stream at a Unix socket under
  `$XDG_RUNTIME_DIR/cedar-ai/`; the window attaches to that socket, replays
  the session so far and follows it live. Restarting the shell, or Quickshell
  reloading, does not touch the session: the service re-attaches on its next
  start, and the Sessions page shows the live one. Only Stop ends it.

## Access

| Mode | Claude Code | Codex CLI |
|---|---|---|
| Read | Read, Glob, Grep, read-only git | `sandbox_mode=read-only` |
| Edit (default) | file edits, git log/diff/status/add/commit, python3, node, qs | `sandbox_mode=workspace-write` |
| Full | `--dangerously-skip-permissions` | `--dangerously-bypass-approvals-and-sandbox` |

Full removes every sandbox for both agents; use it on a checkout you can
throw away.

## Models and effort

Each agent can run a chosen model at a chosen effort, or whatever the tool
itself is set to (the default). Claude Code takes an alias (`fable`, `opus`,
`sonnet`, `haiku`) or a full model name and an effort of `low`, `medium`,
`high`, `xhigh` or `max`. Codex takes a model from the list its own cache
holds (run `codex` once to fill it) and a reasoning effort of `minimal`,
`low`, `medium`, `high` or `xhigh`; the window shows Codex's configured
default beside the Default chip. A session keeps the models it started with
when it is picked back up. In a terminal: `--claude-model`, `--claude-effort`,
`--codex-model`, `--codex-effort`.

## Usage

The session header shows what each agent has used so far, as the tools
themselves report it: tokens in (including cache reads) and out per agent,
Claude's reported cost, and the turn count. These totals are kept with the
session and come back when it is reopened.

Claude Code also reports your plan's 5-hour and 7-day windows on every turn;
the rail and Settings › Tools show them as bars (amber past 80 percent, ember
past 95), with the time of the last reading, which is kept under
`$XDG_STATE_HOME/cedar-ai/limits.json` so it shows before the next run. Codex
CLI reports tokens but no plan window; its own `/status` has that.

## The window

- **Session**: the goal, agents (Both, Claude, Codex), access and rounds
  (Until done, or a number); then the conversation down a spine (Claude
  amber, Codex teal, you green), each hand-off drawn as an arrow between
  turns, the running agent's tool activity beneath the latest turn, and a
  line to step in. Stop ends the session after the running turn. Closing the
  window does not.
- **Sessions**: everything recorded, newest first; opening one shows its
  conversation and lets you pick it back up with the agents it started with.
- **Settings**: the checkout (empty means the shell's own), who works,
  access, rounds before pausing, who speaks first, the model and effort for
  each agent, and whether the tools were found. A Claude-only or Codex-only
  session needs only that tool. The Session page repeats the model pickers for
  the agents in play.

Keyboard: Ctrl+Enter starts the goal or sends your message, Ctrl+1 to 3
switch pages, Escape and Ctrl+W close.

## The terminal

```
cedar-ai "Add a Capture submenu to menus/cedar-menu.jsonc that screenshots with grim"
cedar-ai --mode read --rounds 2 "Review the latest merge for visual regressions"
cedar-ai --agents claude "Write the missing docstrings in scripts/"
cedar-ai --resume-session latest -m "Codex, now write the test"
cedar-ai --list
```

Between rounds the terminal pauses: Enter continues, anything typed goes to
the agents, `q` stops. `--agents claude|codex` runs one agent alone; `--rounds N`
pauses after N rounds (the default, 0, runs until done); `--turn-timeout S`
caps a turn (the default, 0, does not). `--auto` skips the pauses; `--first codex` flips who
opens; `--claude-model` and `--codex-model` override models; `--claude-arg`
and `--codex-arg` pass extra flags through. `--socket PATH` serves the event
stream at a Unix socket and records the session as running, so the window
can attach to a session started in a terminal; `--detach` launches that as
its own process and prints where to attach. `--serve` answers `sessions`
(with the running record), `transcript`, `tools`, `running` and `kill`
(SIGTERM to the running session, which stops it cleanly).

## On disk

Sessions live under `$XDG_STATE_HOME/cedar-ai/<stamp>-<goal>/` (default
`~/.local/state/cedar-ai`):

- `transcript.md` the readable exchange, round by round
- `turns.json` the turns the window reads back
- `events.jsonl` the event stream of a session served at a socket, replayed
  to every window that attaches (a session recorded before it had one is
  seeded from its turns when it is picked back up)
- `state.json` both session ids, the round and turn counts, the goal, the
  checkout, the mode and how the session ended
- `raw/` the JSON event stream of every turn, for debugging

The window and the terminal share these, so a session started in one can be
picked back up in the other. `running.json` beside them names the session
that is running now (its directory, process and socket); it is removed when
that session ends, and a record whose process is gone is dropped on sight.

## IPC

`relay open|close|toggle`, `relay page <session|sessions|settings>`,
`relay start <goal>`, `relay say <message>`, `relay stop`, `relay status`.
`start` and `say` are refused while locked and cap their text at 4000
characters; `start` is ignored while a session runs.

## Requirements

`claude` and `codex` on the shell's PATH, and Python 3.10 or newer. Codex
is run with `--skip-git-repo-check`, so it does not need to trust the
checkout first. Neither tool is required by CEDAR; the window says which one
is missing.
