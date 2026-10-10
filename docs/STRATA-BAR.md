# Strata bar

The `cedar` layout uses one continuous Foundation and Grain frame. The Core
rests directly on that surface, without a separate border. Other bar styles
keep their existing layout.

| Region | Controls |
| --- | --- |
| Left | CEDAR / Station, applications, workspaces, focused application or optional Whispers |
| Center | Heartwood, current profile or real activity, Signals |
| Right | Optional audio pulse and tray, connections, audio, battery / power, calendar, notifications, Quick Controls |

Clicking the center opens Signals. Quick Controls has its own button at the
right edge on every output, including outputs without the activity Core.
Audio supports wheel volume adjustment. Tray items retain activation,
secondary activation, context menus and scrolling. Each dropdown anchor
belongs to the output containing its control.

The layout uses theme tokens and measured text widths. As space contracts,
the application title, optional effects, tray items, date and status labels
yield first. The workspace strip becomes the current workspace plus its
overview control. Core reservation is smaller on narrow logical outputs.
The time remains visible; its tooltip retains the full date and time.

## Ownership and motion

- `StrataBarFrame` owns the retained Foundation and Grain paths.
- `StrataBarContents` arranges the controls and reuses the existing providers.
- `CoreSurface` owns Signals and its privacy/activity indicators.
- `Canopy` retains panel ownership, topic routing and output anchors.
- `CanopyWindow`, `DropFrame` and `StrataGeometry` retain the shared unfolding
  surface, concave joins, content reveal, dismissal and screen bounds.

The controls are usable immediately. Awakening briefly illuminates the grain;
it does not hide the controls. Heartwood hover advances one segment and rests.
A dropdown sends one Rootline trace toward its control. The cedar layout has
no repeating decorative current while a panel remains open. Kinetic Type
handles semantic labels; clock, timer and recording numbers use static text.

`VisualQuality.functionalMotion` respects Reduced Motion and the Off preset.
Efficient and Gaming modes shorten functional transitions while the existing
effects policy can disable ambient decoration. Interrupted dropdown reopening
retains its current geometry and content opacity. Hidden Heartwood effects
cancel rather than continuing offscreen.

Whispers and Canopy Pulse remain optional. Their Strata instances are lazy
and release their work when hidden or unable to fit. Audio levels come from
the existing shared Pulse provider.

## Verification

The redesign has passed Qt 6.12 QML syntax parsing, the production Canopy
transition-command tests, and Strata geometry / Kinetic tests. Actual
Quickshell 0.3.1 with bundled Qt 6.11.2 also passed the 24-state Strata harness
and the existing 36-state six-layout harness using the offscreen software
backend. These runs instantiate the production QML and produce screenshots;
their provider inputs are fixtures. They do not certify Hyprland placement,
GPU frame timing or real hardware actions.

The Quickshell navigation harness also passed real pointer / keyboard events
for the center Signals header, right-side Quick Controls, Connections, Escape
and lock guards. The motion harness observed intermediate Core sizes, bounded
window allocation, collapse, Reduced Motion and critical-signal preemption.
The Canopy harness rendered its 15 production pages at 960px and 480px widths.

Run the actual Quickshell layout harness:

```sh
python3 tests/check_strata_bar.py /tmp/cedar-strata-shots
python3 tests/check_core_bars.py
python3 tests/check_navigation.py
python3 tests/check_motion.py
python3 tests/check_canopy.py
node tests/core/canopy_transition_test.js
node tests/core/strata_test.js
```

The Strata harness covers 640 / 960 / 1280 logical widths, Core enabled and
disabled, font scales 1 and 1.3, and two output identities. It asserts control
bounds, center clearance and output-anchor ownership and saves 24 screenshots.
Workspace and VPN states are explicit fixtures. It reports NOT RUN if `qs`
is missing; syntax parsing is not a substitute for this runtime gate.

Before merging, inspect the live shell on Hyprland: rapid panel switching and
reopening, keyboard focus and Escape, output hotplug and mixed scaling, tray
menus, real audio/network/power actions, privacy indicators, and reduced motion.
Measure idle wakeups and transition frame timing on that system. No CPU, GPU,
memory or compositor performance improvement is claimed from source checks.
