# CEDAR keybinds (Caelestia layout)

CEDAR ships a Hyprland binding set in the layout Caelestia users know, mapped
to CEDAR's own surfaces. It is written for both Hyprland configuration
syntaxes: `themes/keybinds.lua` and `themes/keybinds.conf`. The installer
copies the matching file to `~/.config/cedar/hypr/keybinds.lua|conf`, which
is yours to edit, and CEDAR's generated Hyprland file loads it through the
same journaled loader that applies your display settings. Every entry
unbinds its own keys first, so it wins on that combination and leaves every
other binding you have alone. Removing it is one line: turn `keybinds` off
in `~/.config/cedar/hypr/settings.json` and apply from Settings › Displays,
or restore the backup the installer made.

The installer offers it as "Use CEDAR's keybinds (Caelestia layout)": on by
default for plain Hyprland and Waybar setups, off where an environment
ships its own bindings. `cedar-install --keybinds` / `--no-keybinds` decide
from the terminal.

| Keys | Action |
| --- | --- |
| Super (tap), Super+Space | CEDAR applications |
| Super+Shift+Space | Go menu |
| Super+N | Quick Controls |
| Super+K, Ctrl+Shift+Escape | Field Station |
| Super+Shift+N | Notifications |
| Ctrl+Alt+C | Clear notifications |
| Ctrl+Alt+Delete | Power |
| Super+L | Lock · Super+Alt+L session locker · Super+Shift+L lock and suspend |
| Super+Alt+P | CEDAR Settings |
| Super+G | Gaming Mode |
| Super+Shift+P | Desktop Profiles |
| Super+Shift+F | Focus |
| Super+Shift+H | Station (health) |
| Super+Tab | Workspace overview |
| Super+V, Super+Alt+V | Clipboard |
| Ctrl+Alt+V | Audio |
| Super+T / W / C / E | Terminal, browser, editor, files (as chosen in Settings) |
| Print, Super+Shift+S, Super+Shift+Alt+S | Capture |
| Ctrl+Alt+R, Super+Alt+R, Super+Shift+Alt+R | Record (capture menu) |
| Super+Shift+C | Color picker (hyprpicker) |
| Super+1…0, Super+Alt+1…0 | Workspace n, move window to n |
| Ctrl+Super+1…0, Ctrl+Super+Alt+1…0 | Workspace n+10, move window to n+10 |
| Ctrl+Super+Left/Right, Super+Page Up/Down, Super+scroll | Previous / next workspace |
| Ctrl+Super+scroll | Previous / next workspace group (±10) |
| Super+Alt+Page Up/Down, Ctrl+Super+Shift+Left/Right, Super+Alt+scroll | Move window to previous / next workspace |
| Super+S | Special workspace · Super+Alt+S or Ctrl+Super+Shift+Up moves a window in, Ctrl+Super+Shift+Down out |
| Super+M, Super+D, Super+R | Music, communication, todo special workspaces |
| Super+arrows, Super+Shift+arrows | Focus, move window |
| Super+Minus/Equal, Super+Shift+Minus/Equal, Super+Alt+arrows | Resize |
| Super+Z, Super+left drag | Move window · Super+X, Super+right drag resize |
| Ctrl+Super+Backslash | Center window |
| Super+P, Super+F, Super+Alt+F | Pin, fullscreen, maximize |
| Super+Alt+Space | Float |
| Super+Q | Close |
| Alt+Tab, Shift+Alt+Tab | Next / previous window |
| Ctrl+Alt+Tab, Ctrl+Shift+Alt+Tab | Next / previous in group |
| Super+Comma, Super+Shift+Comma, Super+U | Toggle group, lock group, leave group |
| Ctrl+Super+Space / Equal / Minus / Backspace, media keys | Play-pause, next, previous, stop |
| Super+Shift+M, mute key | Mute · mic mute key mutes the microphone |
| Volume and brightness keys | CEDAR OSD, held keys repeat |

Not carried over from Caelestia: the emoji picker, paste-latest, the
picture-in-picture and "normalize" window actions, and the shell
kill/restart shortcuts. The shell actions address the CEDAR that owns the
`cedar` Quickshell profile (`qs -c cedar`), which is the installed release or
a checkout linked at `~/.config/quickshell/cedar`, and fall back to the
release path (`qs ipc -p ~/.local/share/cedar/current/shell.qml`) only when
no profile exists. The `.conf` variant goes through `cedar ipc`, which makes
the same choice.

The binding set is CEDAR's own writing against Hyprland's documented
dispatchers; it borrows Caelestia's key layout, not its files.
