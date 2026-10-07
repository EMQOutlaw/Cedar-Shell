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

Steps that do not depend on each other run at the same time: the power
profile and the compositor are asked together, the inhibitor is checked
while they answer, and the transaction settles when the last provider has
replied. Nothing waits for show; on this machine the whole entry takes about
half a second, most of it the inhibitor check. Each row moves
`pending → applying → active | failed | unavailable`, and `restored` on the
way out.

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

## The preparation panel

Super+G shows a small CEDAR GAMING card a little above the centre of the
monitor that had focus, on the overlay layer, with no input (clicks pass
through to the game) and no keyboard focus. It is a live view of the
transaction, not a notification:

    ── ◈ CEDAR GAMING ──
       Preparing system…
    ━━━━━━━━━━━━●───────────          a filament lit to the verified fraction
    ◆ CEDAR effects          READY
    ◆ Notifications          READY
    ◇ Sleep inhibited        APPLYING
    ◇ Performance profile    WAITING
    ◇ Compositor effects     WAITING
    ◇ GameMode               NOT INSTALLED
           2 / 5  READY

Each row is a diamond marker that fills when its provider verifies the
change, the name in the display face, and a spaced-capital state word in
the data face (WAITING, APPLYING, READY, COULD NOT APPLY in amber, NOT
INSTALLED quiet). The card is 480 px wide and scales with the font scale.

A row is marked ready only when its provider has verified the change. A
step whose provider is missing (GameMode not installed, no performance
profile) is shown quietly with the reason; a step turned off in Settings is
omitted. When the last provider answers the heading becomes "Gaming Mode
Ready", the count becomes "Gaming Mode Active" (or "4 / 5 optimizations" in
amber when an optional step failed), a line sweeps once along the top edge,
and after 1.2 s the card fades out and the window is released; Gaming Mode
stays on. Leaving shows the same card as "Restoring system…" with each row
verified as restored, then "Gaming Mode Ended · System restored".

When a GameMode-registered game started the transaction, the heading reads
"Preparing for" and names the game from the executable GameMode reports;
without a usable name it says "Preparing for game".

The card is `modules/GamingHudCard.qml` inside `modules/GamingHud.qml`,
created by `shell.qml` only while `Gaming.hudShown` is true. It binds to
`Gaming.steps`, `hudMode`, `hudSettled` and `hudClosing`; it has no timers,
no polling and no loops. The entrance (opacity 0 → 1, scale .96 → 1, 200 ms)
and exit (→ 0, → .98, 200 ms) follow the user's Reduced Motion preference,
not the gaming quality level the card is announcing; the emblem pulses once
on entry and nothing animates after the completion sweep.

## Feedback

While Gaming Mode is on, or whenever a fullscreen or output-sized window has
focus, the Core pill steps aside on that output; an alert, the hub or a
Canopy still bring it back, and recording or microphone use keeps a single
ember dot at the top edge (see docs/CORE.md).

The Core pill is the record: a persistent "Gaming Mode" row with the
summary, announced for 3 s on entry, static afterwards. The Power page shows
every step's result from the last entry or exit and a perimeter line that
completes once on entry.

## Cost

Idle: nothing. Entry and exit: two `hyprctl` helper runs and one
power-profile change, user-triggered, plus one small overlay window that
exists for about two seconds. The GameMode watcher is a single event-driven
process and only exists when GameMode is installed; it lists the registered
games' executables when the count changes, never on a timer.
