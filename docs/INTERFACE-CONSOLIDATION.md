# Interface consolidation

The Core's main button always toggles Quick Controls. Its network indicator opens Connections inside the same Canopy. Audio, Bluetooth, Power/session, system telemetry, weather, calendar, clipboard, notifications and Trails use that shared surface. Signals retain their separate activity-stack destination.

The right edge keeps tray items, battery information and notification history. Its old Control Center, Settings, volume and raw network-label buttons are removed. Field Station's redundant Control Center button is removed too. Secondary monitors and configurations with activity Core disabled retain a centered clock/control entry, including Split layout. Calendar remains available through Canopy → Time.

Quick Controls is now a reusable content component, without an embedded second header, tab strip, Settings button or scroll container. Output volume is immediately visible. Power/session actions share one implementation with the legacy power overlay. Existing command/IPC entry points remain; `ShellState.open/toggle("control")` and power calls route to Canopy when enabled. If Canopy is explicitly disabled, existing overlays reuse the same controls. Saved preferences (including legacy hidden-module keys) are retained; removed modules no longer appear as ineffective toggles in Settings.

## Network selection

The previous service selected the first active saved profile, allowing `lo` to become the bar label. The existing NetworkManager snapshot now selects the active primary underlay, then default/default-IPv6 routes, then eligible physical connections. Loopback is excluded. VPN/WireGuard state is separate. A local virtual bridge without a default route is excluded; unknown routed link types remain unknown rather than being labeled Wi-Fi. Connected, connecting, disconnected and unavailable states are separate from NetworkManager's internet-connectivity result. No new poller is added.

The Core uses an icon, with a simple text fallback if the Nerd Font is missing. Connection names remain in Connections and its tooltip, not on the normal bar. The tooltip says when internet access has not been checked.

## Verification

- 125 project Python tests pass, including 11 network-selection regressions.
- Five staging-updater tests cover locked-session refusal, conflicting edits, edits during validation, backups/repeated application and rollback.
- Real Qt mouse events test Core toggling, changing activities, network navigation, media click isolation, keyboard focus/Enter/Escape and lock guards; also tested at 150% display scale.
- All six bar styles render at 640/960/1280 logical pixels with Core on/off; narrow cases include enlarged text. Assertions check center reservation and centered fallback geometry.
- Eleven Canopy destinations render at 480/960 pixels; pinning and locked-session privacy checks pass.
- Existing Settings, scoped reset, persistence, rapid-volume/drag-hold, animation/reduced-motion, lock-auth state-machine and two-virtual-monitor host/reload checks pass.
- 132 QML files parse. Activity and Forest policy JavaScript tests pass.

Native Wayland input masks, compositor focus-grab ordering, physical displays, live NetworkManager/PipeWire and real authentication remain unverified in the restricted test session. Offscreen tests do not establish physical frame rate or authenticate a user. The focus grab explicitly includes the originating bar/Core windows so an outside-click dismissal does not race the Core toggle.

## Applying this staged update

Run from an unlocked desktop terminal:

```sh
python3 ~/Work/cedar-interface-update/scripts/apply_interface_update.py
```

The updater resolves the installed source through the XDG Quickshell `cedar` registration. It verifies compositor and shell lock state, refuses conflicting source edits, reruns UI checks, creates a private backup under `$XDG_STATE_HOME/cedar/update-backups/interface-*` (default `~/.local/state/cedar/update-backups/`), and stops only the named CEDAR instance through its guarded IPC before replacing files and restarting it. Failure restores changed files from the backup. Settings, monitor configuration and unrelated source files are untouched.

The staging baseline, deployment helper and its five staging-only tests are not copied into the installed source. The backup's `update.json` lists original files and whether each existed; keep it for recovery. Repeating the staging command is safe. Do not manually copy files over a running locked shell.
