# Performance policy

The shell should cost nothing noticeable while it is simply on screen, and
nothing at all while nobody is at the keyboard. The visual language stays:
breathing filaments, spores, gauges and the watch face are all still here.
They just stop asking for frames they cannot be seen in.

## Rules

1. **No vsync loop on an always-mapped surface.** The bar, Core and lock
   surface are mapped for the life of the session. A `*Animator` loop on them
   commits a frame every refresh, forever, and keeps the compositor repainting.
   Ambient loops on those surfaces use `Breath`, which steps at
   `Motion.ambientFps` (12 per second) and only while `Motion.active`.
2. **Ambience rests with the user.** `services/Motion.qml` pauses every ambient
   loop after 120 seconds without input, under Reduced Motion, and in tests.
   Functional transitions (panel open/close, slider motion) are unaffected.
3. **Nothing samples a hidden value.** Brightness is read while a brightness
   control or OSD is visible and on key presses, not every ten seconds for the
   life of the shell. Telemetry cadence is owned by its visible consumers
   (`SystemStats`); the ambient CPU hint samples every 20 s.
4. **Subscribe, then filter.** The NetworkManager stream ignores access-point
   signal-strength churn unless a network list is on screen, and debounces to
   600 ms when collapsed. The recorder probe wakes once per second and scans
   `/proc` every third second.
5. **Build panels when shown.** Go, Settings, Field Station, Canopy, Control
   Center, Power, Themes, Wallpapers and notification history are created by a
   `Loader` on first show and released on close, per output.

## Audit of 2026-10-06

Profiled first, on the live shell (two displays, 3440×1440 at 175 Hz and
2560×1440 at 240 Hz, NVIDIA with the Vulkan scene-graph backend, Quickshell
0.3.1), then changed the four things the evidence pointed at. All numbers are
from this one machine and this one session; nothing below is a benchmark of
other hardware. Measured with `/proc` samples (`scripts/measure_resources.py`
and a 100 ms process-tree watch), `/proc/<pid>/smaps_rollup`, `nvidia-smi`,
`hyprctl layers` and the offscreen harnesses.

### Baseline

| Measure (live shell, nobody at the keyboard) | Before |
| --- | --- |
| CPU, 30 s window, ambience resting | 0.27 % of one core |
| Voluntary context switches, same window | 87 (≈3 per second) |
| Helper processes spawned in 30 s | 2 (`telemetry.py sample … temperature`, `telemetry.py sample … fast`), i.e. about 4 Python starts per minute plus a `sensors -j` child |
| Persistent helpers | 4: `connections.py --watch` (29 MB), `default_apps.py --watch` (35 MB), `core_probe.py` (13 MB), `wl-paste --watch` (2 MB) |
| Shell PSS / RSS | 686 MB / 732 MB (shell and helpers together: 747 MB PSS) |
| Of which | 394 MB anonymous, 205 MB `/dev/nvidiactl` mappings, 5.6 MB QML heap, ~40 MB libraries |
| GPU memory (shell process) | 464 MiB |
| Windows with a render thread | 5: two backgrounds (full resolution), two bars, the Core |
| Threads | 39 |
| Startup to bar mapped / IPC answering | 0.79 s / 0.74 s after `systemd-run` |
| Memory after 600 panel open/close cycles (offscreen, software RHI) | 125 MB → 142 MB after the first 100, flat to 600 |

The idle shell was already quiet: the previous pass (dev.13) had moved every
ambient loop onto `Breath` and `Motion`. What remained was structural.

### Bottlenecks found

1. **A process as the telemetry heartbeat.** `SystemStats` ticked a 1 s timer
   for the life of the shell to ask whether a topic was due, then spawned
   `python3 scripts/telemetry.py` every 20 s for CPU/memory/network and every
   30 s for temperature, where the helper itself spawned `sensors -j` and
   walked its JSON. Disk usage ran every 30 s whenever the disk warning was on,
   which it is by default. That is the "timer → shell → parser → property" shape
   the policy forbids, and it was the only recurring spawn on an idle desktop.
