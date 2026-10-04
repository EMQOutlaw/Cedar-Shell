# CEDAR — development brief and AI handoff

Updated October 3, 2026. Read the actual files before relying on any implementation detail in this document. This is a development contract and roadmap, not permission to replace the existing shell or a claim that every planned feature exists.

## Mission

Evolve **the existing CEDAR implementation** into a complete Quickshell desktop experience on Hyprland, integrated with Omarchy. Preserve its architecture, settings, services, vocabulary, behavior, and identity.

> A quiet, living forest interface with the precision of a personal command station.

Imagine a personal field station in a dark Appalachian forest: bioluminescent fungi, faint organic filaments, quiet observation, real instrumentation. The shell feels awake through purposeful responses and restrained ambient motion. It must remain useful when all decoration and motion are disabled.

Omarchy informs opinionated workflow, keyboard operation, defaults and compositor integration. Ryoku informs layout flexibility and customization. Caelestia informs cohesive Quickshell integration and desktop controls. These are references for ideas, never replacement identities. Preserve CEDAR instead of making a clone of any of them, GNOME, KDE, macOS or Windows.

## Source of truth and working rules

Canonical configuration: `$XDG_CONFIG_HOME/quickshell/cedar/` (default `~/.config/quickshell/cedar/`), registered to the local source checkout. Activation is a separate guarded step. User preferences: `~/.config/cedar/settings.json`, respecting XDG_CONFIG_HOME. This is not Omacale or Omarchy's own shell.

Before changing a feature:

1. Inspect the component, its shared service, IPC entry points, configuration, and callers.
2. Read applicable local instructions and the Omarchy skill. Do not edit package-owned `/usr/share/omarchy/` files.
3. Keep working functionality, settings, and IPC compatibility. Extend existing services instead of polling the same subsystem from another service.
4. Back up user-owned files; distinguish temporary test configurations from the live shell.
5. Implement complete controls with real behavior, availability checks, progress and useful failure messages. No decorative switches.
6. Test state transitions, error paths, persistence and rollback. Check actual shell logs after loading changes.
7. Report precisely what was tested, what remains dependent on hardware/user interaction, and what is still planned.

The installed Hyprland uses **Lua configuration**. Do not generate old hyprlang `.conf` snippets from memory. Check the installed version and current official documentation before extending compositor integration.

## Visual identity

Use `Theme.qml` tokens. Do not hardcode palettes into components.

| Role | Default |
|---|---|
| background | `#080F0D` |
| surface | `#101E19` |
| elevated | `#192D25` |
| border | `#315C4D` |
| green | `#9DFFB0` |
| brightGreen | `#4DFF9A` |
| teal | `#3FE0C5` |
| amber | `#F2C879` |
| ember | `#E58B73` |
| text | `#E3F2E9` |
| muted | `#A0B9AD` |

Rajdhani is the interface/display face; JetBrainsMono Nerd Font carries data and compact icons. Keep readable contrast, clear hierarchy, thin separators, generous spacing and restrained transparency. Use amber for warnings and elevated readings, not arbitrary decoration.

The original angular/chamfered bar can retain its identity. Panels, Field Station, Settings, popovers and controls use calmer rounded geometry. Bar buttons are minimal and uniform. Never put an ornate HUD frame around every button.

Avoid cinematic sci-fi HUD styling, Iron Man blue, meaningless graphs, fake telemetry, constant scanning, gratuitous particles, excessive glow, and visual clutter. “Alive” means responsive and quietly breathing, not busy.

## Existing architecture to preserve

Linux / Wayland / PipeWire / systemd → Hyprland → Quickshell → CEDAR.

