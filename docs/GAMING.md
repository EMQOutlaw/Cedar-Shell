# Gaming Mode

Super+G, the Gaming tile in Quick Controls, Settings › Power & Lock ›
Gaming Mode, or `qs -c cedar ipc call gaming toggle|activate|deactivate|status`.
The desktop quiets itself around the game and restores everything when you
leave. It is a transaction over an explicit registry, not a switch.

## The transaction

    CAPTURE  the current values of everything the registry may change
    APPLY    each enabled optimization, through its provider
    VERIFY   read each provider back; a step is active only when it reports the new state
    ACTIVE   the pill says "N / M optimizations active" and names what failed

The captured values are written to `~/.local/state/cedar/gaming.json` before
anything is applied. A shell that stops mid-game reads that file on its next
start and restores the desktop first.

## The registry

| Step | What changes | Provider | Verify | Setting |
| --- | --- | --- | --- | --- |
| Visual quality | `VisualQuality.level` → gaming: Reduced Motion for every decorative loop and entrance sweep, spectrum off, ambient telemetry off | in-process | — | always |
| Do not disturb | popups wait; critical alerts still show | `Config.saved.doNotDisturb` | read back | `gamingDnd` |
| Stay awake | no idle lock or sleep | `systemd-inhibit --what=idle:sleep` held for the session, plus CEDAR's own lock timer reading `Gaming.inhibitIdle` | the inhibitor process is running | `gamingIdle` |
| Performance power profile | profile → performance | power-profiles-daemon through `Controls` | `powerprofilesctl get` | `gamingPower` |
| Compositor effects | Hyprland blur (and optionally animations) off at runtime | `hyprctl eval 'hl.config({…})'` under Hyprland's Lua parser, `hyprctl keyword` on legacy configs; the configuration file is never touched | `hyprctl getoption` | `gamingBlur`, `gamingAnimations` |
| GameMode | observed over D-Bus (`com.feralinteractive.GameMode` ClientCount); a registered game can enter Gaming Mode and the last game leaving ends it | `scripts/gamemode_watch.py`, a GLib loop that runs only when GameMode is installed | — | `gamingAutoGameMode` |

Nothing is frozen or signalled. Only CEDAR's own behaviour and the providers
above change, each through its supported interface. A step whose provider is
missing reports "unavailable" and is not counted; a step whose provider did
not take the change reports "failed" with the provider's reason, and the pill
carries that reason.

## Leaving

Leave from the pill's action, the tile, Super+G, or by locking the session.
Restore runs in reverse: compositor values, power profile and do-not-disturb
go back to what was captured; the inhibitor stops; visual quality returns.

## Feedback

The Core pill is the overlay: a persistent "Gaming Mode" row with the
summary, announced for 3 s on entry, static afterwards. The Power page shows
every step's result and a perimeter line that completes once on entry.

## Cost

Idle: nothing. Entry and exit: two `hyprctl` helper runs and one
power-profile change, user-triggered. The GameMode watcher is a single
event-driven process and only exists when GameMode is installed.
