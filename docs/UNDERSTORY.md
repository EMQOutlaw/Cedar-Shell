# Understory

The rail that grows from the bar's left end: everything that lives close to
the ground, in CEDAR's own language. Click CEDAR's mark at the left of the
Strata bar, run `qs -c cedar ipc call understory toggle`, or assign a shortcut
in Settings › Bar › Understory. Escape, a click elsewhere, or the mark again
closes it. Opening it closes whatever Canopy drop is showing, and a drop or
the Core pill closes it in turn: one surface at a time, routed through
`ShellState.panel` like every other.

## What is on it

| Region | Contents and owner |
| --- | --- |
| Instrument column | Heartwood (Field Station), Signals (the Core pill), Shield, Station, Profiles, Focus, Field Notes; Keymap and Settings at the foot. Each opens the existing surface and closes the rail. |
| Header | Greeting from `$USER`, the shared 12/24-hour clock, the date, battery from UPower; Lock and Suspend act at once, Log out and Power open Power & session, which asks first. |
| CONNECT | Wi-Fi (NetworkManager radio), Bluetooth (BlueZ adapter), VPN (Proton's CLI when installed; any other tunnel is reported, not driven), Night light and the power profile (`scripts/control.py`), Quiet hours, Keep awake, Gaming Mode, Focus. Absent hardware hides its tile. |
| LEVELS | Output, Microphone, Brightness: the same PipeWire and brightness services as the bar and the pill. |
| ON THE AIR | The shared MPRIS player: art (subject to the remote artwork preference), title, artist, progress where the player supports it, transport. Hidden with no player. |
| STANCE | Desktop Profiles; a tap applies through the transaction engine, a tap on the current one leaves it. |
| POWER | The system power profile, where power-profiles-daemon answers. |
| Foot | Psalm 92:12, from `data/branding.json`. |

Nothing here has a second owner. Every tile calls the same service the
Quick Controls drop and the Core pill call, and shows that service's own
reading: a transaction that fails says so on the tile.

## Keep awake

`services/Awake.qml` holds one `systemd-inhibit --what=idle:sleep` process
for as long as the tile is on. The tile shows the process, not a flag: it
lights only once the inhibitor is running and goes dark once it has gone,
and a failed start is reported on the tile. The inhibitor is released on the
next tap, when the screen locks, and when the shell exits; nothing is
remembered across a restart. CEDAR's own idle lock honours it the way it
honours Gaming Mode's inhibitor. Without `systemd-inhibit` the tile is
disabled and says why.

## The surface

`modules/UnderstoryWindow.qml` is one transparent layer surface on the
chosen output (the main display, or the output whose mark was clicked),
anchored to the top, left and bottom beneath the bar, masked to the rail.
The rail is 388 px wide: Foundation flush to the screen edge and the bar's
foot, the Grain two pixels inside, the Living Edge along the seam, which
brightens as the rail arrives and settles. The right side leaves the bar
through the drop's concave fillet and the bottom right corner carries the
pill's long cut. It slides in from the edge over the bar's grow time and
back out over its shrink time; Reduced Motion snaps. The window unmaps once
it has gone, so a closed Understory holds no surface. The instruments
stagger in on the shared entrance clock (`Understory.ease`), the same as a
Canopy panel.

The Brightness, Controls and NetworkManager watchers run while the rail is
open and stop when it closes, as they do for the Quick Controls drop.

## IPC

`qs -c cedar ipc call understory toggle|open|hide|status`. `status` reports
`{shown, screen, reveal}`.

## Verification

`python3 tests/check_understory.py <dir>` renders the rail offscreen over
the test services, checks the routing against the Canopy, and that Keep
awake refuses without `systemd-inhibit`. The Strata bar, navigation,
Canopy and Settings harnesses cover the mark and the Settings tab.
