# Core, Canopy and Instruments

CEDAR remains the existing Quickshell shell. One optional Canopy host descends
beneath the bar on a selected output. Its native window is keyed to that exact
screen; repeated data updates retain the window and controls. Native dimensions
change at navigation boundaries, not on each animation frame. Entry is 180 ms,
with the existing threaded renderer settings and Reduced Motion respected.

## The morph system

The bar is the foundation and everything grows out of it, but the pieces are
separate Wayland layer surfaces by necessity: the bar (one per output, the
Top layer), the Core pill (the host output, Overlay) and the Canopy drop (a
transparent full-width surface on the Overlay layer, masked to the drop and
unmapped while closed). They cannot be one render surface under layer-shell,
so CEDAR keeps a synchronized visual seam instead and does not claim more:

- Strata: three coordinated layers on every bar surface. The Foundation is
  the fill (`Theme.background` at the panel opacity); the Grain a lighter
  contour two pixels inside it (`Theme.border`); the Living Edge the outline,
  which brightens while a surface unfolds or retargets and settles back.
  `components/DropFrame.qml` draws all three for anything that grows from the
  bar: a flat top left open at the bar's lower edge, two concave fillets
  where the bar's edge bends down to become the drop's sides, the long cut
  bottom-left and the short cut bottom-right of the pill's language. The
  bar's own frame (`HudPanel`) carries the same Grain contour.
- Geometry is decided, then interpolated. `components/core/StrataGeometry.js`
  computes the target rect from the bar's width, the control's screen rect,
  the panel's wanted size and the edge inset (centred on the control, clamped
  inside the bar, the tie line at the control's centre); the drop assigns
  that rect and its Behaviors move there. `Canopy.surfaceState` is the
  controller's state: collapsed → opening → expanded → retargeting →
  expanded → closing → collapsed, readable with `qs -c cedar ipc call canopy
  status` together with the aimed rect and the anchor.
- Retargeting: a topic that shares the open surface's origin (a tab of the
  same drop) morphs in place from wherever the geometry is: content leaves,
  the surface moves to the next size, the next content arrives. A topic with
  a different control folds the drop back into the bar and grows it again
  from there, because they are different objects.
- The pill sits inside the bar's height with the bar's own fill. At rest its
  outline nearly disappears, so its shape and the ember line carry the
  identity; it lights with a signal, a hover or an open panel. Clicking it
  opens Quick Controls, which grows from it; hovering a signal peeks and
  clicking it morphs the pill itself into the Signals stack, inside the same
  surface. Recording and privacy keep the line even while another signal is
  in front.
- Opening a second topic collapses the open drop back into the bar and drops
  the next one from its own control; nothing floats between. Closing fades
  the content ahead of the shrink. Every transition is a `Behavior`, so a
  rapid open, close, open simply retargets from wherever the geometry is.
- One motion vocabulary in `Theme.qml` (`hover` 120, `expand` 220,
  `morphGrow` 320, `morphShrink` 200, `revealDelay` 110, `reveal` 220,
  `conceal` 90, `entrance` 1050 ms) scaled by `VisualQuality.motionScale`:
  full at normal quality, 0.6 in Performance mode, 0.35 in Gaming Mode;
  Reduced Motion disables the Behaviors and snaps. Nothing animates after a
  morph settles.
- Every drop has an origin on the bar: the pill (Quick Controls, Power), the
  network nub (Connections), the CEDAR mark (Field Station), the apps button
  (Go), the bell (Notifications) and the ▣ button at the end of the
  workspace row (the overview). Topics with their own control are standalone,
  without the tab strip; the rest are tabs inside the Canopy.

## Available now

- Forest derives QUIET/AWAKE/FLOW/HUNT/WATCH/EMBER/REST from real CPU usage,
  network traffic, native idle monitors, power profile, and existing Core
  activities. Quiet requires a known CPU reading; ordinary states settle over
  three samples, while recording/privacy/warnings take priority. HUNT represents
  the performance power profile, not guessed game detection.
- Pulse reflects those states. Core retains its bar-sized resting silhouette.
  Echoes keep at most three system glyphs for six seconds; clipboard and other
  private content is excluded.
- Whispers currently cover prolonged quiet, charge reaching 90%, and a connected
  Bluetooth audio output after long idle. They never preempt a Signal, respect
  DND, have a ten-minute global and six-hour per-type cooldown persisted across
  reloads, and have individual settings. No heuristic kernel/VPN assertions.
- Trails are opt-in, memory-only and bounded to 24 entries: application class,
  CEDAR surfaces, Settings pages, and non-input Go actions. Window titles,
  browser content, commands, and user-entered Go text are not collected. Lock or
  disabling Trails clears them. CEDAR navigation entries can be reopened.
- Canopy: audio, network, Bluetooth, system, weather, time/calendar, clipboard,
  notifications, quick controls, Trails, Startup and Workspaces.
