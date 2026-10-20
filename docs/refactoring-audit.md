# Security, performance and architecture refactoring audit

Audit opened 2026-10-20 on dedicated branch
`audit/security-performance-2026-10-20`, from
`058aace7c8da6be810350557a8d65e58077caed3`. This document separates observed
source findings, implemented changes and verification gaps. Historical test
counts and resource figures in older documents are not results of this audit.

## Baseline established before refactoring

- Inspected actual entry points, release inventory, QML registries, shared
  services, native Task Manager, compatibility supervisors and installer/update
  code. [Architecture](architecture.md) records the dependency and process map.
- Existing architecture already uses shared audio/network/media/telemetry
  providers, request timeouts, lazy app surfaces, bounded transaction state and
  motion policy. Preserve these rather than replacing them wholesale.
- The baseline has 250 QML files (30,027 lines), 31 JavaScript files (3,728
  lines), 188 Python files (27,615 lines), four C++ translation units (583 lines),
  including tests. These are source-size indicators, not runtime object counts.
- Existing `scripts/audit_resources.py` records static resource sites and their
  ownership. Existing `measure_resources.py` records explicit root PIDs and
  descendants; it does not automatically include detached CEDAR tools and its
  baseline output lacks per-process private-memory history. Measurement scope
  must be made explicit before accepting a memory figure.
- `docs/PERFORMANCE.md` records an earlier 747 MB combined PSS observation and
  GPU-driver/background-surface costs. That evidence makes full-group/native
  measurement a priority, but cannot establish current usage or a current leak.

## Prioritized findings and remediation backlog

Status at initial triage; subsequent implementation entries below supersede
these starting statuses. A candidate is not a confirmed exploit or leak.

| ID | Priority / evidence | Required response | Initial status |
| --- | --- | --- | --- |
| PERF-01 | P1: process-tree-only accounting omits independently launched wallpaper/keymap/Task Manager and detached services; budget acceptance requires summed group PSS | Explicit process ownership/identity discovery, RSS/PSS/private samples, detached-root inclusion, repeated equivalent workflows and failure if readings are incomplete | Measurement gap; no 500 MB acceptance claim |
| PERF-02 | P1: `modules/WallpaperPicker.qml` image delegates use original images and `cache: true` without `sourceSize`; user libraries can contain very large images | Limit decode dimensions to display needs with scaling considered; compare peak/retained memory and visual thumbnails; preserve standalone picker behavior | Confirmed unbounded decode dimensions; impact not yet measured |
| PERF-03 | P2: `Controls.qml` runs `control.py snapshot` every 10 s for every `canopy` route; `control.py` runs power-profile list/get and nightlight commands | Narrow visible demand to actual control consumers; prefer the existing native PowerProfiles state where compatible; preserve transactions and external changes | Confirmed avoidable broad trigger |
| PERF-04 | P1: native Wayland driver allocations and per-output surfaces may dominate PSS; Canopy is a wide transparent window and backgrounds allocate by output | Measure mappings and peak PSS on actual display/RHI configurations before choosing surface or renderer changes | Investigation; historical evidence only |
| LIFE-01 | P1: optional worker exits, timeout paths, rapid reopen and dynamic helper objects require repeated testing | Stress panels, request failures and Gaming helper destruction; verify no surviving owned workers or unbounded models | Verification gap; no verified leak declared |
| LIFE-02 | P2: Field Notes is intentionally resident for undo history/pre-open IPC; hiding does not release its document/canvas objects | Exercise maximum supported sheets/strokes/history, measure retention and document bounded behavior; retain undo compatibility | Intentional lifetime, needs memory evidence |
| ARCH-01 | P2: ShellState ↔ Canopy/SettingsService and Config ↔ VisualQuality references couple configuration/routing/policy | Clarify existing ownership and narrow dependencies only around measured defects; test construction/reload/order behavior | Reference cycles documented, not evidence of binding loop |
| ARCH-02 | P2: two reachable wallpaper UIs and native/shell telemetry overlap | Reuse compatible pure data/thumbnail behavior; preserve independent Task Manager diagnostic role and fallback UI contracts | Behavioral comparison required |
| ARCH-03 | P3: large Go/notes/CoreSources/Shield QML files mix rendering, routing or adapters | Extract cohesive logic only with test seams and concrete maintenance benefit; retain public types/paths | Backlog; no cosmetic split planned |
| SEC-01 | P0 review surface: updater/bootstrap source authorization, archive paths, integrity metadata, symlinks, current-release pointer and journals | Review hostile input and concurrent-file cases; add focused regressions for verified defects; validate failed-update rollback | Security audit in progress; no blanket security claim |
| SEC-02 | P0 review surface: lock/PAM/polkit, task signals, Shield DNS/firewall, Gaming restoration, local IPC | Validate identity/privilege/lock guards and bounded inputs; test failures without applying real security settings to the user's desktop | Security audit in progress |
| TEST-01 | P1: same-environment baseline/after, 10-minute idle, 60-minute soak, high-refresh/native multi-monitor and recovery evidence required | Record executed and unavailable scenarios separately; publish comparable raw summaries and unresolved blockers | Acceptance incomplete pending evidence |

