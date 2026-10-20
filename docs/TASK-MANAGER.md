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

Hardware NVML, monitor changes, compositor focus, fractional scaling and
long-duration rendering require a real desktop session. Service management
is intentionally read-only. Hierarchical process trees and per-application
icons are not implemented; grouping uses executable identity and the inspector
has a generic process icon.
