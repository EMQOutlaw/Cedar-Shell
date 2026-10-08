# Bar effects

The bar's animation identity: instruments that move when the desktop
changes and are still while nothing does. Settings › Appearance › Bar
effects turns each one on or off, sets the effect intensity and the motion
preset (Calm, Balanced, Expressive, Off); Reduced Motion and the Off preset
keep the bar static. `VisualQuality.effects` and
`VisualQuality.effectIntensity` are the single gate every instrument reads,
so Performance mode and Gaming Mode shorten and dim them together;
Expressive lengthens every motion by a third and brightens it.

Where each one lives in the running bar, so nothing here is a scaffold:

| Instrument | Component | Instantiated in |
| --- | --- | --- |
| Awakening | `modules/Bar.qml` (sweep band, contents settling), `CedarRootlines.grow()`, `CedarHeartwood.awaken()` | `modules/Bar.qml` per output; `components/core/CoreSurface.qml` |
| Heartwood | `components/CedarHeartwood.qml` | `components/core/CoreSurface.qml`, the Core pill's header (30 px at rest, 44 px in the hub) |
| Rootlines | `components/CedarRootlines.qml` | `modules/Bar.qml`, between the frame and the controls, per output |
| Strata frame | `components/DropFrame.qml` | `modules/CanopyWindow.qml`, every drop |
| Workspace glide | `modules/BarContents.qml` (`workspaceMark`) | the workspace row of every bar |
| Kinetic Type | `components/KineticLabel.qml`, `KineticStatus.qml`, `KineticNumber.qml` | `components/StatusPill.qml` (every status word), `modules/QuickControls.qml` (tile values), `components/core/CoreSurface.qml` (the pill's title), `components/CedarWhispers.qml` |
| Whispers | `components/CedarWhispers.qml` | `modules/BarContents.qml`, the bar's text region |
| Canopy Pulse | `components/CanopyPulse.qml` over `services/Pulse.qml` | `modules/BarContents.qml`, before the tray; `components/AudioSpectrum.qml` shares the feed |

## The awakening

When the shell starts (not in test mode), each bar draws itself in: the
Rootlines grow from the left over 1.1 s, a band of green light sweeps the
bar's top edge once, the controls settle in after a beat, and the Heartwood
arrives spread and turned, its three rings spinning into place over 1.4 s
while its glow fades. It starts 220 ms after the compositor has mapped the
bar's window (`PanelWindow.backingWindowVisible`), not at component
completion, because the shell finishes loading well before the bar is on
screen; the Rootlines and Heartwood are absent until then, and
`VisualQuality.awakened` tells the pill's Heartwood when the first bar is
up. Fallbacks (4 s for the controls, 5 s for the drawings) mean nothing can
stay hidden if the window never maps. A Desktop Profile change regrows the
Rootlines in the profile's accent. Nothing of this repeats on its own.

## Heartwood

The cross-section of a cedar: the trunk-and-branches emblem of the shield
mark at the heart, three growth rings of six, nine and twelve segments with
cutouts between them, a soft glow behind. Each ring is one dashed arc path,
so a ring is a single retained stroke; turning it is a dash-offset
animation and the light that runs the outer ring is a second short dash
travelling the circumference. States, all from real desktop state:

- idle: still
- hover: the middle ring turns continuously (one turn per 3.2 s) and the glow
  rises, for as long as the pointer stays
- click: a bloom — the instrument swells to 128 % and springs back while a
  white light runs the outer ring — then Quick Controls opens
- a signal arriving (the pill's alert): a ring ripples outward and fades
- a panel unfolding from the pill: the rings separate radially and settle
- Gaming Mode: the outer ring brightens and thickens, completes one slow
  turn, locks, and keeps a faint glow
- Focus: the rings draw inward and quieten
- Shield attention or risk: one outer segment turns amber and flares twice

The pill steps aside in Gaming Mode on a covered output, so the Gaming ring
is seen when the pill shows for an alert or the hub, and in the showcase.

## Rootlines

A root along the bar's foot with branches rising from it and a lit tip on
each, geometry built once per width and retained; drawn in by the growth
(a dash-offset draw-in along the whole path), so the first thing seen is
the drawing happening.

- While a panel is open on that output, light streams along the root from
  both ends toward the control it grew from (short dashes travelling at
  50 px/s); the tips near that control glow. It stops the moment the panel
  closes, so an idle bar has no running animation.
- A panel opening runs a long bright light with a tail from the bar's
  nearest end to the control.
- A Desktop Profile change or Focus starting lights the centre branches and
  tips in the profile's accent and lets them fade; the profile change also
  regrows the drawing.
- Shield's posture moving sends a light from the right end toward the Core
  pill, amber for attention, green for protected.

Hidden in the islands layouts, whose plates are separate.

## The unfolding sequence

Opening Connections, in order: the control brightens in cedar green for a
moment (`BarButton.unfolding`); a Rootline light runs toward it; the bar's
lower edge bends down through the DropFrame's concave fillets; the
Foundation extends into the panel on the morph curve with a band of light
along its leading edge (`DropFrame.growing`); the Grain contour follows
eighty milliseconds later; a long bright dash traces the Living Edge once
around the new boundary; the content reveals after the geometry; the
Rootlines stream toward the control for as long as it stays open; and
everything else stops. Closing fades the content first and contracts.

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

Idle: nothing runs. The awakening runs once per bar at start; the Rootline
flow runs only while a panel is open on that output; every other instrument
animates on its event and returns to retained geometry. Canopy Pulse is the
one opt-in continuous consumer, and only while audio plays.
