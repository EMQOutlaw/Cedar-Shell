# Frontend stability and UI performance audit — 2026-10-13

This audit found and corrected five classes of frontend defect: unbalanced audio
visualizer subscriptions, transitions surviving their visibility/motion policy,
stale Canopy geometry, lost workspace thumbnail bindings, and stale Canvas theme
colors. Layouts, palette definitions, typography, icons, effects, animation curves,
durations, keybindings and workflows were preserved. These are development-tree
changes, not an installed release or a claim of exhaustive hardware certification.

## Scope and baseline

Worktree: `Projects/cedar-dev`, branch `dev`, starting revision
`3fa8b175c282c660fcfe364d53e81703fedacce4`. Backend changes already present in
`scripts/`, `installer/engine/`, their unit tests and `docs/SECURITY.md` were left
untouched. No backend service QML was edited. No commit, publication or installation
was performed.

The installed desktop was running the separate release
`1.7-9485470c221185e8`. Installed-session observations must not be presented as
before/after measurements of the modified development source.

Discovery inventoried **214 QML files / 24,693 lines**, including services and test
harnesses. The machine-readable map records each file's imports, component-name
references, service references, loaders and timers. This is a syntactic inventory;
native Qt types sharing a local type name require import-context interpretation.
Animation, connection, timer, Canvas, loader and effect sites were also inventoried.

Private local evidence is in `/tmp/cedar-frontend-audit/`:

- `hierarchy.json`: complete file inventory and component/service references.
- `baseline/`: installed desktop capture, initial resources, 15 initial UI suites,
  screenshots and failing regression reproductions.
- `extended/`: 13 additional component/service-fixture suites.
- `final/`: final affected-component renders and lifecycle test logs.
- `native-smoke/`: full-shell run/reload log, IPC measurements, renderer timing and
  screenshot; standalone keymap/wallpaper logs.
- `visual-comparison.json`: per-image pixel differences and bounds.

The screenshots include the user's desktop and are local evidence, not public
release assets. The native smoke capture contains both the installed bar and the
temporary test bar; it is a smoke-test record, not a pixel-regression reference.

The native environment was Quickshell 0.3.1, one `eDP-1` output at 2880×1800,
120 Hz and 1.6× scaling. No second physical display was available.

## Frontend map and ownership

| Entry point or host | Contents and state/lifetime |
| --- | --- |
| `shell.qml` | IPC routes, shared Core and Canopy hosts, permission/application/HUD lazy loaders, and a `Variants` tree per screen |
| `modules/Bar.qml` | One Strata frame, rootline effects and `StrataBarContents` per output; button anchor providers connect controls to Canopy geometry |
| `StrataBarContents` / `CoreSurface` | Applications, workspace indicators, window/app information, tray, network/audio/clock/Quick controls; integrated Signals hub, volume and media. Core hub retained through closing, then unloaded |
| `CanopyWindow` → `CanopyPanel` | One chosen screen, input mask around the drop, focus grab, explicit open/close/switch state machine, async topic Loader |
| Canopy topics | Quick, audio, network, Bluetooth, power, weather, calendar, clipboard, notifications, trails, Field Station, Applications, startup, workspaces, keybinds |
| `Settings.qml` → `SettingsPanel` | Per-output overlay. Page loader/search/navigation; dirty settings can retain their editor while inactive. Shared state selects output, section and requested page |
| Other overlays | Control Center, Field Station/HUD, notification history, themes, legacy wallpaper picker and power menu; content generally created on visibility |
| `Notifications.qml` / `Osd.qml` | Notification popup stack/history and fallback volume/brightness OSD; Core can own those presentations instead |
| Shield, Profiles, Focus, Station apps | Lazy application windows driven by their service's open state; related transaction HUDs exist during operations |
| `LockScreen` → `TrailwatchView` | Session-lock presentation, instrument/watch/terminal components; authentication and ownership remain backend boundaries |
| `keymap.qml` | Standalone `tools/keymap/Keymap.qml`, read/search reference window |
| `wallpaper-picker.qml` | Standalone `tools/wallpapers/WallpaperGrid.qml` with preview/grid and helper-backed apply |
| `installer.qml` | `InstallerModel`, `StagePane`, `SystemVisual`; updater and Stable/Development selector live here |
| Preview/test entry points | `preview.qml`, `showcase.qml`, `trailwatch-preview.qml`, `auth-test.qml`, `notification-test.qml`, plus `tests/core` and `tests/qml` harnesses |

