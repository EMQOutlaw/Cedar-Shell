# Compatibility validation

This branch is a development candidate. No migration test targets the developer's
live desktop, and none of the source changes were installed or deployed.

Recorded development results (2026-10-11): 512 Python tests passed, including
31 compatibility tests. Station and identity offscreen checks passed, as did
the three geometry/transition/diagnostics JavaScript suites, privacy audit,
source inventory, Python compilation and Arch recipe metadata. The candidate
archive passed hash checks and fresh/repeated installation in disposable XDG
directories with real offscreen QML validation. Read-only diagnostics against
the existing CEDAR/Omarchy session confirmed IPC, notification ownership,
mapped bars and control interfaces; the independent Voxtype QS instance was
reported as an unknown role and left untouched. This is not a migration test.

## Automated coverage

`python3 -m unittest discover -s tests -p 'test_compatibility.py'` runs 31 tests
using temporary HOME/XDG directories, injected Host facts and simulated adapters:

- Plain Hyprland, Waybar, native/QML shells, all named profiles, multiple
  installations, and current/other/unknown graphical session evidence.
- Installed/configured/active/autostarted/managed distinctions; unsupported
  providers cannot become activation authority just because they match a profile.
- Duplicate startup entries, unresolved includes, missing dependencies, ordinary
  permission failures, broken symlinks and unknown Quickshell ownership.
- Existing shortcut conflicts, explicit preservation/reassignment, duplicate or
  invalid assignments, classic and Lua rendering, and no global clipboard emulation.
- Read-only preview, stale source approval, exact file/mode restoration,
  idempotent application, operation locks and later user edits.
- Failed shell health, partial activation, coordinator interruption before the
  session ID is copied back, and refusal to claim another session for recovery.
- Failed provider restoration, retry, mismatched service state and missing
  pre-migration service evidence. No failed verification is reported as success.
- Standalone legacy recovery still works without a selected release; pending
  compatibility recovery cannot silently fall through to installation rollback.
- Runtime restart keeps supervisor ownership; health requires mapped bars and
  registered control interfaces in addition to existing session/notification checks.

Existing recovery, portable lifecycle, Omarchy/Omacale, installer, update-channel,
privacy and publication suites also run. Socket fixtures need an environment
that permits temporary Unix sockets; a sandbox refusal is not desktop evidence.

`python3 tests/check_station.py` runs actual Quickshell offscreen in `CEDAR_TEST=1`
with fixture readings and isolated state. It opens Desktop at narrow and wide
widths alongside the existing diagnostics pages and rejects QML load/runtime errors.
This verifies UI integration, not Wayland/PAM functionality.

The normal CI workflow includes the compatibility tests, Python compilation,
privacy audit and publication inventory. `tests/check_artifact.py` additionally
runs compatibility fixtures from a disposable extraction of the exact archive,
along with existing fresh/repeated installation and offscreen validation checks.
The Arch recipe is checked with `makepkg --printsrcinfo`; this does not install
packages. Nix is absent on this host, so no Nix build/evaluation is claimed.

## Native acceptance still required

Use disposable VM accounts or dedicated physical test accounts. Record the
upstream revision, compositor/QS/Qt versions, enabled units, input configuration
and journal IDs. Do not run failure injection on a personal live desktop.

For each experimental adapter (standalone Hyprland/Waybar, pinned Noctalia v4/v5,
and pinned Omarchy), verify preview → approved activation → panel/control and
notification readiness → keep/login → logout/login/reboot → verified restore.
Repeat with multiple outputs, another independent QS widget, restarting units,
user-edited files, shell failure and an interrupted coordinator. Test normal lock,
idle, suspend/resume and optional Trailwatch authentication on a controlled host.

Caelestia, HyDE, end-4 and DMS require dedicated role-level handoff adapters before
native migration acceptance; they currently receive detection and a manual-review
boundary. Nix requires flake/package and Home Manager evaluation plus an actual
session runner. Neither profile existence nor passing fixture tests earns a
"fully supported" label. Compatibility levels remain in the adjacent matrix.
