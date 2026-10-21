# Runtime performance budget and measurement contract

CEDAR uses a **500 MB total runtime PSS ceiling**, with preferred idle/daily/
fully-active targets of **250 / 350 / 450 MB**. MB means 1,000,000 bytes; MiB
means 1,048,576 bytes. These are acceptance targets, not claimed measurements.
The current acceptance status is in [performance results](performance-results.md).

## Scope and ownership

Count the shell's Quickshell process, every CEDAR-owned persistent helper,
feature worker and short-lived action observed during the workload, detached
Task Manager frontend/collector, wallpaper/keymap windows, managed-session
supervisors, and CEDAR-specific task/performance/theme services when running.
Brain is not bundled as a daemon in this tree; explicitly add its roots/cgroups
and label the result if a separate Brain installation participates.

Exclude unrelated applications, the compositor, shared system services
(PipeWire, NetworkManager, UPower, polkit), test controllers and profilers.
Report relevant external services separately. Do not include all `qs` or
`python3` processes merely because CEDAR uses those executables. Conversely,
a process-tree-only sum misses independently launched or reparented workers.
See [architecture](architecture.md) for ownership and executable paths.

Before measuring, inspect `ps`, Quickshell instances, systemd user services and
`/proc/PID/cgroup`; resolve the installed release and identify every active
CEDAR entry point. Supply explicit root PIDs, exact cgroup-v2 paths, and release
source directories. Review the resulting `processesDetail`/`scopeReason` fields.
Remove unrelated applications from the chosen scope instead of silently
attributing them to CEDAR. Source discovery supports common direct Python,
Quickshell and native launches; `qs -c`, `python -m/-c`, arbitrary wrappers and
unreadable metadata require explicit roots/cgroups. Detached services outside
the selected scopes cannot be inferred reliably.

## Accounting

`scripts/measure_resources.py` is an opt-in stdlib diagnostic. It records:

- Per-process identity `(PID, start ticks)`, name, parent, scope reason, RSS,
  PSS, private clean+dirty+private-hugetlb bytes, swap PSS and RSS high-water mark.
- Summed PSS as the primary physical-memory budget, RSS sum (which double-counts
  shared pages), private sum, process count, observed process identities, and CPU
  deltas normalized so 100% is one logical CPU.
- Sampled peaks, first/last-decile median change, least-squares PSS trend, missing
  memory readings, optional process-count violations, and cgroup current/peak
  counters separately.

Linux divides a shared page among its mappers in PSS. `smaps_rollup` sums the
mapping fields for a process. This makes group PSS more useful than summed RSS,
although sharing with processes outside the group still affects it. See the
[kernel proc documentation](https://www.kernel.org/doc/html/latest/filesystems/proc.html).
Cgroup memory also charges page cache and kernel allocations, so it is **not**
an interchangeable PSS figure; see the
[cgroup-v2 documentation](https://www.kernel.org/doc/html/latest/admin-guide/cgroup-v2.html).

Samples are not atomic. Between-sample peaks, very short-lived subprocesses and
their CPU time can be missed. VmHWM and cgroup `memory.peak` are lifetime counters,
not necessarily peaks of this workload. GPU/driver memory needs separate tools.
Never sum overlapping cgroup counters. A PSS slope across startup/lock/workload
changes is not proof of an unbounded leak. Compare warmed equivalent phases,
repeat cycles, then investigate retained objects/mappings and cleanup behavior.

An empty scope, missing PSS, vanished explicit root or PID reuse cannot yield a
passing budget. `--fail-on-budget` exits nonzero for exceeded **or unknown**
accounting after saving evidence. No enforcement kills/restarts CEDAR or changes
its cgroup limits. Sampling is bounded to 10,000 observations and disabled during
ordinary shell operation. Files are written atomically into a private directory;
raw command lines are classified in memory and are not written to reports.

## Reproducible procedure

Create a private results directory first, or let the collector create it. Replace
PID, release and cgroup with the **inspected** values for the session:

```sh
python3 scripts/measure_resources.py \
  --pid PID \
  --cgroup /user.slice/user-UID.slice/user@UID.service/app.slice/cedar-shell.service \
  --source-root /absolute/path/to/installed/release \
  --output /private/results/idle.json --label idle \
  --warmup 120 --seconds 600 --interval 5 --runs 3 --fail-on-budget
```

Use a fresh report for each scenario, recording source revision, renderer,
displays/scale/refresh, feature settings, initial session state, workload times,
and explicit exclusions. A 60-minute soak uses `--seconds 3600 --runs 1`; an
optional four-hour soak uses `--seconds 14400 --interval 10 --runs 1`. Observe
process membership throughout. Run the same protocol before and after on the
same environment. Reports are private evidence; commit sanitized aggregates.

`tools/profiling/surface_stress.py` creates a disposable copy, private XDG state,
real production QML components and a loader lifecycle loop. It covers 15 Canopy
topics plus Field Station, Signals hub, Shield/Profile/Station content, alternating
480/960-pixel widths and reduced motion. It checks shared visualizer/window
registry cleanup and records per-process PSS during load/close/settle. It does
not perform real Shield changes or replace the installed shell.

```sh
python3 tools/profiling/surface_stress.py --source /path/to/baseline \
  --cycles 200 --hold-ms 300 --settle-seconds 15 --output /private/results/before.json
python3 tools/profiling/surface_stress.py --cycles 200 --hold-ms 300 \
  --settle-seconds 15 --output /private/results/after.json
```

The default is software/offscreen. `--native` opens a disposable Wayland window;
this requires an unlocked graphical session. Backend test-mode fixtures, a
single floating window, and responsive width tests do not establish full-shell,
monitor hotplug, real profile/Gaming changes, or hardware memory acceptance.
Read `closedAfterFirstSweep` separately from startup's allocation growth. The
ready marker includes a deliberate one-second harness delay and is **not** the
shell's startup-to-bar latency or a frame-time measure.

Focused checks: `tests/check_service_lifecycle.py` exercises busy-request
completion, polling demand and real helper restart/disable cleanup;
`tests/check_wallpaper_memory.py` measures the production picker with large
synthetic images; `scripts/benchmark_release_validation.py` isolates release
hash/inventory allocations. Existing `scripts/audit_resources.py` produces a
static timer/process/file-watcher ledger. A static site is not proof of runtime
activity. Keep all heavy tools outside the ordinary startup path.

## Required matrix and release gates

Record startup; ten-minute idle; daily bar/Signals use; Field Station; repeated
surfaces; multiple outputs; Profiles/Gaming; Task Manager; theme/wallpaper changes;
60-minute and, when feasible, four-hour soaks. For each, report group PSS/RSS/
private bytes, sampled/cgroup peaks, CPU, process count/churn, retention/trend,
errors/warnings, interaction latency and rendering/frame timing **when measured**.
Mark unavailable metrics as not measured, never zero. Standard/high-refresh
pacing, monitor topology changes, lock/PAM and recovery require controlled native
sessions; fixture passes are separate evidence.

Every persistent timer needs a documented purpose, activation/stop predicate,
non-overlap and retry policy. Every process needs an owner and cleanup contract.
Every significant optimization needs an equivalent before/after workload and
regression checks. If a budget is exceeded, identify and reduce/defer unnecessary
work, retest, and leave the acceptance gate open until repeated evidence passes.