- `shell.qml`: shell composition, existing IPC targets, per-monitor surfaces, notification server and session lock.
- `Config.qml`: defaults plus saved JsonAdapter preferences, atomic writes, debounced multi-value saves, clock/date formatting.
- `ShellState.qml`: focused-output panel routing, explicit OSD state and interaction hold, lock/suspend coordination.
- `Theme.qml`: palette, typography, geometry and motion tokens.
- `services/Audio.qml`: native PipeWire outputs, input, volume and mute. Reuse for all audio UI.
- `services/Network.qml`: shared NetworkManager state and command lifecycle through `scripts/connections.py`.
- `services/BluetoothService.qml`: native BlueZ device state, bounded discovery, local pairing/action helper.
- `services/Controls.qml`: available power profiles and night light.
- `services/DesktopSettings.qml`: compositor settings request lifecycle through `scripts/desktop.py`.
- `services/SystemStats.qml`, `Weather.qml`, `Brightness.qml`: real system/weather readings and backlight control.
- `services/NoticeStore.qml`: bounded notification history and live objects; DND filtering preserves critical alerts.
- `services/Go.qml` and `components/MenuModel.js`: Omarchy menu providers plus applications, search, prompts, and shell compatibility shim.

Reusable station components include `StationButton`, `StationPanel`, `StationField`, `StationSlider`, `StationToggle`, `StationCombo`, `StationCore`, `CedarAtmosphere`, and `ActivityTrace`. Prefer these over another control family.

## Current implementation and boundaries

### Already present before this update

Six bar layouts; minimal bar buttons; Field Station redesign with real telemetry and restrained motion; shared 12/24-hour time and date preferences; Settings redesign; explicit, persistent volume OSD interaction; launcher, notification history, wallpaper/theme selection, power menu, lock and shell lifecycle integration.

### Added in this update

- Fixed real PAM authentication initialization and first-submission handling. Added a local test that does not lock the session. The user confirmed successful authentication.
- Control Center: Wi-Fi/network management, Bluetooth, output/input devices, volume and microphone, brightness, media, night light, DND and supported power profiles.
- Connections: radio, nearby APs, saved networks, saved VPN activation/deactivation, disconnect/forget, hotspot setup. Enterprise and legacy network setup use the existing terminal network editor.
- Bluetooth: bounded discovery, device listing, connect/disconnect, pairing with code/confirmation, trust and forget; battery where BlueZ exposes it.
- Displays: visual arrangement, mode/refresh, scale, rotation, independent timed rollback and explicit Keep.
- Input: keyboard layouts/variant/repeat/NumLock, pointer sensitivity/acceleration/natural scroll, touchpad tap/scroll/typing behavior.
- Keybindings: current active bindings, categories/search, shortcut recording, conflicts, custom commands, editing ordinary exec bindings, restoring CEDAR overrides. Complex Lua callback and special-flag bindings remain read-only.
- Separate generated compositor configuration, last-loaded user overrides, backups and reload/config-error rollback.
- Automated backend and QML tests, plus this handoff.

### Settings remaster

The Settings interface now has 15 lazily loaded category pages, stable navigation, a narrow category list, global descriptor-based search, deep links and transient row highlighting. The page components share SettingRow/SettingControl/SettingsFields and the Station controls. `SettingsSchema.js` is the shared preference/control/search schema; supported input controls derive from the active snapshot and detected touchpad hardware.

Added real desktop inventory, installed theme and wallpaper previews, appearance typography/geometry/motion preferences, bar module visibility, native PipeWire application volume, notification preferences, service health/logs/diagnostics, scoped resets and guarded shortcut replacement. Settings preserves external changes and unapplied input/display drafts. Optional VRR policy is included in the existing display rollback transaction. Input changes verify effective values and roll back on conflicting user overrides. System power profiles remain distinct from the unimplemented CEDAR desktop profiles. See the README’s Settings remaster section for exact coverage and limitations.

### CEDAR Core

A single host on the main display integrates into all six bars. CoreHost keys its native window to the assigned screen so reload/display changes do not migrate a reused visible window; two live reloads passed after this stabilization. Shared native services provide audio, media, critical notification actions, Bluetooth, network/VPN, battery/power and workspace events. Core adds real recorder/keyboard monitoring, identifiable PipeWire privacy activity, persisted timers, actionable saved screenshots/local file drops, on-demand repository update checks and leased provider publications. Priorities, interaction hold, bounded history, stable OSD controls and Reduced Motion are central invariants. See `docs/CORE.md` for source limitations, APIs and verification. General download detection, external integrations and update progress are not implemented merely because their publication API exists.

