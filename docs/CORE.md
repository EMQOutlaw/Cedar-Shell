# CEDAR Core

CEDAR Core is the small contextual surface at the center of the main display's bar. Its chamfered outline, central filament, forest palette and restrained transitions use CEDAR's existing Theme and Station components. It is a single native layer surface; ordinary value changes update its existing controls.

## Use

- At rest, the Core shows the shared 12/24-hour clock. Click to see the date, activities and timer controls.
- Volume and brightness updates open their slider. Hovering or dragging holds it open. Repeated updates keep the same slider instance and explicit OSD state.
- Hover an activity for a small preview. Click for its controls and the activity stack. In the expanded view, Tab moves between controls, arrows select activities, Enter activates, and Escape collapses.
- Settings → CEDAR Core controls the host display, event sources, optional workspace/clipboard feedback and warning thresholds. It follows Main Display by default (the user’s saved preferred output), with one available-output fallback when that display is absent.
- Go → CEDAR → CEDAR Core provides keyboard access through the existing launcher. A dedicated shortcut can be assigned in Core settings; the existing backend checks live bindings and refuses conflicts. No shortcut is installed automatically.
- Disable Core to restore the original bar clock and volume/brightness OSD. Other panels also retain the original OSD while Core is hidden.

## Connected sources and boundaries

| Activity | Actual source and behavior |
|---|---|
| Volume / brightness | Shared native PipeWire Audio, Brightness and explicit ShellState OSD state. |
| Media | Shared native MPRIS player selection; title, artist, art, playback and supported seeking. Track/playback changes get a brief foreground turn; media stays in the stack. |
| Notifications | Critical notifications and their real actions. Other notifications stay in the normal notification system. Core does not copy application notifications into system-activity history. |
| Bluetooth | Native BlueZ connection changes and battery where exposed. |
| Network / VPN | The existing NetworkManager service's snapshots; no separate network polling service. Connectivity changes appear after that service refreshes. |
| Screenshots | Omarchy's saved-screenshot notification and image-path hint. Open, Copy image and Reveal validate the actual local file when clicked. Copy-only captures without a saved-file event do not invent a path. |
| Recording | Current-user gpu-screen-recorder processes, checked every two seconds. PID and process start time identify a recording. The sole Omarchy-owned recorder uses Omarchy's stop/finalize action; independent or multiple recorders use a verified process descriptor and SIGINT for the selected recorder. A stop request is not a claim that a video saved successfully. |
| Microphone / camera | Active, tracked PipeWire capture links with identifiable physical microphone/camera sources. Application names come from the capture stream. Direct ALSA/V4L2 access outside PipeWire and unidentifiable/virtual devices are not covered; absence of an indicator is not a hardware privacy guarantee. |
| Power | Native UPower and shared system power profiles. Low battery below 15%, critical at 5%, recovery at 18% or external power. |
| Workspaces | Native Hyprland focused workspace changes, optional and off by default. |
| Caps / Num Lock | Actual sysfs keyboard LEDs when available; no keypress interception. |
| Updates | Explicit Check updates uses checkupdates for repository packages. No automatic install, invented percentage, AUR total or security classification. Review opens the existing update menu. |
| Health | Shared real temperature sensors and configured filesystem usage, with configurable thresholds and recovery hysteresis. Temperature is not mislabeled as CPU-only. |
| Timer | A real deadline, pause/resume/cancel and acknowledged completion. State persists atomically in `~/.config/cedar/core-timer.json`, including across shell restarts/suspend. |
| Clipboard | Optional generic “Copied” feedback, off by default. No automatic clipboard contents are read, displayed or logged. |
| Files | A real single-file Wayland drop target. Local files owned by the user under home or /tmp expose Open, Copy path, Share, Reveal and two-step Move to Trash. Paths are passed as data, never interpreted as shell commands. Actual compositor drag/drop remains a live-session validation item. |
| Downloads / plugins | Explicit leased publications through the API below. There is no automatic browser download detector, Home Assistant client or Docker integration. |
| Shield | The Shield service's posture, from its real reads: "Attention required" is a high row, "At risk" a sticky critical row, each with Open Shield; "Protected" removes it. |
| Desktop Profiles | The active profile as a persistent row with Leave; the transaction's verified summary and any step that failed. Gaming Mode keeps its own row. |
| Focus | The running session as a persistent row ("18 min left · 3 held") with Pause/Resume and End session, refreshed once a minute; completion is a sticky high row with Dismiss. |

## Activity model

