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

## Measuring

`scripts/measure_resources.py --pid <shell pid> --output <private file>` samples
CPU (percent of one core) and PSS for the shell and its helpers across three
runs. Compare equivalent sessions only; a wallpaper change or an open panel
changes the number. `scripts/audit_resources.py` writes the static ledger of
timers, processes and animations with their stated cadence and stop
conditions. Neither is a frame-rate benchmark.