### Still roadmap work — do not describe as complete

Full universal-search providers; draggable window overview; general reorderable/per-monitor bar module editor; complete appearance and application palette propagation; advanced display HDR/mirroring controls; arbitrary Lua callback shortcut editing; richer notification grouping/per-app policy; additional OSD sources; full profiles; expanded system health checks; full widget/plugin contracts and Home Assistant integration. Implement these in coherent increments without replacing the foundation.

## Top bar direction

Preserve CEDAR, Floating, Full Width, Islands, Center and Split. Internal `minimal` denotes Full Width. Keep gaps between floating/island groups transparent to pointer input through the existing region masks.

Build configurable modules around identity/Go, workspaces, active app, window state, clock/date, media/context, tray, privacy indicators, VPN, network, Bluetooth, volume/mic, brightness, battery, power profile and notifications. Support ordering, enable/disable, responsive hiding, and per-monitor placement. A module whose hardware is absent should disappear or explain availability appropriately.

The clock must use the shared 12/24-hour/date helpers. Changing values must update existing items without recreating bar windows. Clicking volume should open the existing persistent slider; repeated key presses, wheel changes and dragging must not blink the window.

## Go universal command interface

Extend the existing Go architecture. Preserve Omarchy menu routes and script input/select compatibility. Applications and system menu actions already work.

Add providers for open windows, workspaces, settings, files, clipboard history, calculator, terminal commands, web searches, recent items and CEDAR actions. Suggested prefixes: `>` terminal, `@` window, `#` workspace, `:` action, `/` file, `?` web, `=` calculator. Normal search should merge relevant results intelligently.

Keep navigation fast and keyboard-first. Providers must be bounded, cancellable and resilient to stale results. Never evaluate arbitrary calculator text as code. Commands execute only after an explicit user activation. Clipboard contents and search text should not enter logs.

## Control Center and connections

The current control panel is a separate surface sharing services with Settings and Field Station. Preserve that boundary. Quick controls should stay compact; connection details expand into purposeful lists and forms.

Wi-Fi should show real strength/security/connection state and expose connect, disconnect, saved connections, forget and hotspots. VPN controls act on NetworkManager profiles. Extend enterprise/hidden-network credential handling only when it can support the full authentication flow. Do not claim connecting succeeded merely because an asynchronous request was accepted.

Bluetooth should include discovery, pairing confirmation, trust, disconnect/remove and battery where available. Stop scans after a bounded interval or when leaving the surface. Add audio-profile selection through the actual sound service when supported. Do not auto-accept pairing confirmations.

Credentials go over local stdin/DBus, not command arguments, shell strings, screenshots, logs, or CEDAR settings. Keep all secrets out of diagnostic reports. An advanced editor may remain available, but normal controls should work inside CEDAR.

## Settings as a first-class application

Keep the Field Station family: quiet surfaces, clear groups, readable labels and a stable sidebar. CEDAR preferences save automatically; system settings with disruptive effects use explicit Apply/Keep. Make that difference visible.

Appearance should eventually expose wallpaper/palette, fonts/icons/cursor, window look, transparency, blur, shadows, radius, animation/reduced motion and GTK/Qt integration. Interpret alternate palettes through CEDAR's identity instead of replacing it.

Displays should grow from the existing arrangement/mode/scale/rotation editor to supported VRR/HDR, mirroring, preferred output and per-monitor wallpaper. Preserve a reachable output. Detect hotplug while editing. Always trial potentially unusable changes with a rollback process that outlives the shell.

Input should grow to full supported keyboard, pointer, touchpad and gesture controls. Read current compositor values; do not substitute defaults when a property is unavailable.

Keybindings must show actual active bindings and detect conflicts immediately and again at commit. Editing complex Lua callbacks requires a faithful architecture that preserves callback behavior, submaps and flags; never serialize them as guessed shell commands. Keep textual advanced access.

## Configuration ownership and transactions

CEDAR owns `~/.config/cedar/hypr/generated.lua` and its structured settings source. `user.lua` belongs to the user and loads afterward. The first explicit system Apply appends a guarded loader to the user's Hyprland Lua file. Existing unrelated configuration stays intact.

