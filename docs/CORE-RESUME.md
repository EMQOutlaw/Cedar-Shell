# CEDAR Core — current checkpoint

Historical development notes for the existing Core implementation. CEDAR activation and validation status are documented separately in VERIFICATION.md. User display and clock preferences are preserved by migration.

## Current implementation

Active source: `<source>/cedar-shell` (also `~/.config/quickshell/cedar`). Feature behavior, source limitations and API: `docs/CORE.md`.

`components/core/CoreHost.qml` uses a single screen-keyed Variants instance. `modules/CoreWindow.qml` binds its native window to that instance’s assigned screen; it never migrates that visible window to another output. Fullscreen and sizing information also comes from the assigned screen. Switching the selected monitor replaces the host, while ordinary volume/media/activity updates preserve it. `modules/CedarCore.qml` composes them.

Backup before this repair: `~/.local/state/omarchy-backups/cedar-core-resume-1791079931`. Original pre-Core backup: `~/.local/state/omarchy-backups/cedar-core-1791073103`. Temporary staging, if still present: `/tmp/cedar-core-resume`.

## Verified

- The new `python3 tests/check_core_host.py` regression uses two virtual Qt screens and real floating QWindows with the production host model. Display selection, missing-output fallback, disable/enable, stable window identity across 100 volume updates and two hot reloads pass. Floating windows replace the test’s Wayland delegate; physical layer placement is not simulated.
- Core interaction/rendering and timer restart-persistence tests pass after the repair.
- Two actual file-watcher reloads completed with Configuration Loaded in the same live instance `713341dmt`, process 3931, without a restart or new QML errors. No new coredump was found during verification. The mtime-only touch did not trigger a reload and was not counted.
- The current session’s notification server did not log the earlier ownership-contention warning. A preexisting portal registration warning remains; no system services were changed.
- Previous verification remains recorded: 66 Python tests, activity scheduling tests, six bar layouts at two widths, 15 Settings pages and the lock-auth state test. Unchanged backend tests were not rerun merely for the window-lifecycle repair.

Physical monitor hotplug, actual hardware events and real Wayland file drag/drop still require desktop validation. Do not claim that this change fixes Quickshell itself or proves every native-window failure impossible.

## Earlier crash evidence

A live reload at 21:02:14 caused SIGSEGV in Quickshell 0.3.1 / Qt 6.11.2. Crash report: `~/.cache/quickshell/crashes/2o3zyrcmt/report.txt`; coredump PID 143557. GDB showed QWindow::setScreen with a null this pointer (frame 4, rdi=0). The caller disassembly matched the native proxy-window completion path. Plenty of memory was available, with no evidence of OOM. The temporary extracted core was deleted after inspection.

Upstream source: https://github.com/quickshell-mirror/quickshell/blob/v0.3.1/src/window/proxywindow.cpp — completeWindow hides a visible window before setting its screen without another null check. The exact affected QML window was not proven from debug symbols. The repair removes Core’s visible cross-screen reuse path and passed the live reload checks above.

Do not work around inaccessible compositor/system-bus sockets by inserting host-executed test commands. Existing Super+Space remains the launcher. A dedicated Core shortcut is available through Settings with live conflict checks; none was assigned automatically.
