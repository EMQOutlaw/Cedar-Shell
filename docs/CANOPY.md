# Core, Canopy and Instruments

CEDAR remains the existing Quickshell shell. One optional Canopy host descends
beneath the bar on a selected output. Its native window is keyed to that exact
screen; repeated data updates retain the window and controls. Native dimensions
change at navigation boundaries, not on each animation frame. Entry is 180 ms,
with the existing threaded renderer settings and Reduced Motion respected.

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
  notifications, quick controls, Trails and Startup. Only one can be pinned. Pinning
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
