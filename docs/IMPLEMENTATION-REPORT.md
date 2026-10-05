# Candidate 12 implementation and verification

This implements changes in the distribution checkout, based on the implementation master prompt. It is not a claim that all desktop acceptance gates passed. The running personal configuration was identified as a separate source tree and left untouched. The local handoff, machine baseline, logs and screenshots are excluded from the release inventory.

## Changed behavior and implementation

| Area | Implemented change | Evidence and boundary |
| --- | --- | --- |
| Buttons and rows | Shared spacing/control/focus tokens; no hover color or geometry change; inset keyboard focus; compact setting rows below 560 logical pixels | Real offscreen Qt pointer, keyboard, pressed, disabled and text-scale checks |
| Dropdowns | Pure finite-validated placement; flip/clamp inside the containing overlay; bounded scrolling; reclamp on relevant size changes | Actual Qt Controls popup plus randomized geometry checks. This is an in-window popup, not a claim about native layer-shell popup anchoring |
| Views | Asynchronous, visibility-gated Go, Settings, Field Station and Canopy content; bounded inner transitions; no animated native window geometry | 100 Settings and 100 Go creation/destruction cycles. Field Station native host placement remains untested |
| Settings | Desktop Setup page with six steps; wide sidebar and narrow navigation; application priorities and expandable remaining roles | Same `scripts/setup.py` planner/executor as the terminal. Isolated preview disables desktop mutation |
| Drafts | Input draft, base revision and conflict state belong to `DesktopSettings`, outside page lifetime; no-op input changes do not regenerate config | Unit/Qt checks; other existing page-local dirty drafts remain retained rather than being discarded |
| Applications | One GIO catalog subscription before snapshot; hidden events mark dirty; cached search descriptors; stable Go row IDs; GIO launch by desktop ID; missing entries produce a visible error | Real temporary desktop entries exercise Unicode arguments and working directories. AppInfoMonitor test exercises hidden changes and rearming. D-Bus activation/terminal emulator combinations still need native acceptance |
| Defaults | Typed desktop targets, preserved explicit legacy commands, unchanged-association no-op, private backups, unique atomic editor wrapper and readback | File bytes/mtime and no-write tests; real system defaults were not changed |
| Networking | One NetworkManager event stream, coalesced updates, visible detailed snapshots, stable AP/profile rows, vanished selection clears password, AP capability plus disconnect consent for hotspot | Model/selection tests and controlled service responses. Live radio, enterprise authentication and NetworkManager policy prompts remain unverified |
| Bluetooth | Native import behind a URL Loader; unavailable module leaves the shell running; closing controls stops discovery | Actual injected missing-import QML test; native adapter/pairing lifecycle not certified |
| Telemetry | One in-flight batch; fast 2 s visible / 10 s ambient; temperature 5 s visible / 30 s warning demand; disk/uptime 30 s; monotonic rates, timeout and backoff | Scheduling and existing UI tests. No measured CPU, RAM or refresh-rate improvement is claimed |
| Handoff | Pure versioned plan/digest; candidate fingerprint, process/session evidence and explicit role choices; reinspection after approval; durable supervisor ACK before suppression; IPC generation check | Existing full trial/Keep/login/restore workflows plus stale-evidence and acknowledgment tests, with external desktop interfaces simulated |
| Journals | Durable per-operation states and per-file before/after hashes; uncertain outcomes reconciled from evidence; commit refuses unverified operations; existing insecure private directories are rejected without chmod | Real interrupted atomic-write restoration and later-edit conflict tests. Package changes remain outside dotfile rollback |
| Discovery | Bounded `.conf` include graph with cycles/variables; literal Lua includes without evaluating code; one managed package query; Caelestia/Ryoku read-only versioned descriptors | Fixture evidence only. Managed-shell takeover is explicitly not implemented without installed-version startup, updater and lock review |

`services/SetupFlow.qml` holds setup state independently of its page. The UI shows proposed roles, the resulting hybrid mode and the exact login target before approval. A retained Noctalia lock/idle/wallpaper host is not called a complete replacement. `cedar status` reports trial versus kept state separately from ownership mode. Authentication, secure-unlock evidence, sleep coverage, notification ownership and later-edit protections remain authoritative.

The palette, six bar styles, consolidated center navigation, explicit OSD visibility, offline ROOTED/About Scripture and legacy migration contracts remain in the existing implementation. No active desktop, PAM file, compositor settings or personal preferences were modified to obtain test results.

## Reproducible checks

From a checkout or extracted candidate:

```bash
python3 -m unittest discover -s tests
python3 tests/check_controls.py
python3 tests/check_optional_backend.py
python3 scripts/audit_public.py
python3 scripts/package_release.py /tmp/cedar-development.tar.gz
python3 tests/check_artifact.py /tmp/cedar-development.tar.gz
```

GIO execution tests explicitly skip when Python GIO bindings are missing. Quickshell checks require a compatible installed runtime and run offscreen in disposable XDG locations. CI runs source/recovery/archive checks; it must not be described as a native desktop runner. See `LOCAL-VERIFICATION.md` for the results actually obtained.

## Resource evidence

`scripts/audit_resources.py OUTPUT` produces a private static resource ledger from the exact release inventory. Reviewed shared services include consumers, cadence, shutdown/retry and bounds. Other sites are explicitly marked for individual review. Static occurrences do not count live allocations and are not a completed runtime cost audit.

`scripts/measure_resources.py --pid PID --output OUTPUT` samples explicit process roots and their descendants, verifying PID start identities and using monotonic time and `SC_CLK_TCK`. Defaults are three runs, each with 120 seconds warmup and 180 one-second samples. CPU normalization is 100% for one logical CPU; RSS sums can double-count shared memory and PSS is reported separately when readable. Sampled helper starts are a lower bound; detached services require explicit additional `--pid` arguments.

No comparable native before/after runs were performed. Running the collector on an unrelated live personal configuration would not establish performance of this candidate. Output directories must be private; neither measurements nor machine identities belong in a public commit.

## Still incomplete or unverified

- Native Hyprland/Noctalia/Omarchy handoff, login, reboot, restore, real authentication, wrong-password and lock-crash behavior, suspend/resume, monitor hotplug and fractional scaling require controlled native sessions.
- Full Caelestia/Ryoku adoption needs installed-version startup and updater exclusions, mixed-host role evidence and a tested lock/idle migration. These descriptors currently permit discovery and isolated preview only.
- Per-site resource cost review, three-run before/after measurements, sustained memory behavior, input-to-frame latency and representative GPU testing are outstanding. An offscreen lifecycle loop proves neither a memory plateau nor monitor-rate presentation.
- Additional stable-model conversions, virtualization of all long settings inventories, uniform unload contracts for every bundle, and native optional-provider failure coverage remain incomplete. This change does not certify every earlier proposed feature.
- Native GIO terminal/D-Bus launch variants, default changes under external concurrent editors, live Wi-Fi/hotspot/pairing permissions and hardware hotplug need further acceptance tests.
- Full clean-machine bootstrap, external network-traffic measurement, publisher signing identity, first-party license selection and public release acceptance gates remain outstanding.

The observed destination repository is public. The prior upload approval was private-only; this candidate requires a separate publication decision after review. No history rewrite, public release or visibility change is part of these local changes.
