# Security model and hardening

CEDAR runs as the logged-in user. Everything it can do, any other process of
that user can also do; the shell is not a privilege boundary. Hardening here
is about three things: never turning a mistake into a shell, keeping the lock
screen honest, and making the local IPC surface refuse what it does not need.

## Trust boundaries

| Boundary | Position |
|---|---|
| Other users and the network | Outside. Local-only is the default; see PRIVACY.md. |
| Other processes of the same user | Trusted by the operating system, but CEDAR still validates everything they send over IPC (below) so that a bug elsewhere cannot be amplified by the shell. |
| Configuration files under `~/.config/cedar` | Trusted input. Written with mode 600 in a mode 700 directory, read with bounded JSON parsing, and never executed. |
| The session lock | Enforced by `WlSessionLock` (ext-session-lock) and PAM. The lock surface is always opaque; hot reload is disabled while locked; `shell stop` and settings writes are refused while locked. |

## IPC surface

Every `qs ipc` target the shell exposes, and what it will refuse:

| Target | Methods | Guarded by |
|---|---|---|
| `settings` | `toggle`, `set`, `get` | `set` and `get` consult `Config.ipcProtected`: application commands, network and location switches, lock privacy, clipboard history, trails and the whisper ledger are refused. Values are type-checked and strings capped at 1000 characters. `set` is refused while locked. |
| `menu` | `toggle`, `summon`, `refresh` | Refused while locked. `summon` payloads above 256 KiB are ignored; prompts, option counts and option lengths are capped. Reply files are answered only through `scripts/menu_reply.py` (below). |
| `core` | `publish`, `withdraw`, `timer`, … | Payloads above 16 KiB are refused. Provider identities are validated by regular expression; titles and subtitles are control-character stripped and capped; providers cannot attach actions. |
| `osd` | `fromOmarchy`, `volume`, … | Payloads above 4 KiB are ignored; numeric fields are range-checked. |
| `lock` | `lock`, `testAuthentication` | Refused in test mode; the test window never requests a session lock. |
| `shell` | `close`, `isLocked`, `sessionInfo`, `stop` | `stop` is refused while locked. |
| `wallpapers`, `themes`, `control`, `hud`, `power`, `canopy`, `launcher`, `notifications`, `media` | toggles | All route through `ShellState`/`Canopy`, which refuse while locked. |

## Prompt replies

Omarchy's select/input helpers create a selection file with `mktemp`, remove a
second `mktemp` name to serve as a done marker, and send both paths with the
prompt. The paths therefore come from the IPC caller. `scripts/menu_reply.py`
is the only writer and enforces: absolute paths inside a temporary directory,
an existing selection file that is a regular file owned by the user, opened
without following symlinks, and a done marker created with `O_EXCL`. No shell
string is built from either path. Replies are queued in order so a prompt that
is answered while a previous reply is still being written is never lost.

## Subprocesses

Helpers are started with argument vectors, never shell strings, and read their
requests as one JSON line on stdin so secrets never appear in `/proc/*/cmdline`.
Responses are size-limited and time-limited by `ServiceRequest`. The two places
that run `bash` are the menu actions and guards that Omarchy's menu format
defines as shell expressions; they come from the shipped and user menu files,
not from IPC.

## What is not claimed

No sandboxing of QML, user menu entries or helper scripts. No protection from a
compromised same-user process. Native PAM, lock coverage during suspend, and
hardware acceptance are verified only on controlled devices, as recorded in
LOCAL-VERIFICATION.md.

## Privilege prompts

CEDAR registers as the session's polkit authentication agent
(`services/Permission.qml`, `modules/PermissionPrompt.qml`) when it is the
shell. A request from pkexec or any polkit client is shown on the main
display with exclusive keyboard focus; the response travels to
polkit-agent-helper over D-Bus inside the process. Nothing about a request
is logged, and a locked session cancels any open request. Under the Omarchy
adapter the Omarchy shell remains the agent.
