# Strata Control Center architecture and implementation

## Responsive Settings window

Settings can resize down to 480×360 logical pixels. The sidebar folds into a
navigation button when space is limited; its breakpoint accounts for the chosen
text size. Theme and overview cards choose their column count from the available
width, and preference rows stack labels above controls in narrower layouts.
The page heading and draft notice scroll with the content, keeping controls
reachable in short windows. Wide windows center the content within the main pane.

Remembered window dimensions are clamped to the current screen's logical size
when opening. Qt handles display scaling; the layout does not multiply output
scale a second time. Resizing preserves the current page and unapplied drafts.

`tests/check_settings_responsive.py` resizes the real Settings window through
eight size/text combinations and all 26 pages, checks horizontal control bounds
and vertical scrolling, and can retain screenshots via an output-directory
argument. It also runs under `QT_SCALE_FACTOR=1.5` for local HiDPI validation.

## Phase zero: verified architecture

The supplied showcase defines composition, not new shell primitives. The Settings
window remains `modules/Settings.qml`, routed by `ShellState` and the singleton
`services/SettingsService.qml`. Work is isolated from the running checkout.

| Area | Existing implementation | Integration boundary |
| --- | --- | --- |
| Entry and windows | `shell.qml`, `Settings.qml`, `FieldStation.qml` | Keep one Settings window; leave bar, lock, station and IPC ownership intact. |
| Strata and Dynamic Island | `StrataBarContents.qml`, `StrataBarFrame.qml`, `CoreHost.qml`, `CoreSurface.qml`, `CoreService.qml` | Core is CEDAR's Dynamic Island. Preview shared renderers without interactive live shell actions. |
| Morph geometry | `components/core/StrataGeometry.js`, `Canopy.qml`, `CanopyWindow.qml`, `DropFrame.qml` | Reuse logical bounds and shape; preview actions never open production panels. |
| Motion and type | `Theme.qml`, `VisualQuality.qml`, `Motion.qml`, `Kinetic.js`, `KineticLabel.qml` | Use existing preset, duration and reduced-motion policy. No second animation engine. |
| Grain and Living Edge | `StrataBarFrame.qml`, `DropFrame.qml`, `ChamferFrame.qml`, `CedarRootlines.qml`, `CedarHeartwood.qml` | These are retained paths, grain lips and event-driven edge traces, not standalone Grain/LivingEdge modules. Reuse them; do not imply unsupported independent controls. |
| Theme and preferences | `Config.qml`, `SettingsSchema.js`, `Theme.qml`, `desktop_runtime.py` | Existing typed settings remain authoritative. Theme preview must stay local until explicit apply; save a guarded previous snapshot for restore. |
| System inventory | `SettingsInfo.qml`, `settings_info.py`, `desktop_runtime.py` | Bounded, on-demand inventory; real installed themes and wallpapers only. |
| Displays/input/shortcuts | `DesktopSettings.qml`, `desktop.py`, Display/Input/Keybind settings | Preserve CEDAR-owned generated files, syntax checks, conflict checks, independent display rollback watchdog and confirmation deadline. Never replace user-owned config. |
| Desktop profiles | `Profiles.qml`, `Profiles.js`, `Overrides.qml`, `Transaction.qml`, `Gaming.qml` | Existing definitions, preparation, readback, restoration and ownership layering. No invented active Balanced profile. |
| Shield/Signals | `Shield.qml`, `ShieldPages.qml`, `CoreSources.qml`, `NoticeStore.qml` | Provider-derived status, explicit security actions, existing authentication and rollback. Signals is Core's notification hub. |
| Updates/recovery | `cedar_cli.py`, `update_checkout.py`, `distribution.py`, System settings | Separate CEDAR release information from repository package checks. Unknown is not up to date. No automatic install. |
| Wallpapers/screensavers | `desktop_runtime.py`, Desktop settings, `WallpaperPicker.qml`, Trailwatch | Wallpaper ownership is provider-specific; current setting applies to all outputs. No independent CEDAR screensaver selection/speed backend found. Trailwatch is a secure locker, not a screensaver. |

## Missing or constrained capabilities

- Grouped persistent navigation and the requested Overview composition need new
  presentation over existing state. Existing page IDs must stay routable.
- Settings needs local theme selection/preview and explicit apply/restore.
- Motion laboratory and bar preview must reuse production surfaces and gates.
- Module ordering, separate horizontal bar padding, independent Living Edge/grain
  intensity, arbitrary custom accents, per-monitor wallpaper and screensaver
  selection are not existing capabilities. Surface those limits honestly rather
  than storing ineffective preferences.
- General window-rule/tiling editing is not an existing safe Settings backend.
  Show available information and distinguish unavailable editing.
- Existing System settings is a manual signed-archive workflow; do not confuse
  a successful Arch package query with verification of a CEDAR release.

## Ownership and regression risks

`settings.json` is CEDAR preference state. Theme writes target CEDAR's `theme.json`.
Wallpaper actions go through the current provider. Display/input/keybind changes
use `desktop.py`'s owned fragments and managed include, retaining concurrent user
changes. Profiles retain the existing override stack. Network and security writes
remain with their existing providers and confirmation flows. Preview interaction
must not call live Core, workspace, media, volume or Canopy actions.