Priority P0 denotes a security/critical correctness review priority, not a
finding of exploitability. Confirmed defects must receive reproduction details,
severity and a fix or explicit blocker in [security model](security-model.md).

## Important behavior to preserve

- `SessionIntegration`'s one-second timer checks a five-second supervisor
  freshness deadline and fails closed. It is a lock safety watchdog, not a
  decorative idle loop; removal requires an equivalent fail-closed deadline.
- Field Notes retains undo state by design. Unloading it merely to lower an idle
  snapshot would change functionality.
- `Transaction`, `Overrides` and profile/Gaming restore logic preserve external
  edits and nested ownership. Replacing them with unconditional reset commands
  would break recovery semantics.
- Task Manager deliberately runs independently of Quickshell. Reparenting or
  embedding it solely to simplify measurement would reduce fault isolation.
- Motion uses a shared rest/reduced-motion policy. Functional transitions and
  permanent ambient loops have different requirements; disabling animation
  globally is not an acceptable optimization benchmark.
- Source inventory, release paths, root QML imports and public CLI/IPC routes are
  installed compatibility contracts. Update inventory after adding tracked
  release files; exercise packaging and rollback tests after structural changes.

## Controlled implementation and review record

Keep each change small and reviewable. For each implemented item record:

1. Original defect and source evidence, including reproduction where possible.
2. Correction and why it addresses the mechanism.
3. Existing API, installed layout, privilege and animation behavior preserved.
4. Exact regression/benchmark commands and whether they actually ran.
5. Before/after measurements, or explicitly "not measured".
6. Remaining limitations and related backlog IDs.

The initial architecture documentation changes only describe inspected code and
define review boundaries. They do not move files, start services, alter settings,
or claim a performance gain. Validation: paths and references were compared with
tracked files; registries/entry points and the feature owners above were read.
No UI test or runtime resource test is represented by that documentation check.

Implemented fixes and their evidence should be added here as they land; detailed
resource comparisons belong in [performance results](performance-results.md),
budget/accounting rules in [performance budget](performance-budget.md), and
trust boundaries/security limitations in [security model](security-model.md).

## Unresolved acceptance gates

Acceptance remains conditional until the results document records the relevant
executed checks. In particular, a unit-test pass cannot establish native frame
pacing, a short smoke run cannot establish soak stability, an offscreen sample
cannot establish GPU memory, and one process's RSS cannot establish the group
PSS budget. Unavailable hardware/scenarios must be labelled untested and remain
in the backlog. Do not convert an unobserved leak into a claim of leak freedom.

## Continuous engineering rules

Future CEDAR changes follow these rules:

- Reuse a service already owning a system capability before adding a daemon or
  independent polling loop. Document an exception such as diagnostic isolation.
- Give every persistent timer a purpose, interval justification, activation
  predicate, stop condition and retry bound. Security freshness timers need an
  explicit fail-closed policy.
- Give every long-lived process an owner, shutdown/restart policy and memory
  accounting rule, including detached processes and descendants.
- Define each feature's state owner, data source, permission boundary, visible
  and hidden lifecycle, model/cache bounds and test seam before expansion.
- Use structured arguments, bounded responses and request timeouts. Validate
  paths/identities at the privileged or destructive boundary; do not rely on a
  disabled button as authorization.
- Preserve installer/release/recovery contracts with changes to file layout,
  entry points, configuration ownership or dependencies.
- Measure significant optimizations with a recorded same-environment baseline,
  workload, group scope and sampling limitations. Heavy diagnostics are opt-in.
- Investigate resource regressions before merging; do not hide them through
  process omission, arbitrary killing, globally removed effects or changed
  workloads.
- Keep fixture tests, offscreen UI tests, native integration checks and prolonged
  measurements distinguishable. Only report performed tests as passed.
