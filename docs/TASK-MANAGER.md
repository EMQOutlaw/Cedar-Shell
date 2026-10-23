# CEDAR Task Manager

CEDAR Task Manager is an independent Qt Quick application. Field Station opens
it through one utility action; closing Field Station or reloading Quickshell
does not close it. Its four views are Overview, Processes, Performance and
read-only systemd user Services.

## Build, install and recovery

Build requirements: Linux, C++20 (`g++`), `pkg-config`, Qt 6 Core, Network, GUI,
QML, Quick, Quick Controls 2 and D-Bus, including `moc`. On Arch these are
`gcc pkgconf qt6-base qt6-declarative`. NVML is optional and loaded dynamically.
Development builds do not install packages or require sudo.

```sh
python3 scripts/build_task_manager.py
./scripts/cedar-task-manager
```

The normal managed installer builds both binaries before switching releases.
Each immutable release contains its own `libexec/cedar-task-manager`,
`libexec/cedar-taskd` and QML sources. Their hashes are included in
`release-files.json`. The command, application desktop entry, icon and current
release link participate in the existing installation journal. `cedar
task-manager` is also supported. Updates use the same install transaction.
An existing unrelated command is preserved and installation is refused.

Use the installer's printed `cedar restore` recovery route to restore the
previous transaction. Do not copy binaries between releases. A running Task
Manager retains the release it opened; close and reopen it after updating or
rolling back. The per-build socket and handshake prevent mixing backend and
frontend versions. Existing installations still use their existing release
until a normal update is applied.

Arch and Nix packaging recipes build the same native sources. The installer
adds Super+Shift+Escape through CEDAR's owned binding list only when live
Hyprland inspection confirms it is free. Missing inspection defers the binding.
No system service is enabled.

## Architecture and data

`native/taskmanager/collector.*` contains independent Linux collection,
optional NVML integration and process control. `backend.cpp` handles sampling
and validated IPC. `frontend.*` supplies the Qt application, incremental
QAbstractListModel, sort/filter proxy, bounded histories, graph item and
read-only D-Bus service queries. `taskmanager/*.qml` supplies the views.

CPU utilization uses differences between successive `/proc/stat` counters,
excluding guest fields already counted in user/nice. Idle includes iowait.
First samples and counter rollback are unknown, not zero. Per-process CPU is
100% per logical core and uses `(PID, start ticks)` identity.
RAM used is total minus MemAvailable; cache includes reclaimable slab and is
reported separately. Swap uses SwapTotal minus SwapFree.

Processes are read directly from `/proc`, with bounded command lines, UID,
executable, state, parent, session, cgroup, threads, nice, RSS and runtime.
The final closing parenthesis in stat delimits names containing spaces or
parentheses. Start time is rechecked after ancillary reads; disappearing or
inaccessible processes are skipped. No environment variables are collected.
No process snapshots or command lines are written to disk.
Snapshots are bounded to 20,000 records and 24 MiB of process JSON. Any omitted
records produce a visible warning; the UI never silently claims the list is complete.

Disk rates use elapsed monotonic time and sector deltas. Physical leaf devices
exclude partitions and stacked device-mapper layers from aggregates.
Filesystems are a separate list, deduplicated by mount device identity; only
local block filesystems are queried to avoid blocking remote mounts.
Network rates use byte counter deltas and actual elapsed time; aggregate
traffic excludes loopback. Unsupported sensors and GPU fields remain null.

NVML discovery supports multiple NVIDIA devices, utilization, memory,
temperature, power, graphics clocks and available compute/graphics process
memory. GPU rows use a provider-neutral schema. AMD/Intel providers are not
implemented. Missing NVML never prevents CPU/process monitoring.

The application consumes the existing CEDAR palette JSON, theme override,
font, font scale, radius and reduced-motion preferences. It watches changes;
it does not import the shell's singleton graph. Window geometry and selected
view are stored in `cedar/task-manager.ini` under the user's config directory.
Gaming Mode's existing state file is read without changing its policies.

## Protocol and safety

