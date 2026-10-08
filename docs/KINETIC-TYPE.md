# Kinetic Type

Text moves when its meaning changes and is an ordinary static `Text` the
rest of the time. The policy is pure (`components/core/Kinetic.js`) and the
components (`components/KineticLabel.qml`, `KineticStatus.qml`,
`KineticNumber.qml`) only animate what it allows. Durations are Theme's,
scaled by `VisualQuality.motionScale`; Reduced Motion updates statically.

## Transitions

| Style | What moves | When |
| --- | --- | --- |
| `relay` | the glyphs that stayed hold still; the changed run leaves upward and the new run arrives from below, the suffix sliding to its new place | short labels in simple scripts (printable ASCII and Latin-1 letters, at most `maximumAnimatedLength` code points); anything else resolves |
| `resolve` | the whole label leaves upward about five logical pixels while fading; the new one arrives from below | status words, a tile's value, the pill's title |
| `fade` | a crossfade | long or frequent text (the active window title) |
| `none` | a static update | Reduced Motion, `animateChanges: false`, a change inside `minimumInterval`, the first fill, an empty label |

Grapheme safety is decided by script, not guessed: a combining mark, an
emoji, right-to-left text or CJK never relays, because a relay keys on code
points and those are not single glyphs drawn left to right. The fallback is
always correct.

Semantic compression: `variants` (longest first) with `availableWidth`
shows the longest variant that fits, measured with the label's own font, and
the change between variants animates like any other. Glyphs are never
scaled.

Rate limiting: `minimumInterval` (900 ms on `KineticNumber`, 900 ms on the
pill's title, 400 ms on the window title) turns a change that follows the
previous one too closely into a static update, so a clock's minute tick, a
live meter or a title that changes with every tab never animates every time.

## Cost

At rest a `KineticLabel` is one `Text` and one idle `Loader`. A transition
creates two `Text` items (a relay: five) for its duration and destroys them
when it ends; nothing stays allocated. Layout takes the new text's width at
once; the motion is drawn in an overlay, so the surrounding row never
reflows twice.

## Where it is used

Every `StatusPill` relays its word (CONNECTING → CONNECTED, PROTECTED →
ATTENTION, FOCUSING → PAUSED). The Quick Controls tiles resolve their value
(None → Work, Off → 25 min left). The Core pill's title resolves between the
clock, a panel's name and a signal, rate-limited. The bar's active window
title crossfades.

## Tests

`node tests/core/strata_test.js components/core/StrataGeometry.js
components/core/Kinetic.js` (relay safety by script and length, the relay
plan, style choice, compression, the rate limit) and `tests/check_kinetic.py`
(a resolve and a relay run and finish, an emoji change falls back and
finishes, a rate-limited number is static, compression picks a shorter
variant at a narrower width, Reduced Motion is static, nothing stays
allocated afterwards).
