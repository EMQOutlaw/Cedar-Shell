# Release readiness — 0.1.0-dev.11

**Private development candidate. Not a complete public release.** No first-party license or artwork redistribution grant has been selected. Required upstream notices and approved local KJV content remain intact.

## What exists

The complete working CEDAR source is included: six bars, consolidated Core/Canopy controls, real system services, Field Station/ROOTED/About, Go, Settings, OSD, notifications, Trailwatch, audio/routing/scenes, network/Bluetooth, local telemetry, themes/wallpapers, Pulse/Forest States/Echoes/Whispers/Trails, timers and optional clipboard/weather. `data/plugins.json` maps 15 built-in component bundles plus the portable Hyprland/Noctalia and optional Omarchy integration bundles to shipped files, settings, dependencies, sources, lifecycle limitations and tests. They are not falsely advertised as sandboxed independently unloadable plugins. Rituals, Constellation, general plugin API, full desktop profiles, Home Assistant and advanced DSP remain planned.

The new distribution path provides versioned copied code, explicit-path IPC, an isolated ordinary-window preview, private ownership journals, verified file restoration, retained stable recovery, dependency plans, signature-verified local archive updates and deterministic complete archive packaging. Installation leaves the current shell and its startup untouched. The guided installer and normal shell are independent of Omarchy. The old Omarchy-specific helpers remain for explicit compatibility. Stock Hyprland and resident Noctalia trials, Keep and login integration are implemented with separate source/version gates; neither is yet native-certified.

## Evidence and gates

`data/compatibility.json` records observed Arch/Omarchy runtime versions and offscreen evidence. Plain Hyprland and Noctalia 4.7.7/5.2.1 are experimental; Caelestia/Ryoku and generic shell takeover are unsupported without adapter evidence. No hardware vendor has been certified by this work. CI runs source/recovery/archive checks, not native lock or GPU acceptance.

Candidate 7 fixes CachyOS dependency selection and stops treating recommended fonts as installation blockers. Its package backend is explicit in the dependency manifest and remains experimental. The 237-test local suite and exact-archive install/reinstall checks passed; CachyOS package transactions were tested with controlled fixtures only. See `LOCAL-VERIFICATION.md` for evidence and limits.

Candidate 8 fixes unrelated protected processes blocking upgrades. It moves safety checks ahead of installed helper writes and keeps strict desktop identity, release-use and lock checks. Its 256-test suite includes real Linux protected-process behavior plus controlled upgrade/recovery fixtures. The native desktop gates below remain outstanding.

Candidate 9 fixes the reported native Noctalia discovery parse error and the following version/configuration parsing failures. Its 270-test local suite includes a real isolated Quickshell empty-registry command, native Noctalia response fixtures, bar/monitor configuration preservation, canceled activation and exact settings restoration. The target user reports successful candidate 8 installation, reinstall and preview loading on CachyOS; a completed native Noctalia trial has not been verified. Quickshell and offscreen checks cannot certify native Noctalia authentication or desktop switching.

Candidate 10 fixes the next confirmed failure after trial approval: a missing candidate path during the first lock/IPC check. The prior suite did not exercise that complete approved path. Thirteen new workflow tests execute installer option 3 and public CLI actions through discovery, supervision, confirmation, login setup and restoration. They reproduce the old defect and pass with the fix. These tests simulate external desktop interfaces, so they do not change the native acceptance gates below.

The user reports candidate 10 successfully activated the desktop on CachyOS with native Noctalia 5.2.1. Its preserved stock launcher and lockscreen motivated candidate 11's explicit controls choices. Candidate 11 has 294 passing local Python tests and QML authentication/wiring checks; real new Trailwatch adoption and sleep integration on that target are not yet verified. The installer requires installation-local PAM and secure-unlock evidence before removing the original locker. Fixture results do not replace native acceptance.

Outstanding gates:

- Native acceptance of stock Hyprland, Noctalia and Omarchy 4 trials, independent supervisor, Keep and login opt-in. These are implemented and fixture-tested; none is a certified adapter. Existing Omarchy authentication remains responsible for locking, including the newly reviewed Omacale 0.45.0 clone adapter. Its native trial remains unverified.
- Fresh clean-system package bootstrap and package failure/signature/canceled-auth tests on supported package sources.
- Uniform plugin enable/disable resource lifecycle and isolated optional native imports beyond the currently required complete Quickshell build.
- Cross-version settings checkpoints integrated with the new release transaction; legacy migration tests exist, but distribution installation does not silently run a migration over current preferences.
- Publisher signing identity/provenance and authenticated remote update discovery; this build has no trusted default signing key and no scheduled checks.
- Native outbound-traffic measurement, live NetworkManager/PipeWire, GPU vendor matrix, multi-monitor hotplug, suspend/resume, lock crash recovery and real PAM authentication on each installation.
- License selection, asset redistribution verification, explicit first-publication approval, and successful remote CI/clean checkout.

No missing gate is labeled a pass. A private upload preserves work; it does not certify distribution readiness.
