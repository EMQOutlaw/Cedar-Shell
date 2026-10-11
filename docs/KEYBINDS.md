# CEDAR default keybinds

Super is the Windows/logo key. Number shortcuts use the top row: **0 means
workspace 10**. Super+K opens the searchable, scrollable reference; Escape
closes it. Search accepts actions or combinations such as `Super+Shift+V`.

| Keys | Action |
| --- | --- |
| Super+Space | Toggle application launcher |
| Super+T / W / E | Configured terminal / browser / file manager |
| Super+C / X / V | Copy / cut / paste using the application's shortcut |
| Super+Shift+V | Toggle clipboard history |
| Super+Q | Close the focused window normally |
| Super+F | Toggle fullscreen |
| Super+Alt+Space | Toggle floating / tiled |
| Super+arrows | Focus in that direction |
| Super+Shift+arrows | Move a tiled window in the layout; snap a floating window to that edge |
| Super+left / right mouse drag | Move / resize a window |
| Super+1…9 / 0 | Switch to workspace 1…9 / 10 |
| Super+Shift+1…9 / 0 | Send window to workspace 1…9 / 10 and follow it |
| Super+S | Show / hide the scratchpad |
| Super+Alt+S | Send window to scratchpad without following |
| Super+P / Print Screen | Open screenshot interface |
| Super+L | Secure session lock through CEDAR's configured locker |
| Super+Escape | Toggle session/power menu |
| Super+, | Toggle Settings / Field Station |
| Super+K | Toggle keybind reference |
| Ctrl+Super+Space / Play / Pause | Play or pause media |
| Ctrl+Super+Equal / Next | Next track |
| Ctrl+Super+Minus / Previous | Previous track |
| Ctrl+Super+Backspace / Stop | Stop playback (pause) |
| Super+Shift+M / Mute | Toggle output mute |
| Microphone mute | Toggle microphone mute |
| Volume up/down | Volume with CEDAR OSD; repeats when held |
| Brightness up/down | Brightness with CEDAR OSD; repeats when held |

Copy/cut/paste send Ctrl+C/X/V in ordinary applications. Recognized terminals
receive Ctrl+Shift+C/V; cut does nothing there. Applications with their own
nonstandard shortcuts may need an override. Lua Hyprland receives paired
key-down/key-up events to avoid stuck synthetic keys. Media and hardware
controls remain available while locked.

Directional movement uses Hyprland's native window-move dispatcher. Tiled
behavior follows the active layout. On supported Lua Hyprland, floating
movement snaps to the monitor's logical usable area, preserving size and
respecting reserved space. Both scratchpad actions target the special
workspace named `special`; sending there does not leave the regular workspace.

## Installation and updates

`data/keybinds.json` is the shared definition for the reference and both
installable formats. Run `python3 scripts/keybinds.py --write` after changing
it; `--check` verifies the generated `themes/keybinds.lua` and `.conf` files.

The installer's **Use CEDAR's keybinds** option copies the matching format to
`~/.config/cedar/hypr/keybinds.lua` (or `.conf`) and includes it through CEDAR's
journaled loader. `cedar-install --keybinds` / `--no-keybinds` select the option
from the terminal. It defaults on for plain Hyprland and Waybar setups; other
desktop environments retain their bindings unless selected.

Each combination is explicitly unbound before being bound, including old
press/release variants. Reapplying the managed loader is idempotent. The new
set removes the previous CEDAR aliases; unrelated bindings in other user files
are preserved. An untouched managed copy updates automatically. A locally
edited copy is preserved and the installer reports where the new defaults
are available. The installer records the old defaults before switching releases,
so interrupted updates retain the same migration decision.

Put personal overrides in Settings > Keybinds or
`~/.config/cedar/hypr/user.lua` (`user.conf` for hyprlang), loaded last. Explicitly
unbind the old combination before adding a manual override. The reference
reads live bindings when opened, marks missing, renamed or conflicting
combinations, and lists custom actions. Lua callbacks are opaque in Hyprland's
binding report: give overrides accurate descriptions so the reference can
identify their behavior. When Hyprland cannot be read, the panel labels the
reference as unverified rather than claiming it is live.

The shell actions use the active `cedar` Quickshell profile. Terminal, browser
and file-manager choices come from CEDAR Settings. Older hyprlang setups use
the installed release's runtime helper.

## Conflicts replaced

The old CEDAR layout used Super+C for the editor, Super+X for mouse resizing,
Super+V for clipboard history, Super+P for pinning, Super+K for Field Station,
and Super+, for window grouping. These are now copy, cut, paste, screenshot
interface, keybind reference and Settings respectively. Clipboard history moves
to Super+Shift+V; mouse resizing remains Super+right drag. Extra shell shortcuts
and alternate numbered-workspace combinations from that layout are retired.

## Rollback and validation

Restore the keybind file and `hypr/settings.json` from the installer's backup,
then reload Hyprland. The backup manifest and restore script are stored outside
the repository under the user's CEDAR state directory. To disable the managed
set, turn `keybinds` off in `hypr/settings.json` and apply Settings > Displays.

Run `python3 -m unittest discover -s tests -p test_keybinds.py`,
`python3 -m unittest discover -s tests -p test_installer.py`, and
`python3 tests/check_keybinds.py`. `tests/check_canopy.py` renders all panels.
For local changes, use `Hyprland --verify-config -c <main-config>`, then
`hyprctl reload` and `hyprctl configerrors`. Physical dragging, focus restoration,
real application clipboard behavior and native session locking also require
interactive verification; isolated tests do not certify them.