Back up before mutation. Generate only settings the user edited. Validate numeric values, enumerations and output capabilities. Serialize strings as data, never concatenate untrusted Lua. Reload with `hyprctl reload`, inspect `hyprctl configerrors`, and restore on failure.

Display trials use unique tokens and a separate watchdog. Stale confirmation cannot keep a newer transaction, and a stale watchdog cannot revert one. Preserve concurrent unrelated user edits while removing a newly inserted loader during rollback.

Never reset user settings or Omarchy files just to make implementation easier. Updates must not erase customization.

## Workspace overview

Create a distinct overview for monitors, workspaces and windows using real compositor state. Selecting a window focuses it; selecting a workspace switches it. Add window dragging between workspaces where technically supported. Support dynamic workspaces and special-workspace semantics correctly.

Start with useful window cards if live thumbnails are unavailable. Never substitute fake preview content. Keep animation restrained and fully respect Reduced Motion.

## Notification Center

Preserve history, live actions, dismiss, clear, critical urgency and DND. Add app grouping, per-app preferences and clearer action handling without overloading Control Center.

Bound histories, remove destroyed notification references, and display action availability accurately. Muting popups must not discard history. Critical notifications remain visible when DND is on. Distinguish dismissing a current notification from deleting its historical record.

## OSD invariants

Explicit visibility state is authoritative. **Never bind visibility to `Timer.running`.** A timeout controls when state changes; restarting it must not unmap/remap a surface.

Interaction holds the OSD open and restarts the idle timeout when interaction ends. Volume changes update the same slider in place. Preserve output routing during an open interaction.

Extend the common geometry/type/motion to brightness, mic mute, keyboard brightness, Caps/Num Lock, power profile, touchpad and airplane mode when these events are available. Avoid duplicate OSDs from multiple services.

## Field Station

Keep its name and personality. It remains the personal dashboard: clock/date, CPU/memory/disk/temperature, uptime, network, weather, media, greetings and quick actions. Shared time/date settings must update it immediately.

StationCore, CedarAtmosphere and ActivityTrace have specific roles. Activity traces contain real bounded readings, never random data. Empty/unavailable/stale states must be explicit. Ambient motion may respond gently to real activity without turning metrics into animation props.

## Profiles

Design Balanced, Work, Gaming, Battery, Night and Custom around supported capabilities. A profile may coordinate power, DND, motion, wallpaper, monitor refresh/VRR, apps, audio and workspace behavior.

Gaming can request performance, VRR/max refresh, DND, reduced motion and GameMode only where supported. Report skipped unsupported options. Make applied effects visible and reversible; do not silently overwrite user values. Configuration presets and system power profiles are distinct concepts.

## Multi-monitor behavior

Use monitor geometry, scale, focus, active workspace and pointer context deliberately. ShellState routes panels to the selected main display, falling back to the focused output. Preserve that and avoid duplicate exclusive keyboard grabs.

Bars/wallpapers/workspace content must be per-monitor capable. Handle hotplug, rotated outputs, mixed scaling and changing focused outputs. Session lock must cover every required output and remain secure across hotplug.

## Wallpaper and theme engine

Preserve existing wallpaper selection and Omarchy theme handoff. Plan coherent color extraction from wallpaper into CEDAR, Hyprland, GTK, Qt, terminal and shell surfaces, with generated/user-owned boundaries for each target.

Presets may include CEDAR, Nord, Catppuccin, Gruvbox, Tokyo Night, Rose Pine, Everforest, Monochrome and Custom. CEDAR remains the canonical default. Check readability and contrast for every generated palette; extracted colors are suggestions, not permission to create unreadable controls.

## System health and diagnostics

Add a health center for Hyprland, Quickshell, PipeWire, WirePlumber, NetworkManager, BlueZ, desktop portals, GPU acceleration, notifications and CEDAR services. Report Healthy, Warning, Failed or Unavailable using actual evidence.

Offer targeted restart, logs and diagnostic copy where appropriate. Restart actions should identify the service and consequence. Diagnostics should include OS/kernel/GPU/driver, compositor/shell versions, portals/audio, monitors and relevant recent errors while excluding secrets and unnecessarily private environment values.

