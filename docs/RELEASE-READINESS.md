# Release readiness — 0.1.0-dev.7

**Private development candidate. Not a complete public release.** No first-party license or artwork redistribution grant has been selected. Required upstream notices and approved local KJV content remain intact.

## What exists

The complete working CEDAR source is included: six bars, consolidated Core/Canopy controls, real system services, Field Station/ROOTED/About, Go, Settings, OSD, notifications, Trailwatch, audio/routing/scenes, network/Bluetooth, local telemetry, themes/wallpapers, Pulse/Forest States/Echoes/Whispers/Trails, timers and optional clipboard/weather. `data/plugins.json` maps 15 built-in component bundles plus the portable Hyprland/Noctalia and optional Omarchy integration bundles to shipped files, settings, dependencies, sources, lifecycle limitations and tests. They are not falsely advertised as sandboxed independently unloadable plugins. Rituals, Constellation, general plugin API, full desktop profiles, Home Assistant and advanced DSP remain planned.

The new distribution path provides versioned copied code, explicit-path IPC, an isolated ordinary-window preview, private ownership journals, verified file restoration, retained stable recovery, dependency plans, signature-verified local archive updates and deterministic complete archive packaging. Installation leaves the current shell and its startup untouched. The guided installer and normal shell are independent of Omarchy. The old Omarchy-specific helpers remain for explicit compatibility. Stock Hyprland and resident Noctalia trials, Keep and login integration are implemented with separate source/version gates; neither is yet native-certified.

## Evidence and gates

`data/compatibility.json` records observed Arch/Omarchy runtime versions and offscreen evidence. Plain Hyprland and Noctalia 4.7.7/5.2.1 are experimental; Caelestia/Ryoku and generic shell takeover are unsupported without adapter evidence. No hardware vendor has been certified by this work. CI runs source/recovery/archive checks, not native lock or GPU acceptance.

Candidate 7 fixes CachyOS dependency selection and stops treating recommended fonts as installation blockers. Its package backend is explicit in the dependency manifest and remains experimental. The 237-test local suite and exact-archive install/reinstall checks passed; CachyOS package transactions were tested with controlled fixtures only. See `LOCAL-VERIFICATION.md` for evidence and limits.

Outstanding gates:

- Native acceptance of stock Hyprland, Noctalia and Omarchy 4 trials, independent supervisor, Keep and login opt-in. These are implemented and fixture-tested; none is a certified adapter. Existing Omarchy authentication remains responsible for locking, including the newly reviewed Omacale 0.45.0 clone adapter. Its native trial remains unverified.
- Fresh clean-system package bootstrap and package failure/signature/canceled-auth tests on supported package sources.
- Uniform plugin enable/disable resource lifecycle and isolated optional native imports beyond the currently required complete Quickshell build.
- Cross-version settings checkpoints integrated with the new release transaction; legacy migration tests exist, but distribution installation does not silently run a migration over current preferences.
- Publisher signing identity/provenance and authenticated remote update discovery; this build has no trusted default signing key and no scheduled checks.
- Native outbound-traffic measurement, live NetworkManager/PipeWire, GPU vendor matrix, multi-monitor hotplug, suspend/resume, lock crash recovery and real PAM authentication on each installation.
- License selection, asset redistribution verification, explicit first-publication approval, and successful remote CI/clean checkout.

No missing gate is labeled a pass. A private upload preserves work; it does not certify distribution readiness.