`Config` and `Theme` supply preferences/tokens. `ShellState` owns shared panel,
output, lock and OSD state. `Canopy` owns topic, pin/peek, output and registered
anchors. `CoreService`, `Forest`, `Motion` and `VisualQuality` govern contextual
presentation and motion policy. UI consumers read native Quickshell services or
the existing Audio, Network, Bluetooth, Media, Pulse, telemetry, clipboard,
notification, calendar/weather, desktop-settings and application services.
Those service contracts were inspected, not rewritten.

No standalone CEDAR screensaver frontend was found. Trailwatch is a lockscreen;
external Omarchy screensavers and their selection/runtime are not certified here.
The Applications drop is the launcher; a separate retired Go window was not
invented or restored.

## Confirmed corrections

| Defect / original reproduction | Root cause and targeted correction | Validation |
| --- | --- | --- |
| Create one CanopyPulse: `Pulse.demand` becomes 2 instead of 1. AudioSpectrum has the same initial-binding/completion pattern. Closing can leave the worker demanded | Both the property-change handler and completion handler acquire the feed. Each component now tracks its actual held subscription and synchronizes idempotently. CanopyPulse also releases when hidden even if its caller keeps `active` true | Original lifecycle check failed with demand 2. Final test exercises 100 cycles of each component, hide/show, activate/deactivate, destruction and simultaneous consumers; demand returns to baseline |
| Hide a KineticLabel's ancestor, disable its animation or enable Reduced Motion during a transition: temporary labels and animations remain allocated | Motion policy was consulted only at text-change time. A reactive motion gate now releases the transition immediately. The existing static label already holds the latest text | Original regression failed all policy/visibility assertions. Final Kinetic suite passes; showing the label does not replay the interrupted text. Visible transitions retain their styles/timing |
| Open Power at 740px available window height, then shrink host to 300px: target stays 288px even though only 245px fits below the bar | Explicit Canopy geometry retargeted on width/content/anchor changes, but omitted window height and bar join changes. Both now use the existing coalesced `reaim()` path | Native actual CanopyWindow fits after vertical shrink, restores original height on expansion, follows bar-height changes, survives 30 rapid reopen/cross-origin switches and host recreation |
| Drag a window thumbnail within its own workspace and release: it stays displaced; later compositor positions no longer move it | MouseArea writes remove x/y bindings; release assigned the displaced coordinates again. Release and cancellation now restore bindings to the same original coordinate calculations | Actual production pointer handlers with a fixture compositor reproduce the original failure. Final test checks same-workspace drop, later geometry changes and cancellation; no real window is moved |
| Change a palette without resizing: Canvas parts retain previous colors while surrounding QML changes | `onPaint` reads are not reactive bindings. Explicit theme-dependency properties now request paint when the values used by the drawing change | Nine component/page images differed from a forced repaint before the fix. Final ten-component comparison matches exactly offscreen. Native comparisons allow at most one 8-bit channel step, after measured GPU rounding of only 3–35 channels per affected image |

Canvas changes add invalidation only. They leave paths, grain, gradients, blur,
geometry and paint operations intact, and introduce no recurring timers. The same
missing invalidation was corrected on the workspace empty-tile Canvas; its empty
tile was outside the initial comparison viewport, so it was not one of the nine
original image failures.

