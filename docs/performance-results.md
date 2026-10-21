# CEDAR audit measurements — 2026-10-20/21

**The 500 MB acceptance threshold has not been met.** The installed release
exceeded it during a 60-minute observation that included approximately 50
minutes locked, and with the Task Manager collector and offscreen frontend
active. The source improvements
below are committed on `audit/security-performance-2026-10-20`; they have not
been deployed to the user's running shell. Fixture savings are not evidence
that the installed desktop now meets its budget.

## Provenance and accounting

Source baseline: `058aace7c8da6be810350557a8d65e58077caed3`, extracted through
`git archive` into a separate directory. Installed runtime: release
`1.15-81f0f1f9bd0424f6`. Measurements used the same laptop, Linux
`7.2.5-3-omarchy`, Quickshell `0.3.1-1`, Qt base `6.11.2-3` and declarative
`6.11.2-1`. The physical display was 2880×1800 at 120 Hz, scale 1.6. Native
checks used the existing threaded render loop. Software/offscreen fixtures
are identified separately; neither their memory nor timing describes native
GPU rendering. No display settings, firewall, DNS or session authentication
settings were changed for these tests.

The installed group comprises the managed Quickshell process, its CEDAR
default-apps/network/Core-probe helpers, clipboard watcher when unlocked,
and observed transient CEDAR control helpers. Explicit root identity,
`cedar-shell.service` cgroup and installed source ownership were inspected;
observed descendants remain tracked after reparenting. Task Manager adds its
independent frontend and actual `cedar-taskd`. No CEDAR Brain process was
identified. Hyprland, the separate voice-typing Quickshell, browsers and other
applications are excluded. Contemporaneous Hyprland PSS was approximately
131.5 MB and the voice-typing shell 118–124 MB; these contextual snapshots
are not attributed to CEDAR.

PSS is summed from `/proc/*/smaps_rollup`; RSS and private clean+dirty memory
are supplementary. All MB in the tables are decimal, one million bytes.
CPU percentages use one logical core as 100%. Samples are not simultaneous
across processes and may miss short peaks or short-lived workers. RSS double
counts shared mappings. GPU allocations outside these mappings are not fully
represented. Cgroup memory also charges cache/kernel memory: the observed
shell cgroup peak reached about 772 MB and cannot be substituted for PSS.
See [accounting contract](performance-budget.md) for discovery limitations and
commands. Private raw reports retain per-process identities; the accompanying
[sanitized evidence](audit/2026-10-20/measurements.json) omits machine paths,
command lines, credentials and personal identifiers.

## Installed runtime observations

| Workload | Samples | PSS median / peak MB | Peak summed RSS / private MB | CPU median / max % | Max processes | Samples over 500 MB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| First 10 minutes, observational desktop | 120 | 359.71 / 376.28 | 506.20 / 347.13 | 0.60 / 4.18 | 5 | 0 |
| 60-minute soak, approximately 50 minutes locked | 716 | 504.27 / 530.30 | 684.99 / 501.91 | 0.79 / 5.78 | 6 | 405 |
| 10 minutes after unlock, mixed normal activity | 119 | 471.36 / 479.86 | 609.66 / 449.91 | 3.18 / 6.72 | 5 | 0 |
| Installed shell plus real Task Manager, 30 seconds | 29 | 523.79 / 524.23 | 721.39 / 481.90 | 7.71 / 9.62 | 7 | 29 |

The first two runs began at 23:02:13–14 UTC on October 20 and sampled
every five seconds. The 60-minute run contains 3600 seconds of measured
monotonic elapsed time. The user's later report establishes approximately
50 minutes locked; exact lock-transition times were not recorded. The later
lid-closed period is a separate condition. These earlier files did not record
CLOCK_BOOTTIME, so they cannot quantify suspension or wall-clock adjustments.
Future closed-lid runs should enable the sampler's clock metadata.

