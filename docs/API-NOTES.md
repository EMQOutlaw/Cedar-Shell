# API and validation notes

## Sources

The installed Quickshell **0.3.1-1** package is the authoritative API source for this build. Its generated `*.qmltypes` files under `/usr/lib/qt6/qml/Quickshell/` and `qmldir` exports were inspected before implementation. This avoids treating old online examples as evidence for current APIs. The [Quickshell documentation](https://quickshell.org/docs/v0.2.1/) was consulted as a reference; versioned individual type URLs were not reliably available during this session.

Validated types include `PanelWindow`, `Variants`, `Scope`, `LazyLoader`, `IpcHandler`, `Process`, `StdioCollector`, `DesktopEntries`, `QsMenuAnchor`, `WlrLayershell`, `WlSessionLock`, `WlSessionLockSurface`, `IdleMonitor`, `PamContext`, `PwObjectTracker`, `SystemTray`, `UPower`, `Mpris`, and `NotificationServer`.

The correct `Variants` model for a notification ObjectModel is `server.trackedNotifications.values`. A local singleton named `State` collided with QtQuick's built-in `State`; it was renamed `ShellState`. Both issues were caught and corrected by runtime testing. Direct `SystemTrayItem.activate()`, `secondaryActivate()`, menu anchoring and scroll use the installed declarations. Workspaces activate through `HyprlandWorkspace.activate()`.

System telemetry and network details use explicitly bounded Python helpers through Quickshell `Process`; no invented Quickshell CPU, weather, brightness or cellular properties are used. Weather follows the [Open-Meteo forecast API](https://open-meteo.com/en/docs). Kitty's angled tab strip uses its documented [powerline tab configuration](https://sw.kovidgoyal.net/kitty/conf/).

Hyprland **0.56.2-2** uses Lua. The [current window-rule documentation](https://wiki.hypr.land/Configuring/Basics/Window-Rules/) was checked, and `/usr/share/hypr/stubs/hl.meta.lua` plus the installed Omarchy helpers were used for the exact `hl.config`, `hl.layer_rule`, `hl.unbind`, and `o.bind` forms. The generated Lua file passed `Hyprland --verify-config` when appended to the current user configuration in a temporary file. The legacy `.conf` is explicitly a 0.54 reference and is not installed into the current Lua configuration.

## Evidence

- Stage 1 ran on the live compositor for five seconds and loaded successfully.
- The complete preview loaded successfully; IPC opened HUD, launcher, history, power and theme panels and showed a volume OSD. No scene warnings, binding loops or QML errors were observed in the passing smoke test.
- A HUD screenshot was visually inspected for layout and readability, then deleted because the adjacent monitor contained unrelated desktop content.
- Private-D-Bus tests sent notifications, dismissed them, expired them, and verified history survived closure without retaining destroyed notification objects.
- Sixteen regression tests cover worst-case AA text contrast, sole-source QML colors, all 16 ANSI colors, missing/bad sensors, Wi-Fi vs cellular labeling, brightness failure, invalid coordinates, and enter/leave/repeated/locked/failed theme handoffs.
- Neovim loaded the generated colorscheme headlessly with `-u NONE -i NONE`; Lua syntax validation passed.
- Actual `hyprctl -j binds` output confirmed the documented conflicts. The captured full bindings were removed after extracting only the relevant results.

## Go menu and settings

`FileView` with a child `JsonAdapter` (the adapter is `FileView`'s default property in the installed 0.3.1 declarations) persists CEDAR's settings; `adapterUpdated` fires only for QML-side changes, so `writeAdapter()` on that signal does not echo file reloads. `Process.environment` exists but the Go menu instead exports `PATH` inside the `bash -lc` script it hands to `systemd-run --user --scope`, so Omarchy helpers find `scripts/shim/omarchy-shell` and the action outlives the shell. `DesktopEntry.command` is a string list and `Quickshell.iconPath(name, true)` returns an empty string for unknown icons; app rows fall back to a generic executable icon. `IpcHandler` string parameters carry the select/input JSON payloads verbatim.

Omarchy stages the selected theme's `hyprland.lua` by copying it into `~/.local/state/omarchy/current/theme/`, so editing `themes/hyprland.lua` needs `omarchy theme set cedar` (or copying the file) before `hyprctl reload` sees new bindings. Verified live on the selected theme: root, Apps, Setup › Plugins and Installed Plugins menus; search with drill-down divider; `omarchy-menu-select` and `omarchy-menu-input` round trips through the stand-in returned the chosen row (with subtext) and typed text; the stock `omarchy-menu-plugin enable|disable` prompts opened in CEDAR; `settings set`/`get` wrote and reloaded `~/.config/cedar/settings.json`, and an external edit was picked up by the watcher. Hyprland reported no config errors after the new bindings loaded.

## Remaining live checks

Omarchy’s selected background symlink is polled by the native Quickshell wallpaper surface, so choosing any of the indexed images updates the live desktop. The repaired handoff was tested live in both directions: CEDAR → Tokyo Night restored the normal Omarchy shell; Tokyo Night → CEDAR started exactly one CEDAR shell. The graphical selector cache contains CEDAR’s preview. Real PAM authentication and secure unlock, multi-monitor hotplug while locked, critical notification action delivery, actual backlight changes, cellular modem behavior, and configured weather network delivery require hardware/session testing. Preview mode intentionally cannot lock or acquire the live notification bus name. Existing Omarchy lid-close and external sleep helpers require separate integration before relying on external suspend paths.

Known environmental warning: Qt's host portal reported that a connection already had an app ID during the live preview. It did not prevent loading or IPC. The private-bus offscreen test also prints an expected Wayland-display/offscreen warning.


## October 3 desktop update

The private PAM include problem was confirmed in the previous boot journal. CEDAR now selects the installed Omarchy password policy from `/etc/pam.d`, queues the first response, preserves infrastructure errors, and offers a non-locking local test. The user confirmed successful real authentication. Session-lock release, suspend/resume and hotplug still need separate integration testing.

Control Center and the additional Settings pages have isolated QML rendering coverage. The compositor backend validates Lua data, uses explicit Apply, keeps user overrides separate, and provides an independent display watchdog. No compositor settings were applied during development. Physical Wi-Fi/VPN/hotspot/Bluetooth changes and input/display Apply remain hardware/session validation tasks. Historical component development included live reloads; CEDAR activation is tracked separately in VERIFICATION.md. See `DEVELOPMENT-BRIEF.md` for the complete feature boundaries.
