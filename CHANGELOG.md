# 0.1.0-dev.10 — initialize the approved trial before checking it

- Supply the explicit installed candidate path before the first lock/IPC check. Candidate 9 could finish installation and approval but fail with `'root'` before creating a trial or changing Noctalia's settings.
- Add complete public-workflow regressions for installer option 3 and the installed CLI: approved native Noctalia and plain Hyprland trials, Keep, login activation, renewed provider identity at login, timeout/startup-failure recovery, exact restoration, later user edits and lock deferral.
- Exercise production discovery, candidate lookup, IPC routing, lock checks, transactions, supervisor and approval logic together. Only external desktop/process interfaces and time are simulated. The new test reproduces the candidate 9 failure with the old trial function.
- Run these workflow tests in CI and against the extracted release archive. Native CachyOS/Noctalia desktop and authentication acceptance remain unverified; offscreen component checks cannot substitute for them.

# 0.1.0-dev.9 — native Noctalia discovery and settings handoff

- Accept Quickshell's exact successful `No running instances.` response in JSON-list mode. Native Noctalia does not require an existing Quickshell profile. Malformed or missing responses still defer desktop changes and now identify the failing interface.
- Parse Noctalia's `v5.2.1` release field separately from package/build metadata; retain the reviewed-version gate. Version output is not a binary provenance check.
- Handle native bar-order metadata, quoted bar names, monitor aliases and per-monitor bar/dock enable flags. Change only approved surface booleans, preserve comments and unrelated preferences, and keep the existing Noctalia host and authentication services.
- Share instance discovery with doctor and the optional Omarchy adapter. Doctor distinguishes a verified empty registry from failed discovery.
- Add actual Quickshell empty-registry and controlled native-response, cancellation, lock-state, settings and exact-restoration tests. Native CachyOS desktop handoff remains unverified.

# 0.1.0-dev.8 — protected process discovery and upgrade safety

- Do not require executable or argument access to unrelated protected applications. Scope installation checks to Hyprland and Quickshell; keep strict PID/start/executable verification for coordinated desktop providers.
- Preserve active executable detection after package replacement and resolve Quickshell current-release links through its instance registry. Unknown lock states and unreadable desktop providers continue to block switching.
- Check upgrade safety before validation or installed helper changes, and check again immediately before replacing helpers. Refused upgrades leave the existing launcher and recovery code intact.
- Add process-permission, lock, PID reuse, upgrade and rollback regressions, including a real protected Linux child process. No ptrace permissions, system settings or running desktop are changed. Native CachyOS activation remains unverified.

# 0.1.0-dev.7 — CachyOS setup and optional font recovery

- Recognize CachyOS explicitly through the dependency manifest, independently of the selected Hyprland/Noctalia/Omarchy desktop adapter. Verify distribution, architecture and configured package availability before asking for privileged package approval.
- Keep recommended fonts optional with readable fallbacks; a missing font no longer blocks updating an older installed cedar command. Explicit font installation remains available through dependencies --include-recommended.
- Reuse the exact disclosed package plan after approval, require full-upgrade consent, and record package failures without proceeding to desktop changes.
- Clarify checkout versus installed-version updates and add installer/package regressions. CachyOS native activation and live package transactions remain untested.

# 0.1.0-dev.6 — standalone Hyprland and optional Noctalia

- Remove Omarchy from portable dependency checks, installer prerequisites, Go, default-app launching, theme/wallpaper state and PAM selection. Retain an explicit optional adapter for existing Omarchy installations.
- Add a guided installer with package approval, Install Only, isolated Preview, supervised Trial, Keep and separate login approval. Reuse compatible local Quickshell/Qt builds after actual import/image checks.
- Add stock Hyprland provider coordination and separate reviewed Noctalia 4.7.7/5.2.1 adapters. Preserve resident lockers, idle services, wallpaper providers, running applications, display/input configuration and existing shortcuts.
- Add private, recoverable surface settings edits, exact provider identity checks, source/version revalidation at login, lock-state deferral and an independent supervisor. Unknown configurations remain preview-only.
- Support both generated Hyprland configuration formats; ship ordinary optional palettes without distro-specific startup or keybind replacements.
- Extend recovery, portable runtime, QML, manifest and exact-archive tests. Native handoff/login/PAM/hardware and clean-machine package bootstrap remain unverified; this is a private development candidate.

# 0.1.0-dev.5 — reviewed custom bar and companion handoff

- Recognize reviewed Aegis source without publishing its private source or manifest; validate its imported helper files and preserve the existing Omacale locker.
- Preserve inspected Omaland, Omacord and VoxType OSD plugins by exact source/lifecycle checks; disclose their reload behavior before approval.
- Refuse active Aegis focus sessions and unfinished/open Operations UI before switching. Preserve independent EQ, tasks and profiles.
- Report unknown companion plugins together. Add source, lifecycle, helper, privacy and activity-state regressions. Native desktop handoff remains unverified.

# 0.1.0-dev.4 — detect retained lockers independently of the bar

- Discover enabled lock clones even when Omacale is no longer the selected bar.
- Retain all provider source, lifecycle, capability and live authentication checks. An installed but disabled plugin is not treated as a running provider.
- Add regressions for retained lockers, inactive installations, modified lock code and selected-but-inactive bars. Native handoff remains unverified.

# 0.1.0-dev.3 — installation diagnostics and source boundaries

- Report session refusals without Python tracebacks, including clear trial-first instructions.
- Package only the reviewed source inventory; preserve and exclude nested clones and untracked local files.
- Preserve intentionally disabled idle, wallpaper and polkit services. Support the reviewed Omacale 0.45.0 lock clone without replacing authentication; reject unknown providers.
- Pause/resume Omacale notification/OSD repair watchers through an optional coordinator, with interrupted two-stage configuration recovery.
- Add standalone recovery CLI and archive-boundary regressions. Native activation remains unverified.

# 0.1.0-dev.2 — experimental Omarchy desktop activation

- Add a full desktop trial, independent recovery supervisor, explicit Keep, separate login opt-in and restoration using the existing ownership journal.
- Keep the existing Omarchy authentication/idle/polkit host and wallpaper; switch only the approved visible providers. Scope legacy named CEDAR IPC to the selected release.
- Add fixture and offscreen lock-state tests. Native device/login/hardware acceptance remains pending; this is not a stable release.

# 0.1.0-dev.1 — private development candidate

Preserves the implemented CEDAR shell, consolidated Core/Canopy, Field Station, Trailwatch and offline Christian identity. Adds private network defaults, versioned install-only deployment, ownership journals, verified backup/restore, dependency planning, isolated preview and signature-checked local update candidates.

This is not a stable public release. Real desktop trial/Keep-at-login activation, independent trial supervision, clean-system compatibility and secure-lock hardware testing remain release blockers. Distribution adapters do not claim certification. First-party source and carried-forward artwork remain unlicensed; private review only.
