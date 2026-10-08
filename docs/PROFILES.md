# Desktop Profiles

One stance for the desktop at a time: Balanced, Work, Battery, Night, Gaming
or Custom. A profile is a set of typed operations applied through the
providers CEDAR already drives, verified by reading each provider back, and
restored exactly when you leave. It is a transaction, not a switch.

Open it from the Profile tile in Quick Controls, Go › Profiles, Super+Shift+P,
`cedar profiles`, or `qs -c cedar ipc call profiles open`. Activate one with
`cedar profiles work`, `qs -c cedar ipc call profiles activate work`, or
Ctrl+1…6 inside the window. The Core pill carries a persistent row for the
active profile with a Leave action; the Quick Controls tile names it.

## The engine, shared

`components/Transaction.qml` is the step engine Gaming Mode, Desktop Profiles
and Focus share: rows move `pending → applying → active | failed |
unavailable` on apply and `→ restored | failed` on restore; steps that do not
depend on each other run together and the transaction settles when the last
provider has answered. `components/TransactionHudCard.qml` is the shared
preparation card; Gaming's `GamingHudCard` and Profiles' `ProfileHudCard`
feed it their rows and words.

`services/Overrides.qml` (policy in `components/core/OverrideStack.js`) is
the ownership stack. Every value a mode changes is held under its owner
("gaming", "profile", "focus") with the value it found and the value it
applied. Releases nest in any order: the top owner's release restores what it
found; an owner underneath hands what it found to the owner above, so the
original comes back when the last one lets go. A change the user makes by
hand while a key is held marks the top holder overridden, and that holder's
release leaves the user's value alone. Config-backed keys are written
through the stack, so a change from Settings, Quick Controls or IPC is
recognised as the user's; power, night light and audio report external
changes from their snapshots.

## The operations

| Operation | Provider | Values | Verify |
| --- | --- | --- | --- |
| Power profile | power-profiles-daemon through Controls | power-saver, balanced, performance | `powerprofilesctl get` read back |
| Do not disturb | CEDAR's own popups (`doNotDisturb`) | on, off | setting read back |
| Lock after | CEDAR's idle lock (`idleLockSeconds`) | never, 5, 10, 30 min | setting read back |
| Night light | hyprsunset or Omarchy through Controls (toggle) | on, off | snapshot read back |
| Ambient effects | `ambientIntensity` | off, low, normal, high | setting read back |
| Performance mode | `performanceMode` → VisualQuality | auto, on, off | setting read back |
| Whispers | `forestWhispers` | on, off | setting read back |
| Audio scene | a saved Audio Scene through audio_instruments.py | scene name | default output equals the scene's |

A provider that is missing reports "unavailable" and is not counted; one
that did not take the change reports "failed" with its reason, and the pill
carries it. Nothing is frozen or signalled. Bar presentation and widget
cadence are not managed: the bar style is a layout choice, and telemetry
cadence already follows what is visible.

## The profiles

| Profile | Accent | Sets |
| --- | --- | --- |
| Balanced | cedar green | power balanced, DND off, performance auto, whispers on |
| Work | teal | DND on, performance on, whispers off, power balanced |
| Battery | moss (green warmed with amber) | power saver, lock after 5 min, performance on, ambience off, whispers off |
| Night | blue-green | night light on, DND on, ambience low, whispers off |
| Gaming | bright green | Gaming Mode's own transaction (docs/GAMING.md) |
| Custom | chosen by the user | whatever the user sets, per operation, with "Leave" for the rest |

Profiles are exclusive. Activating one while another is on restores the
first and then applies the second; Gaming counts, so choosing Work while a
game is on leaves Gaming Mode first. Super+G, the Gaming tile and GameMode
detection are unchanged, and the Profiles surface reflects them.

Custom lives in `~/.config/cedar/profiles.json`, watched and editable. The
runtime state (`~/.local/state/cedar/profiles.json`: the active profile and
each held key with the value it found) exists only while a profile is on; a
shell that stops mid-profile reads it on its next start and puts the plain
settings back at once and the power profile when its snapshot arrives.

## The preparation panel

Activating shows the shared card a little above the centre of the focused
monitor: "CEDAR · WORK", "Preparing work…", one row per operation with a
diamond that fills when its provider verifies, a filament lit to the
verified fraction, and the count. When the last provider answers the heading
becomes "Work ready", the count "WORK ACTIVE" (or "3 / 4 changes" in amber
when one failed), a line sweeps once along the top edge, and after 1.2 s the
card fades and the window is released. Leaving shows "Restoring the
desktop…" and then "Work ended · Desktop restored". The card takes no input
and no keyboard focus; it has no timers of its own.

## The window

A station like Shield: the active profile as a frame tinted with its accent
and the rows of the last transaction (including "Kept your own change" where
a manual change was respected), the six profiles as chamfered tiles with
their accent on the top line and a lit bottom line on the current one, and
the Custom editor with a "Leave / value" chip row per operation and an
accent picker. Everything enters on one shared clock; nothing loops. Tiles
and chips are keyboard targets with a visible focus ring; Escape or Ctrl+W
closes.

## Cost

Idle: nothing. Activating reads the power and audio snapshots once when the
profile needs them, then asks each provider once; the panel exists for about
two seconds. The window opens with one power snapshot and one audio
snapshot (for the scene names) and reads nothing while open.

## Tests

`node tests/core/overrides_test.js components/core/OverrideStack.js` (the
ownership stack: nesting in both orders, manual changes, re-holds),
`tests/check_profiles.py` (apply, verify, counts, the pill row, a manual
change kept on restore, nesting with Gaming Mode in both directions,
exclusivity, Custom persistence, the window at 1100 px), and the Gaming
checks, which now run on the shared engine.
