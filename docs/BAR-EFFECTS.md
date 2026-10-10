# Bar effects

The bar's animation identity: instruments that move when the desktop
changes and are still while nothing does. Settings › Appearance › Bar
effects turns each one on or off, sets the effect intensity and the motion
preset (Calm, Balanced, Expressive, Off); Reduced Motion and the Off preset
keep decorative motion static. `VisualQuality.effects` and
`VisualQuality.effectIntensity` are the single gate every instrument reads,
so Performance mode and Gaming Mode suspend decorative effects;
Expressive lengthens motion by a third and brightens it. Functional Core and
Canopy transitions use `VisualQuality.functionalMotion`: Efficient and Gaming
shorten them, while Reduced Motion and Off disable them.

The continuous cedar layout is described in [Strata bar](STRATA-BAR.md).
Other layouts retain their own arrangements and effects.

Where each one lives in the running bar, so nothing here is a scaffold:

| Instrument | Component | Instantiated in |
| --- | --- | --- |
| Awakening | `modules/Bar.qml` (cedar grain lift; legacy sweep), `CedarRootlines.grow()`, `CedarHeartwood.awaken()` | `modules/Bar.qml` per output; `components/core/CoreSurface.qml` |
| Heartwood | `components/CedarHeartwood.qml` | `components/core/CoreSurface.qml`, up to 24 px at rest, 44 px in the hub |
| Rootlines | `components/CedarRootlines.qml` | `modules/Bar.qml`, between the frame and the controls, per output |
| Strata frame | `components/StrataBarFrame.qml`, `components/DropFrame.qml` | cedar bar; `modules/CanopyWindow.qml`, every drop |
| Workspace glide | `modules/StrataBarContents.qml`, `modules/BarContents.qml` | the workspace row |
| Kinetic Type | `components/KineticLabel.qml`, `KineticStatus.qml`, `KineticNumber.qml` | `components/StatusPill.qml` (every status word), `modules/QuickControls.qml` (tile values), `components/core/CoreSurface.qml` (the pill's title), `components/CedarWhispers.qml` |
| Whispers | `components/CedarWhispers.qml` | `modules/StrataBarContents.qml` and `modules/BarContents.qml`, the text region |
| Canopy Pulse | `components/CanopyPulse.qml` over `services/Pulse.qml` | `modules/StrataBarContents.qml` and `modules/BarContents.qml`, before the tray; `components/AudioSpectrum.qml` shares the feed |

## The awakening

When the shell starts (not in test mode), cedar briefly lifts the light on
its retained grain edge, then rests. Other layouts grow their Rootlines
outward and sweep a band of light across the top once. Controls are visible
and usable immediately in every layout. Heartwood arrives spread and turned,
its three rings settling into place while the glow fades.
Awakening starts 220 ms after the compositor has mapped the
bar's window (`PanelWindow.backingWindowVisible`), not at component
completion, because the shell finishes loading well before the bar is on
screen. `VisualQuality.awakened` tells Heartwood when the first bar is up;
its five-second fallback prevents it staying hidden if the window never
maps. Desktop Profile changes ripple Heartwood in cedar; legacy layouts
regrow Rootlines in the profile's accent. Nothing repeats on its own.

## Heartwood

The cross-section of a cedar: the trunk-and-branches emblem of the shield
mark at the heart, three growth rings of six, nine and twelve segments with
cutouts between them, a soft glow behind. Each ring is one dashed arc path,
so a ring is a single retained stroke; turning it is a dash-offset
animation and the light that runs the outer ring is a second short dash
travelling the circumference. States, all from real desktop state:

- idle: still
- hover: the middle ring advances one segment over 440 ms, then rests
- click: a bloom — the instrument swells to 128 % and springs back while a
  white light runs the outer ring — then Signals opens in cedar, or Quick
  Controls in other layouts
- a signal arriving (the pill's alert): a ring ripples outward and fades
- a panel unfolding from the pill: the rings separate radially and settle
- Gaming Mode: the outer ring brightens and thickens, completes one slow
  turn, locks, and keeps a faint glow
- Focus: the rings draw inward and quieten
- Shield attention or risk: one outer segment turns amber and flares twice

The pill steps aside in Gaming Mode on a covered output, so the Gaming ring
is seen when the pill shows for an alert or the hub, and in the showcase.

## Rootlines

A fine root along the bar's foot with curved, tapered forks facing outward
from the centre. Uneven spacing keeps the silhouette organic. Detail stays
in the bottom ten pixels below the controls, with feathered ends. Tiny sap sparks bloom at branch tips only when a
current or growth front reaches them. Paths are retained; animation changes light, opacity and the reveal.

Cedar uses only the single panel-opening trace, fading the underlying root
back into its grain afterwards. The repeating open-panel currents and the
other Rootline reactions below apply to the legacy layouts.

- On awakening, the root reveals from the centre over 1.25 s and the branches
  appear as growth reaches them (duration follows the motion preset).
- While a panel is open on that output, two soft currents travel toward its
  control over 2.6 s. Nearby branches catch the light as it passes. A small
  pool of light seats the control on the root; it fades when the panel closes.
- A panel opening sends a single soft light from the nearest end to its control.
- A Desktop Profile change or Focus starting lights the centre branches in
  the profile's accent; changing profile also regrows the drawing.
- Shield's posture moving sends a light toward the Core pill, amber for
  attention and green for protected.
- Hidden surfaces, Reduced Motion, performance mode and user inactivity stop
  the animations, including effects already in flight. The idle bar is static.

Hidden in the islands layouts, whose plates are separate.

## The unfolding sequence

Opening Connections, in order: the control brightens in cedar green for a
moment (`BarButton.unfolding`); a Rootline light runs toward it; the bar's
lower edge bends down through the DropFrame's concave fillets; the
Foundation extends into the panel on the morph curve with a band of light
along its leading edge (`DropFrame.growing`); the Grain contour follows
eighty milliseconds later; a long bright dash traces the Living Edge once
around the new boundary; the content reveals after the geometry; the
Rootline trace settles (legacy layouts retain a current while open).
Closing fades the content and contracts. Reopening during a close retains
the current geometry and reveal instead of restarting from zero.

## Workspace glide

The active workspace mark is one underline shared by the row, and it glides
to the new workspace on the morph curve with a slight overshoot instead of
jumping between buttons.

## Kinetic Type

docs/KINETIC-TYPE.md. Transitions travel 9 px over the morph duration. A
relay drops the changed letters in one by one, each a beat after the last,
bright white for an instant before settling; the `reveal` style types a
whole line in the same way. In the bar: a Desktop Profile change relays the
tile value (NONE → WORK) and the pill's title resolves between the clock, a
panel's name and a signal, rate-limited so the clock never animates;
CONNECTING → CONNECTED relays on the saved-connection pills; Whispers'
contextual lines are typed in.

## Whispers

The bar's text region: the window title by default; as things happen, a
contextual line in spaced teal capitals types itself in and stays seven
seconds (a profile applied with what it changed, Focus started, paused,
resumed or ended with its counts, Shield's posture, Gaming Mode, a Forest
whisper); and a curated line when no window has a title, turning every
ninety seconds while the user is present. A signal of high or critical
priority asking for attention keeps Whispers quiet. Nothing scrolls.

## Canopy Pulse

Sixteen strokes, 22 px tall, before the tray that follow real audio: CAVA
over PipeWire through one shared feed (`services/Pulse.qml`) that runs only
while a consumer holds it, something is playing, effects are on and the user
is present. Peaks turn bright green. Off by default. Without CAVA the strip
shows nothing and its accessible name says why; levels are never invented.

## Showcase

`qs -p showcase.qml` beside the shell opens a development window that
instantiates these same components and triggers their real transitions
(buttons, or keys H G F W U I A E · T P S L D · O R C · K N M V · 1 2 3 Q ·
X). Its only synthetic input is the Canopy Pulse test signal, labelled as
such.

## Cost

The cedar frame and decorative instruments rest after each event. Existing
provider work, minute clocks and optional Whispers remain separate from
decoration. Legacy Rootline flow runs while a panel is open on its output.
Canopy Pulse is an opt-in continuous consumer only while audio plays and
the effect is visible. Runtime resource use requires measurement; this
description of the lifecycle is not a CPU or GPU benchmark.