During the soak the five-minute median group PSS values were 359.73, 359.67,
452.22, 460.42, 502.79, 506.57, 504.57, 504.43, 505.50, 505.12, 505.25 and
505.83 MB. First/last-decile difference was +146.10 MB. This is a clear budget
violation and state-dependent retention, **not proof of an unbounded leak**:
the later portion largely plateaued and the lock state changed. Thirteen
process identities were observed across the hour, mostly persistent helpers
and brief refresh workers; no monotonically increasing live process count was
observed. The last shell itself held 472.07 MB PSS and 447.99 MB private memory.
Anonymous mappings dominated a later inspection, but mapping classes alone
cannot assign them to QML objects, textures or allocators.

The after-unlock run began at 00:34:02 UTC on October 21 and included ordinary
activity. Its first/last-decile delta was +74.16 MB. It is not a controlled
idle comparison or evidence of a regression introduced by this branch. The
installed release was unchanged throughout.

Task Manager used a private offscreen frontend with its real read-only
collector, alongside the observed installed shell. All 29 samples included
both frontend and collector. Their median PSS was 45.51 MB and 6.91 MB,
respectively. Both exited and their private sockets disappeared after close.
No process-control action was issued against the live desktop. This combined
group already exceeds the hard threshold; a Task-Manager-only number would
hide that failure.

No frame-time or response-latency trace was collected for these observations.
A query of the shell's systemd journal for the initial soak returned no
entries; internal Quickshell logs were not exhaustively parsed, so an error
count of zero is **not established**. No visual observation was possible
during the user's unattended locked period.

## Measured changes in isolated workloads

### Wallpaper decode bounds

`tests/check_wallpaper_memory.py` loads six generated 4096×2304 wallpapers
through the production grid, replacing only its window host for offscreen
execution. Five open/close cycles run against baseline and changed source;
memory is sampled every 50 ms and at phase markers. Thumbnail dimensions now
follow displayed size and device-pixel ratio, and decoded images do not enter
the shared image cache.

| Measurement, 1× scale | Before MB | After MB |
| --- | ---: | ---: |
| First-open PSS | 333.46 | 96.80 |
| Sampled peak PSS | 333.38 | 130.29 |
| Sampled peak RSS | 384.76 | 182.06 |
| Sampled peak private memory | 322.96 | 120.77 |
| Closed PSS range over five cycles | 93.62–94.45 | 96.29–97.32 |

First-open PSS fell 71%; sampled peak PSS fell 61%. Phase markers and periodic
samples occur at different instants, hence their small peak discrepancy.
Closed-state retention did not improve: allocator/cache retention remains
approximately 94–97 MB. A changed-source 2× scale run completed five cycles
with sampled peak PSS 185.76 MB; no equivalent baseline 2× reduction is claimed.
These fixtures exclude the rest of the shell and native GPU allocations.

### Service lifecycle and release verification

`tests/check_service_lifecycle.py` demonstrated these changes with the same
fixture against baseline and changed services:

| Condition | Before | After | Interpretation |
| --- | ---: | ---: | --- |
| Calendar debounce wakeups while its request is busy, 650 ms | 6 | 1 | Wait for completion; deliver latest month without spinning. |
| Unrelated Canopy-topic control polls, accelerated 650 ms window | 3 | 0 | Only actual quick controls/power consumers maintain the poll; production cadence remains 10 s. |
| Core-probe heartbeats after retry then disable, 350 ms | 7 | 0 | Preserve the `running` binding so disabling owns process shutdown. |

Floating Settings power controls and re-enabling the probe also passed.
The fixture waited through the real 15-second retry. It reports expected
offscreen/sandbox IPC diagnostics; those are not hidden as clean native logs.
These counts establish eliminated work, not a measured percentage reduction
in whole-shell CPU.

`scripts/benchmark_release_validation.py --reference eb60f2c` performed three
runs per version on a 64 MiB synthetic asset. Streaming inventory hashing and
an 80-byte LFS-prefix read reduced peak traced Python allocations from
67,110,577–67,110,633 bytes to 395,159 bytes. Worker maximum RSS fell from
89.70–93.77 MB to 22.82–22.97 MB; median duration was 26.04 ms before and
17.23 ms after. All six digests matched. This measures transient release
validation, not runtime shell memory. Git-archive extraction also now streams
through a private temporary file with explicit member/byte bounds.

### Repeated surfaces