Transport is newline-delimited JSON over a private Unix socket:
`$XDG_RUNTIME_DIR/cedar/taskd-<build-id>.sock`. Runtime directories must be
owned by the user with no group/other access; socket paths must be owned
sockets, not symlinks. Both sides require same-UID SO_PEERCRED.
There is no TCP listener, command-shell execution or privilege elevation.

Every message includes `"protocol":1`. A connection begins with
`{"protocol":1,"type":"hello","build":"<build-id>"}`. The backend replies with
`hello`, `build`, `uid`, and a `capabilities` array. A different build or protocol
is rejected. The frontend then sends `visibility` with boolean `visible`.

`snapshot` messages contain `sequence`, `sampleIntervalMs`, CPU, memory, GPU,
disk, network, filesystem and error fields. `processes` messages contain a
sequence and `rows`; unchanged tables are not resent. Actions carry `type:
"action"`, a bounded string `id`, integer `pid`, string start ticks `start`,
and `action` (`term`, `kill`, `stop`, `continue`, `nice`). Kill requires boolean
`confirmed:true`; nice requires an integer from -20 to 19. `action-result`
echoes the ID/identity and contains `ok`, `code`, and `message`. `error`
terminates an invalid connection.

Requests are bounded to 8192 bytes and 20/second per client, with at most
eight clients and a three-second handshake deadline. Unknown fields and
commands are rejected. Slow readers are disconnected before unbounded output
accumulates. Frontend input is bounded to 32 MiB. Telemetry timeout clears
readings and displays a disconnected state while reconnecting.
Collector startup/exit diagnostics are retained in a bounded 4 KiB memory
buffer, with a short visible error taking precedence over previous action
messages. They are not discarded or written to an accumulating log.

Signals require pidfd_open and pidfd_send_signal plus start-time validation.
There is no numeric-PID signal fallback. Only processes whose real, effective,
saved and filesystem UIDs match the caller are eligible. Backend/frontend,
their ancestors, session leaders, essential session cgroups, compositor and
shell processes are protected. CEDAR scripts are identified using their
actual source root markers in addition to executable information.

Linux has no pidfd-based setpriority. Priority changes therefore require a
short-lived tracing helper: seize the selected task, verify its pidfd/start
identity, interrupt it, verify again while held, call setpriority and detach.
The tracer holds the PID against reuse; its exit detaches automatically and
never kills the target. There is no unguarded fallback. Yama, an existing
debugger, SELinux or other tracing restrictions may deny this operation even
when ordinary setpriority would be allowed. The UI reports that refusal.
Stopped targets must be resumed before priority changes. No tracing policy is
changed. Priority applies to the Linux thread-group leader; it is not a
recursive process-tree or all-thread scheduling policy.

Force Stop has an explicit dialog naming the captured process and PID.
Signals are reported as delivered, not as proof the process has exited.
Pending actions have a timeout and never invent a successful result.

## Resource lifecycle

Visible sampling is once per second, hidden/minimized sampling once per five
seconds. The backend stops sampling with no authenticated consumers and exits
after five seconds. Closing the application terminates its owned backend.
The singleton focus socket prevents duplicate windows across release versions.
Histories retain at most 120 samples; the process ListView virtualizes rows.
Filtering is debounced, updates are batched and sorting occurs once per batch.
Graphs repaint when samples change, not on a continuous animation timer.

## Field Station migration

The Tasks & performance navigation and `StationTasks.qml` were removed,
along with their exclusive `scripts/task_monitor.py` polling helper and tests.
The existing Overview body, widgets and animations are unchanged.
`SystemStats.qml` and every shared consumer remain. Legacy task/system routes
launch the standalone application. The one Task Manager button is in the
existing Terminal/Browser/Files/Update CEDAR utility flow.

## btop reference and licensing