2. **Forest recomputed once a second.** `Forest.update()` ran on a 1 s timer
   whenever the Core was enabled, filtering `CoreService.rows` and re-deriving
   the state from inputs that are all properties and only change on events.
3. **Both bar trees built per output.** `Bar.qml` instantiated `BarContents`
   and `BarIslands` and toggled `visible`, so each display carried a second,
   invisible bar with its own bindings, tray model and Core controls.
4. **Memory is the driver's.** Of 686 MB PSS, about 600 MB is anonymous
   memory and `/dev/nvidiactl` mappings that scale with the five windows and
   their full-resolution swapchains (two 3440×1440 and 2560×1440 background
   surfaces); the QML heap is 5.6 MB and the wallpaper is a 1672×941 PNG. No
   leak: 600 open/close cycles stay flat. This is not something a QML change
   recovers; see "Left alone".

Examined and found already right: panels are `Loader`-built on show and
released on close; `Osd`, `Hud` and the Core window gate their content on
`visible`; every infinite animation is gated by `Motion.active` and visibility;
workspace, window, media, audio, power, privacy and Bluetooth state come from
Quickshell's native event sources, not `hyprctl` or `playerctl`; images declare
`sourceSize` where they are thumbnails; singletons hold the shared state and
per-output QML only renders it.

### Changes

- **`services/SystemStats.qml`** reads `/proc/stat`, `/proc/meminfo`,
  `/proc/net/dev`, `/proc/uptime` and the chosen hwmon `temp*_input` in
  process. Each is a `FileView` with `preload` and `blockLoading`, re-read with
  `reload()` + `waitForJob()` (a reload without preload hands back the previous
  read; the `loaded` signal is asynchronous). One non-repeating timer sleeps
  until the earliest due topic. hwmon inputs are discovered once per shell
  lifetime by `telemetry.py sensors`; the CPU package sensor (k10temp Tctl,
  coretemp Package id 0, zenpower, cpu_thermal) is preferred, otherwise the
  hottest input stands in as `sensors` did. Disk usage is the one remaining
  process, `df -P -k`, every 30 s while an instrument shows it and every five
  minutes for the warning. Cadences, properties and `demanded` are unchanged.
- **`services/Forest.qml`** recomputes when a `signature` of every input
  property changes. The 1 s clock runs only while a state is settling (the
  three-sample debounce), an echo or whisper is fading, or a signal is
  announced and its attention window will pass.
- **`modules/Bar.qml`** builds only the selected bar style per output through
  `Loader`s; the input mask follows the loaded `BarIslands`.
- **Settings › Health › Shell cost** shows the shell's resident memory and
  threads from `/proc/<pid>/status` (every 2 s, only while the page is open),
  ambience state, the live telemetry cadence and voluntary context switches as
  a wakeup gauge, so a regression is visible without a terminal.

### Results

Same machine, same session, live shell, measured the same way after the
changes. "Resting" is a 30 s window with nobody at the keyboard and ambience
paused; "breathing" is the first two minutes after input, when the Core pill
and filaments breathe at 12 steps per second.

| Measure | Before | After |
| --- | --- | --- |
| CPU, resting window | 0.27 % of one core | 0.23 % of one core |
| Voluntary context switches, resting window | ≈3 per second | 0.4 to 1.0 per second |
| CPU, breathing window | not measured | 1.5 % of one core, ≈100 wakeups per second |
| Helper processes spawned per minute, idle | ≈4 Python starts plus `sensors` | 0 (one `df` every five minutes; one `telemetry.py sensors` per shell lifetime) |
| 1 s timers running while idle | SystemStats scheduler, Forest | none from these two |
| Shell PSS, four minutes after start | 686 MB | 620 to 631 MB |
| Persistent helpers | 4 | 4 (unchanged, see below) |
| Startup to bar mapped / IPC answering | 0.79 s / 0.74 s | 0.79 s / 0.74 s (unchanged) |
| Offscreen: 600 panel cycles | flat at 142 MB | unchanged |