`tools/profiling/surface_stress.py` uses production QML with isolated test-mode
backends. It exercises 15 Canopy topics plus Field Station, Core Hub, Shield,
Profiles and Station pages, 200 open/close cycles, alternating widths and
reduced-motion policy, then a 15-second settle. Closed samples after the
first complete feature sweep distinguish initial cache population from later
retention. The same harness runs three alternating baseline/changed pairs.
All six runs completed their assertions, 1,200 total cycles:

| Variant/run | Median / peak PSS MB | Peak RSS / private MB | Median CPU % | Warm closed PSS delta MB | Complete PSS |
| --- | ---: | ---: | ---: | ---: | --- |
| Before 1 | 120.66 / 135.91 | 206.07 / 117.87 | 6.56 | -0.13 | Yes |
| After 1 | 122.55 / 137.68 | 206.30 / 120.00 | 6.67 | -3.29 | No: one transient helper |
| Before 2 | 122.82 / 137.18 | 205.50 / 119.26 | 7.20 | +0.23 | Yes |
| After 2 | 122.77 / 138.30 | 207.71 / 120.45 | 6.51 | -0.92 | Yes |
| Before 3 | 122.00 / 138.16 | 206.28 / 120.26 | 7.10 | +1.16 | No: one transient helper |
| After 3 | 120.16 / 133.18 | 202.11 / 115.89 | 7.16* | +1.68 | Yes |

These results show **no consistent broad reduction** in surface memory or CPU.
Each run saw at most five processes, including short-lived read-only fixture
helpers. After-1 and before-3 each lost a transient `bash` process between
enumeration and reading PSS; their budget status is correctly `unknown`.
All warmed closed sample sets were complete. The small positive and negative
retention differences over roughly 2.5 minutes do not establish leak freedom.
*After-3 overlapped a separate short offscreen Trailwatch investigation; its
CPU and shared-page PSS must not be used for a causal speedup comparison.*

Each run logged five platform/offscreen warning lines and one unavailable
PipeWire error, despite zero assertion/binding errors. After-1 additionally
logged two objects still incubating at engine destruction. The original
`warningLineCount` field aggregates WARN and ERROR lines; exported evidence
and future reports separately count them. These are not zero-error native runs.
This is not full-shell startup, live profile switching, native frame pacing or
monitor hotplug; the harness-ready delay intentionally includes a one-second
timer. Recorded CPU peaks and full sample summaries are in the evidence file.

### Lock scene investigation

A separate disposable Trailwatch preview at 1920×1200 logical pixels, 1.5×
scale, software/offscreen rendering and test-mode backends measured three
create/inactivate/destroy cycles. Empty-fixture PSS was 91.45 MB. Active PSS
was 223.01, 225.07 and 221.92 MB; making the view inactive while retaining it
left 224.49, 221.22 and 221.25 MB. Destruction reduced these to 154.64,
148.92 and 149.65 MB; optional explicit fixture GC further reduced them to
145.98, 138.62 and 135.07 MB. Explicit GC is a diagnostic, not a production
change. The first scene creation added 131.56 MB; there was no accumulating
trend across these three cycles.

The instantiated tree contained 1,895 visual items, 306 effectively visible,
with 12 Complications retaining six kind-specific layouts each. Two Canvas
items were full 1920×1200, with another approximately 1607×1607 and one 846×846.
This makes deferred responsive/kind layouts a concrete follow-up candidate;
it does not attribute all memory to those objects or certify a native saving.
The exploratory fixture used an authentication stub and saw sandbox IPC,
PipeWire and compositor availability diagnostics. It did not run the real
lock protocol. Its source and raw results remain private diagnostic artifacts;
sanitized phase readings are included with the evidence. Production lazy
loading needs native pixel, focus, authentication and multi-monitor tests
before changing lock construction or lifetime. No such change was applied.

### Rejected rendering optimization

A candidate reduced `CedarAtmosphere`'s full-height Canvas to its painted
155-pixel strip. It saved about 27.9 MB PSS in a software fixture and passed
offscreen pixel comparisons. At native 1.6× scaling, comparison found 14,971
different image channels (maximum difference five); the theme-repaint
comparison also differed. An alignment adjustment did not preserve exact
output. The production change and its candidate-specific assertion were
reverted in `964c410`. **That memory saving is not delivered.** The original
native lifecycle suite passed after reversion. No pixel tolerance was weakened.