Reviewed upstream revision
[`4792b0700e617cb2ee5ffbced50c1e52528b912a`](https://github.com/aristocratos/btop/tree/4792b0700e617cb2ee5ffbced50c1e52528b912a):
`src/linux/btop_collect.cpp`, `src/btop_shared.hpp`, `src/btop_shared.cpp`.
The reviewed techniques are CPU time deltas/guest exclusion, MemAvailable
accounting, proc stat field offsets/start identity, elapsed-time throughput,
and dynamically resolved NVML interfaces.

Direct extraction would pull in btop's Runner, Config, shared global history
and terminal-oriented data structures. CEDAR independently implements these
Linux techniques with Qt data/IPC types. It does not compile copied upstream
translation units, scrape output, execute btop, or require btop to run.
The upstream Apache 2.0 license and attribution are preserved in
`licenses/btop-Apache-2.0.txt` and `native/taskmanager/NOTICE`; this does not
relicense CEDAR. Linux process controls follow the documented
[pidfd](https://man7.org/linux/man-pages/man2/pidfd_send_signal.2.html),
[ptrace](https://man7.org/linux/man-pages/man2/ptrace.2.html) and
[priority](https://man7.org/linux/man-pages/man2/setpriority.2.html) interfaces.

## Verification

```sh
python3 tests/check_task_manager.py
python3 -m unittest discover -s tests -p test_task_manager.py
PYTHONPATH=scripts python3 -m unittest discover -s tests -p 'test_settings*.py'
python3 tests/check_station_tasks.py
python3 tests/check_identity.py /tmp/cedar-identity
python3 -m unittest discover -s tests -p test_distribution.py
python3 scripts/update_source_inventory.py --check
```

The native check builds collector tests, uses disposable owned processes,
exercises protocol rejection and idle cleanup, then runs the real QML window
offscreen through all views, selection, search, sorting, narrow geometry and
6,000 fixture rows. It never signals the real compositor or CEDAR session.
`CEDAR_TASK_REQUIRE_IPC=1` makes a blocked IPC environment fail rather than skip.
The self-test's explicitly enabled local-collector transport allows QML
verification in sandboxes denying SO_PEERCRED; it cannot bypass authentication
in a normal application launch.
The failure-window fixture runs a deliberately failing collector executable
and verifies that its real startup error is visible with an empty process
model and cleared telemetry.

Hardware NVML, monitor changes, compositor focus, fractional scaling and
long-duration rendering require a real desktop session. Service management
is intentionally read-only. Hierarchical process trees are not implemented; grouping uses executable
identity. Desktop-entry icons are now resolved by the standalone frontend,
with a neutral CEDAR glyph for unmatched processes.

## Recorded engineering verification — 2026-10-20

The native and recovery job for
[`5bb545b`](https://github.com/EMQOutlaw/Cedar-Shell/actions/runs/39402174400)
passed on Ubuntu 24.04 with Qt 6.4.2. It exercised real Unix sockets,
cross-UID rejection, malformed/oversized/version/rate guards, disposable
SIGTERM/KILL/STOP/CONT targets, guarded priority and permission rejection,
identity/protected-process checks, duplicate launches, backend restart,
idle exit, normal termination cleanup and native installation rollback.
An earlier run exposed termination reaching a Qt worker before cleanup;
blocking termination signals before Qt thread creation fixed that failure.

Local Qt 6.11.2 verification also passed:

| Executed check | Result |
| --- | --- |
| `python3 tests/check_task_manager.py` | Native accounting/control tests, all four QML views, 6,000-row model, search/sort/inspector, two lifecycles, 150% text, Reduced Motion, real binary installation/restore passed. Local IPC checks skipped because the sandbox denies SO_PEERCRED; CI ran them without that skip. |
| `python3 -m unittest discover -s tests -p test_task_manager.py` | Five integration contracts passed, including preserved Overview content hash and occupied-shortcut handling. |
| `PYTHONPATH=scripts python3 -m unittest discover -s tests -p 'test_settings*.py'` | 60 tests passed. |
| `python3 tests/check_station_tasks.py` | Production Field Station utility actions, retired routes, Overview and lock guards passed. |
| `python3 tests/check_identity.py /tmp/cedar-task-after` | Identity content, narrow/wide scaling, missing fonts, Reduced Motion and persistence passed. |
| `python3 tests/check_settings_window.py` | Window routes, resize, levels, reopening and lock passed. |
| `python3 tests/check_settings_responsive.py` | 26 Settings pages across eight sizes passed. |
| `python3 scripts/package_release.py /tmp/cedar-task-candidate.tar.gz` then `python3 tests/check_artifact.py /tmp/cedar-task-candidate.tar.gz` | Exact archive hashes, plugin artifacts, isolated fresh/repeated installation with actual offscreen shell validation, and existing recovery fixtures passed. |
| `python3 scripts/audit_public.py` and `python3 scripts/update_source_inventory.py --check` | Privacy scan and explicit source inventory passed. |

The broader `PYTHONPATH=scripts python3 -m unittest discover -s tests -p
'test_*.py'` ran 668 tests with one existing failure:
`test_cedar.Palette.test_only_theme_defines_qml_colors` finds a literal color
in unchanged `modules/CalendarConnections.qml`. Running `test_cedar.py` in an
isolated archive of the pre-task `8e81ec7` source reproduced the same failure.
The native rewrite does not alter that calendar component or weaken its test.

### Measurements and limits

The passing Ubuntu CI native check observed the following over eight seconds
with software/offscreen rendering, 150% typography and Reduced Motion:

| Measurement | Observed |
| --- | --- |
| Frontend idle CPU / RSS | 0.87% of one core / 60.77 MiB |
| Backend idle CPU / RSS | 1.37% of one core / 19.78 MiB |
| 6,000-row batch, filter, sort and selection exercise | 93 ms combined |
| Complete first window test, including restart and view checks | 8.92 seconds; this is not a cold-launch latency benchmark |

A separate twelve-sample local collector-only probe observed 1.32 ms mean,
1.62 ms maximum sample time, 0.21% of one core and 42,528 KiB peak RSS. That
sandbox exposed only four processes, so it is not a desktop-scale benchmark.
No hardware-rendered FPS, multi-hour soak, live monitor hotplug, NVIDIA driver
matrix or packaged Nix build has been certified. These remain reproducible
desktop/package verification tasks, not claimed successes.

## Signature frontend reconstruction — 2026-10-21

The standalone frontend now uses CEDAR's Strata material vocabulary across all
four views. The collector, process-control implementation, protocol, Field
Station Overview, launcher, and desktop configuration are unchanged.

### Changed files and responsibilities

| Files | Responsibility |
| --- | --- |
| `taskmanager/Main.qml` | Integrated navigation, stable chrome, keyboard shortcuts, preferences, confirmation, view lifetime and visual test sequence. |
| `taskmanager/TM.qml`, `qmldir`, `Format.js` | Small adapter over the existing palette/preferences and shared formatting; no parallel theme engine. |
| `taskmanager/Material.qml`, `LivingEdge.qml`, `grain.svg` | Retained chamfered geometry, partial inner grain contour, event-driven edge light, shared 64×64 static material texture. |
| `taskmanager/TMText.qml`, `TMHeading.qml`, `TMButton.qml`, `AppIcon.qml` | Typography, Kinetic heading resolution, focus-visible controls, genuine desktop-entry icons and neutral process fallback. |
| `taskmanager/ResourceCard.qml`, `ResourceCluster.qml` | Four compact instruments and a slim network strip. |
| `taskmanager/ProcessWorkspace.qml`, `ProcessTable.qml`, `ProcessInspector.qml` | Shared Overview/Processes workspace, virtualized rows, search/filter/sort, reversible integrated inspector and existing guarded controls. |
| `taskmanager/PerformanceView.qml`, `ServicesView.qml` | Selected-resource diagnostics and compact service inspection. |
| `native/taskmanager/frontend.h`, `frontend.cpp` | Desktop icon index, chart guides/scaling, paired network series, effects preferences, action-result semantics and test-only profiling. |
| `scripts/build_task_manager.py`, `data/source-files.json` | Include every frontend asset and imported pure policy in the release payload/build fingerprint. |
| `tools/profiling/task_manager_design.py` | Isolated before/after measurements and Wayland/offscreen capture harness. |
| `docs/TASK-MANAGER.md` | Design, validation, measurement methodology and limitations. |

### Shared design and interaction

The implementation reads the existing `themes/palettes/cedar.json`, theme
replacement and CEDAR settings through `Task.style`. It imports the actual
`components/core/StrataGeometry.js` for pane constraints and
`components/core/Kinetic.js` for typography transition policy. `Material.qml`
adapts the retained silhouette and partial inner lip studied in
`StrataBarFrame.qml`, `DropFrame.qml` and `CoreSurface.qml`; importing those
Quickshell components directly would start an incompatible shell service graph
inside this standalone application. No shared shell primitive was modified.

At the default scale, Overview instruments are 150 logical pixels high in two
columns above a 62-pixel network strip. Processes follow immediately, with a
42-pixel row, native incremental model and bounded delegate cache. CPU,
memory, GPU and storage accents come from the palette, including violet and
blue tokens. Missing sensors remain unavailable. Network upload/download use
one shared chart scale. Charts show real samples, gaps and a recent marker;
throughput scales hold their peak rather than breathing on every update.

The inspector retains its process identity and component instance while
selection changes. On wide layouts it expands into the table's right edge;
on narrow layouts it becomes an in-window bottom sheet with independent
scrolling. A local tie line follows the selected row. Controls are gated until
geometry settles. Existing PID/start identity, protection rules, pending-action
handling, priority limits and Force Stop confirmation remain intact. Only a
backend reply determines the action result.

Performance loads the selected diagnostic details on demand, including CPU
cores, memory/cache/swap, GPU/VRAM, physical storage/filesystems and interfaces.
Services exposes actual active/sub/load state and a matching expandable detail
surface. It retains the existing read-only management boundary.

Navigation, headings, search and inspector geometry use the existing nominal
120/180/220/320/200 ms CEDAR timing vocabulary with OutCubic transitions.
Telemetry numbers are stable monospaced text and do not animate per digit.
There are no ambient animation loops, new telemetry timers, per-row effects,
or full-window blur layers. The small texture is shared through Qt's image
cache. Full, Reduced and Minimal display modes are available; CEDAR Reduced
Motion and the `off` motion preset always win. The default follows CEDAR's
performance, kinetic, motion-preset and effect-intensity preferences.

Shortcuts: Ctrl+1…4 switches views, Ctrl+F reveals process search, Escape
closes the active confirmation/inspector/search, and Ctrl+W closes the window.
The process table supports arrow-key selection and visible keyboard focus.

### Reproducing visual and resource checks

Build first, then run from this checkout:

```sh
python3 scripts/build_task_manager.py
python3 tests/check_task_manager.py
python3 -m unittest discover -s tests -p 'test_task_manager*.py'
python3 tests/check_station_tasks.py
python3 tools/profiling/task_manager_design.py --native --measure --output /tmp/cedar-task-design-review
```

The native harness requires an attended Wayland/Hyprland session and permission
to connect to it. It uses private configuration, state, cache and socket paths,
floats only its fixture window, captures each view and closes cleanly. It does
not modify Hyprland rules or the installed CEDAR release. Without `--native`,
it uses software/offscreen rendering. The accessibility pass uses 150% text
and Reduced Motion. The visual sequence also exercises all five Performance
resources, service detail, inspector reversals, runtime effect tiers and
520×440 / 1180×820 / 1920×1080 / 2560×1440 / 3440×1440 logical sizes (large
sizes are offscreen only).

`--baseline /path/to/original/checkout --measure` compares isolated real
collector workloads in the selected renderer; add `--measure-only` to skip
the capture sequence. Each workload warms up for four seconds, then records
13 samples over 12 seconds. Frontend and backend CPU are reported separately
as a percentage of one logical core. RSS comes from `/proc/PID/stat`; PSS
comes from `smaps_rollup`. No shell process is included. A short sample is not
a sustained-memory, desktop-budget or FPS certification.

The self-test reports time to first delivered frame, retained QQuickItem and
process delegate counts at capture points, and median/p95 delivered-frame
intervals below 100 ms. That frame statistic excludes idle gaps and includes
test-driven captures and transitions; it is not GPU render time or a strict
animation FPS benchmark.

### Scope limits

GPU provider coverage remains unchanged: optional NVIDIA NVML, no new AMD or
Intel provider. This Intel laptop correctly reports unavailable GPU metrics.
Services remains read-only; management stays in Field Station. Desktop icons
are resolved once per launch from desktop entries and the system icon theme;
newly installed icon associations appear after reopening the application.
There is no multi-hour soak, GPU-driver matrix or physical ultrawide/monitor
hotplug certification. The redesign is implemented and built in the source
checkout; installation continues through the normal managed CEDAR updater.

### Recorded reconstruction checks

| Executed check | Result |
| --- | --- |
| Native build with installed Qt 6.11.2 | Passed. GCC reports the existing Qt `QBitArray` SFINAE header warning; no project compile errors. |
| `tests/check_task_manager.py`, outside the sandbox | Passed real IPC, malformed/version/rate rejection, disposable TERM/KILL/STOP/CONT, priority/identity/protected-process safeguards, restart, search/sort, model updates, two lifecycles, 150% text, failed collector startup, installation and rollback. |
| `test_task_manager*.py` | 8 tests passed. |
| `test_distribution.py` | 29 tests passed. |
| `tests/check_station_tasks.py` | Passed the existing Overview/utility/retired-route/lock-guard contract. |
| Native visual harness | Passed on the 2880×1800, 120 Hz Wayland display at 160% output scaling; all four screens, every Performance resource, service detail, inspector cycles, Full/Reduced/Minimal and narrow windows captured. |
| Accessibility visual harness | Passed at 150% text with Reduced Motion; 520×440 through 3440×1440 logical sizes. No QML reference/type/assignment/binding-loop errors in either harness. |
| Release inventory and whitespace | Inventory checked through a disposable Git index; user's index unchanged. `git diff --check` passed. |

In the final native capture sequence, C++ entry to first delivered frame was
210 ms. The 6,000-row batch/filter/sort/selection exercise, including the added
persistent-model-index/dataChanged/no-modelReset check, took 116 ms. The
Processes screen retained 17 delegates for roughly 402 real processes. It
contained 558 visual items both before and after five inspector close/open
cycles; these are retained-item snapshots, not cumulative allocation counts.
Across 1,220 contiguous delivered frame intervals below 100 ms, the median was
8.31 ms and p95 was 9.07 ms. Captures and transitions are included; idle gaps
are excluded. This supports responsive interaction on this machine without
claiming a universal frame-rate guarantee.

The initial matched software/offscreen measurement (four-second warmup,
12-second sample, real desktop processes, default font scale) recorded:

| Process / metric | Original | Reconstruction |
| --- | ---: | ---: |
| Frontend CPU, % of one core | 0.92% | 1.33% |
| Frontend mean RSS | 84.30 MiB | 82.99 MiB |
| Frontend mean PSS | 40.97 MiB | 39.92 MiB |
| Backend CPU, % of one core | 1.83% | 2.41% |
| Backend mean RSS | 21.25 MiB | 21.20 MiB |
| Backend mean PSS | 6.39 MiB | 6.16 MiB |

The additional visible process table costs some CPU in this short sample;
frontend memory is slightly lower. Backend source is unchanged and the two
sequential desktop workloads are not perfectly controlled. Both fixtures
released their sockets. No whole-desktop memory budget is asserted.

The subsequent native comparison used the same 880×1055 logical tiled window
on the 160%-scaled Wayland display, with the same warmup/sample method:

| Process / metric | Original | Reconstruction |
| --- | ---: | ---: |
| Frontend CPU, % of one core | 1.83% | 2.16% |
| Frontend mean RSS | 139.54 MiB | 140.28 MiB |
| Frontend mean PSS | 68.98 MiB | 70.73 MiB |
| Backend CPU, % of one core | 2.66% | 1.58% |
| Backend mean RSS | 21.06 MiB | 21.16 MiB |
| Backend mean PSS | 6.34 MiB | 6.36 MiB |

Native frontend RSS increased by 0.74 MiB and CPU by 0.33 percentage points of
one core in this sample. The backend variation again illustrates why short
sequential desktop measurements should not be treated as controlled CPU
regression benchmarks. Both native fixtures closed and released their sockets.
The four finished native screenshots, narrow inspector, service detail,
validation logs and raw comparison JSON were saved locally under
`~/Pictures/cedar-task-manager-redesign/`.