The breathing figure is CEDAR's identity doing its job and is bounded by
`Motion` (it stops after 120 s without input, and under Reduced Motion or
Performance mode). The PSS difference is within what a wallpaper change or an
open panel moves and should not be read as a saving; the win is the absence of
spawns and of two always-on timers. Opening a panel still runs `control.py`
once for the power profile (user-triggered, not a heartbeat).

### Performance mode

Settings › Power & Lock › Performance mode, stored as `performanceMode`
(`auto` by default, `on`, `off`). It runs only the basics: Reduced Motion for
every decorative loop and entrance sweep (breathing light, spores, orbiting
accents, the spectrum), and no ambient telemetry pulse. Panels, OSD, Core
signals and instruments keep working at their visible cadences. `auto` turns
it on while the system power profile is power-saver (battery saver) or the
focused window is fullscreen, which is how games run; the Power page badge and
the Health › Shell cost card say when it is on and why. The fullscreen rule
is event-driven: Hyprland's `fullscreen` event refreshes the toplevel and the
focused window's `lastIpcObject.fullscreen` is read, so no polling.

### Shield and Gaming Mode

Added after the audit, built to its rules. Idle, neither exists: the
capability registry is one helper run at startup, Shield reads only while its
page is open (on open, refresh, an action, and a debounced network change) and
Gaming Mode's inhibitor and GameMode watcher run only while applicable, the
watcher only when GameMode is installed. Entering or leaving Gaming Mode costs
two `hyprctl` helper runs and one power-profile call, all user-triggered, and
one preparation panel that is created for the transaction, binds to the
service's step states (no timers of its own) and is released 1.4 s after it
settles. The
shield mark animates only on a transition and is static afterwards. The
process-tree watch on this machine after loading them showed no new recurring
spawn and no new persistent helper; a clean resting window could not be
repeated at the time because the desktop was in use.

### Left alone, and why

- **GPU and driver memory.** The backgrounds are two full-resolution layer
  surfaces with their own swapchains; the bars and Core are small. The
  Omarchy adapter already hands the wallpaper to an external daemon
  (`CEDAR_BACKGROUND=external`), which drops both background windows and their
  render threads. Measuring that trade-off on this machine, and whether a
  shared-memory wallpaper is wanted on portable installs, is the next step.
- **The four persistent helpers.** `default_apps.py --watch` (35 MB) could be
  replaced by Quickshell's native `DesktopEntries` for the catalog, keeping the
  GIO launcher for one-shot launches; `connections.py --watch` (29 MB) by the
  `Quickshell.Networking` module. Both change tested boundaries (real GIO
  launches, NetworkManager stream policy) and are a separate change each.
  `core_probe.py` wakes once a second for LED state and scans `/proc` every
  third second at 0.15 % of a core.
- **`LockStatePublisher`'s 5 s heartbeat** is the lock-safety contract with the
  Omarchy bridge (a dead shell must read as stale, never as unlocked). It only
  runs under Trailwatch-on-Omarchy and stays.
- **Full desktop profiles.** Performance mode above covers the "basics only"
  half. The Balanced / Work / Gaming / Battery / Night profiles in the
  development brief would additionally coordinate DND, wallpaper, refresh/VRR
  and audio; `Motion`, `Config.performanceActive` and the per-consumer
  cadences are the levers they will use.

## Measuring

`scripts/measure_resources.py --pid <shell pid> --output <private file>` samples
CPU (percent of one core) and PSS for the shell and its helpers across three
runs. Compare equivalent sessions only; a wallpaper change or an open panel
changes the number. `scripts/audit_resources.py` writes the static ledger of
timers, processes and animations with their stated cadence and stop
conditions. Neither is a frame-rate benchmark.