The critical regressions are stale draft loss, wrong advanced-search targets,
misleading update/protection state, duplicate shell actions from previews, hidden
page timers, non-reversible monitor writes and profile success reported before
verification. Preserve existing harnesses and extend them at these boundaries.

## Implementation order and validation

1. Verify existing backend and establish missing capability descriptions.
2. Extend theme inventory and guarded apply/restore; verify isolated filesystem tests.
3. Replace Settings furniture with a persistent responsive rail, shared material
   surfaces and a bounded atmospheric image.
4. Build real-state Overview and integrate Appearance, Shell & Bar, motion,
   wallpapers, display/profile/security and remaining pages.
5. Run isolated service, rendering, navigation, persistence, search, lock, profile,
   display rollback and theme tests; inspect screenshots at multiple widths.
6. Reconcile source/plugin inventories and document supported/unavailable controls.

## Performance constraints

The navigation rail stays mounted. Only the selected page is loaded; a dirty draft
is retained across hide/reopen. Images are asynchronous and decoded to bounded
sizes; wallpaper galleries virtualize thumbnails. No continuous background blur.
Previews are explicitly activated and stop on hidden pages/reduced motion. No new
telemetry polling or ambient timer is introduced into the running bar.

## Implemented behavior

- The persistent four-group rail, search, compact navigation and architectural
  header use CEDAR typography, palette and chamfer primitives. Existing page IDs,
  IPC, draft guards, recent history, resize persistence and lock hiding survive.
- Overview reads Profiles, SettingsInfo, DesktopSettings, Audio, Network and
  Shield. Empty/unverified providers say so. The updater card reads only the
  recorded result of an actual managed update check, invalidated by source changes.
- Appearance previews installed palette colors without modifying Theme. Apply
  validates against the current theme digest, writes an undo snapshot and verifies
  the write. Restore preserves exact prior bytes and refuses conflicting external
  edits. A failed write retains the previous undo point.
- Shell & Bar uses the production Strata frame and contents with pointer/keyboard
  actions disabled. The local morph preview uses DropFrame and StrataGeometry;
  Heartwood and KineticLabel use production motion gates and shared tokens.
- Wallpaper selection is a draft, followed by explicit Apply through the current
  desktop provider. The GridView virtualizes thumbnail delegates, uses bounded
  source sizes and Qt's image cache, and decodes asynchronously.
- Displays retain the existing graphical arrangement, numeric controls, actual
  modes, managed configuration and independent watchdog rollback.
- Profile cards select a proposed configuration before applying. Comparisons use
  actual preferences/provider data and label unavailable operations. Settings uses
  the existing transaction with automatic restoration on failed verification;
  normal profile/Gaming clients retain their existing behavior. Custom editing
  opens the existing complete profile editor.
- Privacy embeds the existing Shield content and its authenticated operations.
  Lock privacy has a separate page. Input and applications expose related pages
  through section tabs, with old deep links intact.
- Updates reuse the managed Updater to verify a candidate in its isolated cache;
  checking never installs. Installation remains an explicit review in the updater.

## Explicit capability limits

Screensaver selection/speed, arbitrary bar module ordering, separate Strata
padding/spacing/corner/margin sliders, independent grain/edge intensity, global
blur controls, per-monitor wallpaper targeting and a general Hyprland window-rule
editor are unavailable. Relevant pages explain these limits; no decorative dummy
switches or invented preferences are supplied. System power and audio options
remain capability-driven. Native compositor gestures and real hardware changes
require desktop acceptance; offscreen rendering cannot certify them.

## Validation evidence

Validated on 2026-10-18 in isolated test environments:

- 53 Settings unit tests, including theme conflict/undo handling and malformed,
  stale, failed and successful updater status.
- 16 desktop backend tests, including display rollback; 30 theming tests.
- Profile service harness, including failed Settings profile verification followed
  by restoration of the prior preferences.
- All 26 schema pages rendered at 1180×800 and 480×800, with search, reset,
  draft-navigation and persistent-rail interactions. Narrow Shield tabs wrap.
- Settings service and floating-window lifecycle, resize, reopen and lock checks.
- Production Strata bar at multiple widths/font scales, Core interactions and
  event priority, and 15 Canopies at wide/narrow sizes with lock privacy.
- Seven Shield backend tests, five validation diagnostic tests and 18 ownership
  and interruption tests.
- Source inventory consistency, whitespace checks and public-source privacy scan.

These checks use fixture system providers. Actual monitor changes, native window
dragging and desktop service interaction still require a live-session check.
The working checkout is isolated; local activation preserves the prior checkout
and restores it if the replacement shell fails its startup check.

## Atmospheric asset

`backgrounds/strata-forest.png` was generated with the built-in imagegen tool for
this application. Prompt: a photorealistic, wide mountain landscape with layered
cedar and pine forest, mist between trees, an overcast dawn sky, deep muted
evergreen/graphite tones and restrained highlights; quiet low-contrast detail for
a Settings background; no text, logos, interface, borders, buildings, people or
watermarks. The asset is decoded at a bounded size and darkened by theme-colored
QML overlays. It is an image asset, not a screenshot used as the interface.