No production binding-loop warning was reproduced in the initial suites. The
resolved QML issues were missing repaint/geometry dependencies and bindings lost
through input handling; this report does not claim to have removed nonexistent
baseline warning messages.

## Interaction and rendering validation

**28 existing suites passed** across the initial and extended runs. Thirteen
affected suites were rerun after the production changes and passed. The new
frontend lifecycle suite passes offscreen and natively. Existing Strata geometry
and Canopy transition JavaScript tests also pass.

| Area | Evidence and practical limit |
| --- | --- |
| Bar, Core, effects, panel navigation | `check_core_bars`, `check_strata_bar`, `check_core_host`, `check_core_ui`, `check_motion`, `check_navigation`, `check_kinetic`; narrow/wide and enlarged text, real Qt pointer/key delivery, hover/pin, allocation and effect resting |
| Canopy and search | `check_canopy`, `check_applications`, `check_compass`; 15 topics at 960/480px, launcher/menu prompts, arithmetic/search, pin/history/privacy. Native lifecycle tests exercise real dropdown transitions |
| Settings/controls | `check_desktop_ui`, `check_controls`, `check_keybinds`, `check_identity`; page navigation/search, dirty drafts, controls, missing fonts, external preference changes, keyboard/empty data and popup geometry |
| Notifications/clipboard/media | Canopy/Core/navigation fixtures cover presentation, actions, privacy and media controls. Full shell test opens their actual destinations; no real clipboard capture or notification ownership is taken |
| Calendar, themes, wallpapers | Calendar suite and theme Preview/Apply/Reset fixture pass. Canvas palette regression added. Both native wallpaper/keymap entry points load without scene errors; no user's wallpaper is applied |
| Installer/update channels | `check_installer_ui` passes stages and keyboard-driven channel controls against its fixture model. No live branch switch, installation or system upgrade is performed |
| Shield, profiles, Focus, Station | Their existing render/fixture suites pass, including Gaming HUD and Station tasks. No firewall, power profile or system-service action is executed against the real machine |
| Lock presentation | `check_trailwatch` passes five viewport sizes, privacy/auth UI/reduced-motion cases. Session, permission, portable UI and Core persistence fixtures pass. Real PAM/unlock security is outside this frontend audit |
| Native shell / reload | Disposable full shell: 58 successful IPC calls, all 15 topics, 14 Settings destinations, menu prompt, Signals, themes, standalone pickers, one hard reload and post-reload Quick Controls. No QML errors, scene warnings or binding loops in this smoke run |

The lifecycle runner modifies only two guards in its temporary copy: it permits
AudioSpectrum's demand binding and native Canopy motion while keeping backend
test mode enabled. Workspace data/dispatch is a test double; production pointer
handlers are unchanged. Native full-shell smoke uses a disposable external-lock
status file. The first smoke attempt without that file correctly kept UI locked;
that was a fixture omission, not a frontend defect.

`qmlformat` accepted 213 of 214 existing QML files. It returns 1 without diagnostics
for the unchanged `modules/ShieldPages.qml`, both before and after this work. The
actual Quickshell Shield rendering suite passes. This formatter result remains an
open tooling discrepancy, not a clean full-tree parser claim. `git diff --check`
and Python syntax checks for changed tests pass.

Offscreen logs contain expected missing Wayland, IPC sandbox, D-Bus and PipeWire
backend warnings. Native lifecycle fixture shutdown occasionally reports 2–18
items still being incubated; this was not reproduced as a QML error or broken
state in the full-shell reload test. It remains recorded rather than filtered out.

## Performance findings

- Installed-session baseline: one 30-second sample, median **1.98% of one CPU
  core**, **65.47 MiB aggregate PSS** for the shell and observable descendants,
  five processes and zero sampled new process identities. This was an active
  desktop, not a controlled idle benchmark. The installed release was not patched,
  so there is no installed before/after CPU or memory claim.
- The confirmed resource win is exact ownership: visualizer create/destroy cycles
  no longer accumulate feed demand. No CAVA process was started in the regression
  fixture. Worker CPU/battery savings in a production audio session remain unmeasured.
