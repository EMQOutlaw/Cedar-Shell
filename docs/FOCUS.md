# Focus

A timed session in which the desktop quiets itself, then puts everything
back. A sibling to Shield and Gaming Mode: its own window (`cedar focus`,
Go › Focus, the Focus tile in Quick Controls, Super+Shift+F, `qs -c cedar
ipc call focus open`), a preparation card when a session starts and ends,
and a persistent row on the Core pill with Pause and End session.

Start one with `cedar focus 25`, `qs -c cedar ipc call focus start 50`,
or the window (15, 25, 50 or 90 minutes; the default is in Settings ›
Notifications › Focus). Ctrl+Enter starts or ends, Space pauses and
resumes, Escape or Ctrl+W closes the window; the session carries on with
the window closed and survives a shell restart.

## What a session changes

A transaction over CEDAR's own settings, held in the ownership stack under
"focus" so a Desktop Profile and Focus can overlap and both restore
correctly (docs/PROFILES.md describes the stack):

| Step | Setting | Default |
| --- | --- | --- |
| Hold notifications | `doNotDisturb` on | on |
| Silence Whispers | `forestWhispers` off | on |
| Quiet the desktop | `ambientIntensity` 0 and `performanceMode` on (VisualQuality efficient) | on |
| Pause activity trails | `forestTrails` off | off |

Each is verified by reading the setting back; a row that did not take says
so. Ending the session releases each key: back to what Focus found, or left
alone when the user changed it by hand meanwhile, or handed to a profile
that still holds it.

## What is counted

Only what was observed. CEDAR is this session's notification server, so a
notification its popup path hid (ordinary urgency while do-not-disturb is
held and the app is not excepted) counts as **held**; one that reached the
screen (critical, or an excepted app) counts as an **interruption**. If
"Hold notifications" is off, nothing is held and every notice is an
interruption. Focus does not claim to block what it does not deliver.

Exceptions are application names as they announce themselves, matched
case-insensitively, kept in `focusAllowedApps`; an excepted app's popups
show even while do-not-disturb is on.

Completion publishes a sticky high row on the pill ("Focus complete · 25
min · 3 held · 1 interruption") with Dismiss. Every session, completed or
ended early, is a history entry (last 30) with its planned and actual
length and both counts, shown in the window as a timeline.

## The window

The session as a large clock inside a progress ring (retained vector
geometry, twelve branch ticks, no canvas); readings for the session, when it
ends, held and interruptions; the length chips and Start while idle, Pause
and End session while running; the plan or the live rows of what the
session quiets; the exceptions field; the session history. One shared
entrance clock; nothing loops. The only recurring work is a one-second tick
while the window or the expanded pill shows the seconds, a one-minute tick
for the pill's subtitle, and a single shot at the deadline.

## Persistence

`~/.local/state/cedar/focus.json`: the running session (deadline, paused
remainder, counts, the held keys with the values each had before) and the
history. A restarted shell re-holds those keys and carries on; a session
whose deadline passed while the shell was down completes on start.

## Tests

`tests/check_focus.py`: registry from settings, apply and verify through the
stack, the pill row, held and interruption counting from injected notices,
exceptions, pause and resume, nesting with a profile (release underneath a
profile restores nothing; the profile's release restores the originals),
ending early with a history entry, completion at the deadline with the pill
row, and the window at 1000 px.