## Verification matrix and remaining gates

| Requested scenario | Evidence from this audit | Still required |
| --- | --- | --- |
| A. Fresh startup | Isolated source, QML and native Task Manager startup/lifecycle fixtures | Restarted full-shell before/after startup PSS and responsiveness |
| B. Idle 10 minutes | 120-sample initial observation | Controlled idle repeated with deployed candidate; preferred 250 MB target missed in observed group |
| C. Everyday bar/Signals | Observational runtime and Core/Canopy regression suites | Deployed comparable interactive workload; preferred 350 MB target missed |
| D. Field Station | Production-content offscreen stress and station/task regression suites | Representative live content and native group PSS |
| E. Repeated surfaces | Three paired 200-cycle fixtures; separate five-cycle wallpaper tests | Long native object/allocator traces for locked-state growth |
| F. Multi-monitor | Geometry/lifecycle fixtures; one real 120 Hz display at 1.6× | Physical second display, hotplug and 60 Hz vs 120 Hz frame-time comparison |
| G. Profiles/Gaming | Restoration/policy/backend failure fixtures and QML suites | Isolated real-host mode transitions, external-edit recovery and group peaks |
| H. Task Manager | Real native collector, IPC/actions in disposable tests; combined 30-second PSS run | Native full interaction budget, longer active soak; combined run failed 500 MB |
| I. Themes/wallpapers | Palette, Canvas invalidation and thumbnail fixtures | Live theme/wallpaper switching group peak and GPU trace |
| J. Extended soak | 60-minute installed observation with locked-state context | Deployed 60-minute repeat and 4-hour soak with suspend accounting |

Final source validation passed **748 Python tests** with
`python3 -m unittest discover -s tests -p 'test_*.py'` (49.94 seconds). Baseline
had 670 tests and one pre-existing calendar color-contract failure; exact
colors were retained when ownership moved to Theme. Both JavaScript geometry/
transition suites and all seven Notes test files passed. Already executed
QML suites include motion, Canopy,
Strata, Core host/persistence, profiles, gaming, Shield, Station/tasks, theme
palettes, lock wiring/auth fixtures, Trailwatch, settings, optional backends,
bridge lock and permission handling. The native frontend lifecycle suite
passed at 120 Hz/1.6× before the latest lid-close; it emitted one teardown
warning about 44 objects still incubating. That warning remains a diagnostic
finding, not a proven leak. No native tests are run through the user's lock.

Final headless reruns of service lifecycle, Shield, Calendar and Settings
window passed. `qmlformat` 6.11.2 parsed all eight changed production/harness
QML files; targeted `qmllint` completed with existing unqualified-access and
Quickshell metadata warnings. Python compilation, POSIX bootstrap/Bash syntax,
source inventory and publication privacy scans passed. The privacy scan is
for current release inputs; Git history needs its own review. New security,
sampler and service-lifecycle regressions were added to CI; remote CI was not
run during this local audit.

The native Task Manager suite passed with real same-user socket IPC, guarded
actions on disposable processes, 6,000-row frontend behavior and cleanup.
Different-user peer rejection was not executed because its root-client gate
was not enabled. Real desktop actions, PAM and privileged policy changes were
not performed. `scripts/package_release.py` and `tests/check_artifact.py`
passed for the complete 680-file candidate: archive hashes/plugin inventory,
spaces/non-ASCII extraction paths, simulated Trial/Keep/login/restore and
interruption recovery, plus actual fresh and repeated installation with
offscreen QML validation into isolated XDG directories. External desktop
responses are simulated; this does not establish a real login/reboot handoff
or fresh-system package bootstrap. No release was published or activated.

Acceptance remains blocked by the observed memory violations, lack of a
deployed comparable after-run, unsigned publisher trust policy, incomplete
verification of runtime-only firewall/DNS restoration, and unexecuted physical
display/authentication/reboot gates. Security fixtures test failure handling;
they do not certify real privileged operations or absence of vulnerabilities.
See [security model](security-model.md) and [remediation backlog](refactoring-audit.md).