`components/core/Activities.js` contains the pure scheduling policy. `CoreActivityModel.qml` owns reactive state; `CoreService.qml` exposes publication, actions and routing; `CoreSources.qml` adapts existing services. CoreHost selects a single screen-keyed window instance. CoreWindow binds to that instance’s assigned screen for its lifetime. Display preference changes replace the host; activity changes retain it. This avoids moving a visible reused native window between screens during reload. Rendering is split into CoreSurface, CoreVolume, CoreMedia, CoreDetails and CoreHub. `Media.qml` supplies one shared player policy to Core, Field Station, Control Center and media IPC.

Activities have stable IDs, type/source, title/subtitle, priority, progress, persistence, timestamp, attention deadline and whitelisted actions. Dismiss removes a row that can be removed (never a recording or privacy row); there is no snooze, because a row that comes from a live reading (temperature, a posture, a session) would simply be published again by its source. A value update replaces the row with the same identity; it does not recreate a native window. Critical sticky warnings can preempt a selected/held lower-priority activity. Persistent activities settle into the stack after their initial attention interval. Recording/privacy indicators remain visible alongside other foreground activities. The stack is bounded to 64 activities and system history to 32 entries. History is in-memory; only the timer is persisted.

The expiration timer only runs while a deadline needs handling. Its running state never controls visibility. Ambient motion stops while the surface is hidden/covered and respects Reduced Motion. A fixed overlay layer keeps the Core above bars regardless of window creation order. The quiet clock hides when its output is covered: a fullscreen window on the workspace, a focused window whose geometry is the whole output (a borderless game), or Gaming Mode. Alerts, the expanded hub and an open Canopy still bring the pill back. Recording and microphone/camera use do not hold the pill over a game; while covered they show one 8 px ember dot at the top edge that takes no input, so the indication is never lost. Repeated volume updates do not change layers or remap the window. The native input region covers only the visible Core surface, leaving transparent surroundings available to the desktop.

## IPC and provider API

```sh
qs -c cedar ipc call core toggle
qs -c cedar ipc call core show
qs -c cedar ipc call core hide
qs -c cedar ipc call core timer 300 'Tea timer'
```

CEDAR-owned QML sources call `CoreService.publish({...})` and `remove(id)`. Optional external integrations use JSON with an explicit source and provider-local ID:

```sh
qs -c cedar ipc call core publish '{"source":"my-downloader","id":"download-1","type":"progress","title":"Fedora.iso","subtitle":"Downloading","progress":0.68,"persistent":true,"leaseMs":30000}'
qs -c cedar ipc call core withdraw my-downloader download-1
```

This is an example publication format, not an installed download integration. A real provider must renew its lease while active and publish completion only after the underlying operation succeeds.

Provider types are `progress`, `update`, and `integration`; priorities are normal or high. Progress is 0–1. Transient durations are bounded to 0.8–60 seconds. Persistent leases are 1–60 seconds, default 30 seconds, so a failed provider cannot leave a permanent false status. A provider can hold at most eight activities; IDs and text are bounded. Providers cannot request executable actions or impersonate native privacy/recording event types. Source identity is visible in expanded details. IPC is local shell IPC, not authentication of third-party claims.

## Verification

```sh
python3 -m unittest discover -s tests -p 'test_*.py'
node tests/core/activities_test.js components/core/Activities.js
python3 tests/check_core_ui.py
python3 tests/check_core_bars.py
python3 tests/check_core_persistence.py
python3 tests/check_core_host.py
python3 tests/check_desktop_ui.py
python3 tests/check_lock_auth.py
```

The QML tests run with isolated preferences and offscreen rendering. They exercise stable repeated volume updates, visibility hold, priority/preemption, activity stack, timer controls and persistence, six bar layouts with/without Core at two widths, Settings navigation and OSD fallback. They do not send passwords, stop actual recordings, apply display changes or operate real devices. Live compositor focus, hardware events and drag/drop require the actual desktop; shell-load logs are checked separately when deploying.

### Reload stabilization, October 3

The initial live update encountered a native `QWindow::setScreen` null-pointer crash during reload. The Core now uses the same screen-keyed `Variants` pattern as the bars, with a separate native window bound to a fixed output. The host regression test uses two virtual Qt screens and verifies display selection, fallback, enable/disable, stable identity during volume updates and two reloads. Its floating-window test delegate cannot verify Wayland layer placement; that limitation is explicit. Existing Core interaction and timer-persistence tests also pass. Two live file-watcher reloads passed in the same shell instance without a crash or restart. See `CORE-RESUME.md` for the current verification checkpoint.