- Connections carries a VPN section: every VPN-plugin or WireGuard profile
  NetworkManager knows, whoever created it, with Connect, Disconnect and
  Forget through NetworkManager's own D-Bus calls and a state read from it
  (Saved, Connecting…, Connected, Disconnecting…), never an optimistic
  success. A profile kept by a provider's own application (Proton VPN,
  Mullvad and others name theirs recognisably) says so, because that
  application may reconnect it. A kill-switch connection an application
  keeps active is reported as that application's; CEDAR offers no kill
  switch of its own because it cannot enforce or verify one. Advanced
  settings stay the profile's (nmtui or the provider's app). Bluetooth rows
  show BlueZ's state or the action in flight for that device (Pairing…,
  Connecting…, Disconnecting…), the battery where reported, and trust.
- Workspaces (Super+Tab, Go › Workspaces, `canopy flip workspaces`): one column
  per monitor, one chamfered tile per workspace in the monitor's shape with
  each window drawn where it sits, a "new" tile per monitor, and special
  workspaces named but not drawn. Thumbnails come from the compositor's
  toplevel-export path through `ScreencopyView`, captured once when the
  overview opens and again when the focused window changes while it is open,
  never live; a window the compositor refuses to export shows its class
  instead. Click or Enter switches, arrows and 1–9 choose, a window dragged
  onto another tile moves there silently. Dispatchers follow the running
  Hyprland (`hl.dsp.focus`/`hl.dsp.window.move` under a Lua configuration,
  the classic strings otherwise). Only one can be pinned. Pinning
  releases exclusive keyboard focus so desktop work continues; unpin to type.
- Audio reuses native MPRIS and PipeWire controls. Native PwNodePeakMonitor is
  explicit opt-in and opens the selected microphone only while its instrument
  is visible. Application routing validates Pulse stream identity and output
  existence. It uses the PipeWire PulseAudio-compatible server when available.
- Up to eight audio scenes save real current devices, mute/volume and one route
  per application. Applying validates disconnected devices and gains before
  mutation. A subsequent server error can still leave a partial apply; errors
  are reported rather than claimed as success. Scene files are private (0600).
- CAVA spectrum uses real PipeWire samples and 24 bounded bars. It is off by
  default, stopped on close/Reduced Motion, and never synthesizes a waveform.
- Startup lists the session's autostart entries (`~/.config/autostart` over the
  system `autostart` directories) with the state of the `app-*@autostart`
  unit the systemd generator ran for each, a switch, run/stop now and remove.
  Typing adds an installed app by copying its desktop entry, or any command as
  a `cedar-*.desktop` entry marked `X-CEDAR-Startup`. System entries are turned
  off with a `Hidden=true` override, never deleted. Hyprland `autostart.lua`
  lines show read-only. `scripts/startup_apps.py` does the file work; nothing
  is launched or stopped except by an explicit Run/Stop.
- System Instrument reads real CPU/memory/storage/temperature and available
  NVIDIA or DRM GPU telemetry. GPU queries run only while visible, every 5 sec.
- Sky Watch extends the existing Open-Meteo request with hourly temperature/rain
  probability and sunrise; forecasts share the old cadence and stale indicator.
- Calendar provides actual dates and the existing persistent timer service.
- Notification Canopy uses the existing notification history, independently of
  Signal history. Normal and critical popup routing is preserved.
- Clipboard capture is opt-in and memory-only. Up to 20 text/PNG items (five pins),
  with text capped at 32 KiB and images at 1 MiB. Known sensitive hints are skipped;
  unmarked secrets cannot be reliably identified, which the opt-in explains.
  Content is hidden until Reveal/Copy; nothing is sent to Core or persisted.
  Lock/disable clears pins too. Pin means retain within this session.

## Capability boundaries

No compatible DSP control backend is installed/integrated. EQ exposes an honest
unavailable capability object (`available`, `bands`, `filters`, `reason`), not
pretend sliders. Graphical/parametric EQ, preamp, device EQ presets, suppression,
gate/compressor and automatic EQ scene/profile coupling still need an actual DSP
adapter. Installing EasyEffects alone does not implement that adapter.

Game FPS/1% lows, VRR measurement, calendar accounts, official severe-weather
alerts, kernel-reboot observations and automatic desktop-profile/audio-scene
coupling need reliable providers. No sample readings are displayed as live data.
Weather forecasts are model data, not an official severe-weather alert feed.

## Validation

`tests/check_canopy.py` renders ten panels at 960 and 480 pixels, and checks
pinning, opt-in histories, and lock cleanup. `tests/core/forest_test.js` checks
state priorities, bounded trails, and private Echo exclusions.
`tests/test_instruments.py` checks stream identity, scene persistence, gain
validation, and rejecting missing devices without mutation. Existing Settings,
Core hold/animation, and six bar-layout harnesses remain in use.

These offscreen checks do not establish hardware audio results or physical FPS.
Native compositor, PipeWire, CAVA and clipboard interaction need the desktop
session; the development sandbox cannot access those sockets.

Reference APIs: [Quickshell focus grabs](https://quickshell.org/docs/v0.3.0/types/Quickshell.Hyprland/HyprlandFocusGrab/),
[Open-Meteo forecast variables](https://open-meteo.com/en/docs).