Expose useful underlying errors rather than only “Something went wrong.” Absence of optional hardware is not a failure.

## Lock and session security

The October 3 failure was caused by a private PAM service including `system-auth` without the included policy in its configuration directory. Journal logs confirmed PAM could not open the file. The first submission could also start a conversation and discard the supplied response.

The fix selects Omarchy's installed `/etc/pam.d/omarchy-lock-password` policy from `/etc/pam.d` and queues a response until requested. `LockAuth.qml` handles retry, timeout, error preservation and secret clearing. Only `PamResult.Success` releases the actual `WlSessionLock`. Watch-file reload remains disabled while locked. Do not kill or replace the shell during a secure lock.

The user confirmed the non-locking local authentication test succeeded. Full session-lock release, suspend/resume and monitor hotplug are separate integration tests. Never ask the user to send a password. Do not automatically lock, reboot or log out to test development changes.

The session menu should support lock/logout/suspend/hibernate/reboot/shutdown where logind supports them. Unsupported actions must be disabled or explained. Suspend must wait until the lock is secure. Preserve deliberate confirmation for destructive session actions.

For portability beyond Omarchy, detect and use a suitable installed PAM policy explicitly. Do not assume this machine's policy exists everywhere, invent an insecure fallback, or silently weaken system authentication.

## Extension architecture

Design optional modules with stable contracts for data subscriptions, actions, settings and widgets. Keep the core useful without extensions. Potential integrations: weather, Home Assistant, Docker, GitHub, Tailscale/VPN, Steam, KDE Connect and custom system monitors.

Home Assistant belongs in an optional extension. Devices such as lights, thermostats, locks, garages and sensors may surface in Control Center or Field Station. Protect credentials, distinguish state changes from commands, and make consequences of physical-device actions clear.

The existing Omarchy plugin-menu bridge is not yet a general CEDAR widget framework. Do not confuse those APIs or claim extension compatibility without implementing it.

## Motion and performance

Stop ambient animation when its surface is inactive. Respect Reduced Motion across all components. No readability or control operation may require animation. Never flash text on updates.

Prefer event-driven native services, bounded polling where no signal path exists, shared models, lazy surfaces, bounded history, and conditional animation. Avoid permanent expensive Canvas repaints, uncontrolled timers/processes, unbounded particles and repeated window recreation.

Watch idle CPU/memory and hotplug behavior. Repeated opens/closes, reconnects, errors and updates must not leak subprocesses or DBus agents. Password helpers and pairing conversations must expire/cancel cleanly.

## Delivery and validation checklist

- Keep changes cohesive and reviewable; explain the concrete behavior and failure modes.
- Run Python regression tests and isolated QML harnesses with a temporary config/runtime directory.
- Use fixtures only in tests. Never ship sample telemetry or network rows into production.
- Check all visible states: populated, empty, unsupported, busy, failure and successful completion.
- Check keyboard focus, Escape behavior, scroll reachability, small screens and multiple outputs.
- Validate compositor changes only through guarded transactions. Do not apply guessed display layouts to the user's running desktop.
- Inspect the actual shell log after loading the tested components. Differentiate environmental test warnings from application errors.
- Keep this brief and README honest about current capabilities and remaining work.

Official references: [Quickshell PAM](https://quickshell.org/docs/v0.2.0/types/Quickshell.Services.Pam/PamContext/), [NetworkManager DBus API](https://networkmanager.dev/docs/api/latest/gdbus-org.freedesktop.NetworkManager.html), [Hyprland bindings](https://wiki.hypr.land/Configuring/Basics/Binds/), [Hyprland monitors](https://wiki.hypr.land/Configuring/Basics/Monitors/). Check the versions installed locally before implementing from documentation.


### Main-display addition

`Config.saved.mainDisplay` stores an optional preferred output. Panels, notifications and new OSD interactions follow it when available; locks cover all outputs. Apply system default preserves geometry/workspaces and uses generated configuration with user overrides. Real hardware application must be verified in the desktop session.
