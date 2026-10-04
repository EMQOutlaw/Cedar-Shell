# CEDAR verification — 2026-10-04

## Installation status

The local CEDAR source is registered at the canonical named Quickshell configuration. Real legacy preferences, custom files and state were backed up and migrated. A value-by-value comparison confirmed the original preferences are unchanged except for the explicit default-bar identifier translation and schema marker. Original source and settings remain available.

**CEDAR is installed but not activated in the desktop session.** The activation guard refused because the development environment cannot query the compositor's lock state. The original named shell remains the only live desktop shell, with its original startup hooks. No live compositor configuration or monitor settings were changed during this task.

Run `~/.local/bin/cedar activate` from an unlocked desktop terminal to complete the guarded handoff. `cedar status` distinguishes the canonical and retained legacy shell. A successful live launch is not claimed by the installer or this report.

## Checks actually run

| Check | Result |
|---|---|
| Python unittest discovery | 106 tests passed, including all inherited tests and migration/activation regressions |
| Activity model JavaScript tests | Passed: priority, stable identity, hold, preemption, bounded history, leased providers |
| Forest policy JavaScript tests | Passed: real semantic state selection, bounded Trails, private Echo exclusions |
| Settings UI harness | Passed: 16 pages at 1180/480px, three Control Center tabs, search, scoped reset, draft protection |
| Core UI harness | Passed: rapid volume updates, held interaction, activity stack, timer and fallback OSD |
| Six bar layouts | Passed at 960/1280px, with Core enabled/disabled |
| Motion harness | Passed: window allocation, interpolation, vector gauges and Reduced Motion |
| Canopy harness | Passed: ten panels at 960/480px, pinning, bounded history and lock privacy |
| Core host harness | Passed: two virtual displays, fallback and two reloads |
| Timer process persistence | Passed: pause/restart/elapsed completion, isolated XDG state storage |
| Lock authentication state machine | Passed without acquiring a session lock or entering a password |
| New identity harness | Passed offline: full Psalm, both John verses, Copy Passage/clipboard attribution, 360/940px, 150% text, missing font, Reduced Motion, unknown-key persistence |
| Installer against actual local data | Passed; repeated installation and migration also passed |
| Fresh installer in isolated home | Passed twice with custom XDG paths containing spaces; no startup activation |
| Migration edge cases | Passed: both namespaces, unknown keys, custom assets, newer-schema rejection, type checks, transaction failure rollback, edited-file recovery protection, destination symlink escape protection |
| Activation model | Passed with mocked session commands: successful handoff, repeat, no duplicate shells, launch failure rollback, customized-file protection, locked/unknown refusal |
| QML syntax | All 125 QML files parsed with the installed qmlformat |
| Scripts | Python parsed/compiled; Bash entry points passed syntax checks |
| Privacy audit | No matches for local identity, personal home paths, private IPv4 endpoints or credential signatures in the new source/docs/assets; copied runtime logs and bytecode excluded |

The physical development stack reports Quickshell 0.3.1, Qt 6.11.2 and Hyprland package 0.56.2. These observations are not a broad compatibility promise. Rajdhani is absent on this system; the readable sans-serif fallback was verified. JetBrainsMono Nerd Font is available. No fonts were bundled.

## Remaining verification and release limits

Offscreen and mocked tests do not prove native Wayland layer placement, physical display timing, monitor refresh-rate performance, multi-monitor focus, real PAM authentication/unlock, Wi-Fi/Bluetooth operations, audio routing on hardware, screen-reader behavior through an accessibility bus, or notification ownership in the live CEDAR session. The full native smoke/notification tests were not run against the protected desktop. UI text has explicit accessible labels and keyboard focus, but an actual assistive-technology session still needs testing.

Systemd activation, theme handoff and recovery commands are implemented and unit-tested; their actual execution still requires the unlocked desktop session. Source/JSON/QML validation is complete; native session behavior remains unverified. Automatic Omarchy activation with custom XDG configuration/state roots is blocked because the installed Omarchy theme command uses fixed default paths. CEDAR migration and registration themselves support those XDG roots.

The original project is a filesystem snapshot without Git metadata, so no tracked/untracked distinction or commit history could be inspected. Runtime logs and a generated source export were excluded from the public source copy. Existing home-path documentation was made generic. No credentials were detected by the current scans, but pattern scans are not a guarantee against every secret format. No history was rewritten and nothing was pushed or published.

Original-source/asset licensing has not been declared by the inherited project. Required Omarchy MIT attribution is retained; Scripture terms are documented separately in LICENSES.md. A public release needs that licensing decision. Unsupported DSP, planned Rituals/Constellation and other unfinished concepts remain explicitly listed in STATUS.md.