- Native full-shell smoke captured **1,904 render-loop records**: median reported
  frame total 4ms, p95 8ms, maximum 31ms; reported render phase median/p95 0ms at
  millisecond log precision, maximum 26ms. Totals include synchronization/swap waits
  and multiple windows. These are diagnostic timings, not physical FPS, input-to-
  photon latency or a before/after speedup. Cold rendering still produces outliers.
- The same run's 58 command round trips had median 25.15ms, p95 32.65ms and maximum
  341.84ms. This includes CLI/process/IPC overhead, not just UI response time.
- Existing Core allocation tests still pass: native window allocation is retained
  through geometry interpolation rather than resized on every animation frame.
  Canopy geometry uses deferred/coalesced retargeting. Decorative policy/effects,
  spectrum cadence, blur and animation duration values were not reduced.
- Thumbnail decode sizes, notification/history bounds, lazy topic/page construction,
  native event-driven status sources and reduced-motion/rest gates were inspected.
  No speculative shader replacement or broad model/architecture rewrite was made.

## Visual regression evidence

131 matching baseline/final capture pairs were compared as 8-bit RGBA pixels.
**72 are pixel-identical**. The other 59 differ in bounded areas including clock
digits, date/time/settings status, animation sampling and raster rounding. For
example, the 640px Strata capture changes only the clock from 17:32 to 17:44.
Representative captures were visually inspected; the machine-readable comparison
retains every differing-pixel count and bounding rectangle.

These non-frozen screenshots do not prove universal pixel identity. The dedicated
Canvas comparison supplies deterministic same-state evidence: no change occurs
when repainting the already-updated offscreen image. Native one-step rounding is
documented above. No screenshot was accepted as evidence for a redesign, and no
style constants or animation curves were edited.

## Files changed by this audit

- Feed lifecycle: `components/AudioSpectrum.qml`, `components/CanopyPulse.qml`.
- Motion lifecycle: `components/KineticLabel.qml`.
- Geometry/input: `modules/CanopyWindow.qml`, `modules/WorkspaceCanopy.qml`.
- Canvas invalidation: `components/ArcGauge.qml`, `components/CedarAtmosphere.qml`,
  `components/HudPanel.qml`, `components/StationCore.qml`,
  `components/TransactionHudCard.qml`, `components/trailwatch/Topo.qml`,
  `components/trailwatch/WatchFace.qml`, `modules/DisplaySettings.qml`,
  `modules/TrailwatchView.qml`, plus the workspace file above.
- Tests: extended `tests/check_kinetic.py`; new `tests/check_frontend_lifecycle.py`.
- Documentation: this report and `FRONTEND-BACKEND-HANDOFF.md`.

To repeat the new checks:

```sh
python3 tests/check_kinetic.py
python3 tests/check_frontend_lifecycle.py
python3 tests/check_frontend_lifecycle.py --native --output /tmp/cedar-native-check
node tests/core/strata_test.js
node tests/core/canopy_transition_test.js
```

New test/documentation files must be included when staging a release, followed by
the repository's `scripts/update_source_inventory.py` workflow. The tracked-file
inventory check passed during this audit; it intentionally does not include
untracked additions until they are staged. No unrelated changes were staged.

## Remaining verification and backend handoff

Physical monitor hot-plug, mixed DPI/rotation, real resolution changes, compositor
restart, long-duration GPU/memory behavior, real notification bursts, actual audio
device/media changes, branch installation, external screensavers and live hardware
actions are **incomplete**. Pointer/key fixtures and host resizing cannot certify
those cases. The temporary source tests and installed-session baseline also do not
certify the installed release with these fixes until it is built and deployed.

See `FRONTEND-BACKEND-HANDOFF.md` for the reproduced polkit ownership issue, portal
warning and service-contract follow-up. No backend-owned file was changed to mask
those findings.
