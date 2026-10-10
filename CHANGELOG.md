# 0.1.3 — Desktop Profiles, Focus, Station, the workspace overview, Connections, and the bar's animation identity

- Rootlines redesigned with fine curved cedar roots, centre-out growth, soft currents that illuminate passing branches, tiny sap sparks at their tips, and a subtle light beneath the active panel control. Motion stops when hidden, idle, reduced, or in performance mode.

- Desktop Profiles: Balanced, Work, Battery, Night, Gaming and Custom, applied as verified transactions over a shared engine (`components/Transaction.qml`) and ownership stack (`services/Overrides.qml`), with a preparation card, a Profiles window, a Quick Controls tile, Go entries, `cedar profiles` and Core pill signals. Gaming Mode now runs on the same engine. See docs/PROFILES.md.
- CEDAR Focus: timed quiet sessions with held and interruption counts from what really happened, a window with the progress ring, a preparation card, pill actions, a Quick Controls tile, Go, Super+Shift+F and `cedar focus`. Shield, Profiles and Focus are Core pill signals. See docs/FOCUS.md.
- CEDAR Station: health as a first-party application with a diagnostics engine (what, why, verified, action, privileges), live readings, services and failed units with confirmed restarts, the shell log and a redacted diagnostic bundle; `cedar station`. See docs/STATION.md.
- Workspace overview: Super+Tab drops every workspace on every monitor from the bar with compositor thumbnails, switching, keyboard choice and drag-to-move.
- Connections: a VPN section for every NetworkManager VPN or WireGuard profile with Connect, Disconnect and Forget and states read from NetworkManager (a provider's own kill switch is reported, never imitated); Bluetooth rows carry BlueZ states; `settings open <page>`.
- Shield is a station: pages enter on one shared clock, every surface is a chamfered frame with a lit top edge, the rail carries the posture, the overview names the next step, activity is a timeline, and pages deep-link (`cedar shield`, `shield page <name>`).
- The morphing bar: the drops, the Core pill and panel entrances share one motion vocabulary scaled by visual quality; drops join the bar through concave fillets (DropFrame); the pill sits quietly in the bar at rest; the workspace overview grows from its own control.
- Strata: the drops decide their geometry through one model (`StrataGeometry.js`), report explicit surface states, retarget in place between tabs and draw Foundation, Grain and a Living Edge. Kinetic Type moves status words, tile values and the pill's title only when their meaning changes. See docs/KINETIC-TYPE.md.
- The bar's animation identity (docs/BAR-EFFECTS.md): the shell awakens once its bar is on screen (Rootlines draw in, a light sweeps the bar, the Heartwood spins into place); light streams along the root while a panel is open; the Heartwood in the Core pill blooms on click, ripples on a signal, turns on hover and marks Gaming, Focus and Shield attention; panels grow with a lit leading edge; letters cascade and Whispers' lines type in; the workspace mark glides; Canopy Pulse follows real audio when enabled. Settings › Appearance › Bar effects, with Calm, Balanced, Expressive and Off presets; Reduced Motion keeps the bar static; nothing runs at idle.
- `cedar shield`, `cedar ipc` and the Go menu actions reach the shell that owns the `cedar` profile, so they work when the profile points at a checkout.
- Installer: on Omarchy the plan warns before installing when the session handoff cannot run; packages are added the way `omarchy pkg add` does, without a system upgrade, and a failed package transaction is explained; a `cedar` command left by an earlier checkout registration is replaced through the journal and restored on uninstall; Update CEDAR runs inside the installer window with guidance instead of tracebacks (`installer/engine/update.py`).

# 0.1.2 — Keybinds in the Caelestia layout

- Updating is one action: Field Station → Update CEDAR (or `cedar installer --update`) fetches the newest CEDAR, a fast-forward pull of the checkout when one exists or the latest verified release otherwise, then the installer hands the desktop back from a running CEDAR session by itself, installs, and starts CEDAR again. An unreadable `ORIG_HEAD` left by an interrupted git operation is cleared instead of stopping the update.
- CEDAR ships a Hyprland binding set in the Caelestia layout for both configuration syntaxes (`themes/keybinds.lua`, `themes/keybinds.conf`): Super+T/W/C/E for the terminal, browser, editor and files chosen in Settings, Super+Q close, Super+F fullscreen, Super+1…0 workspaces, Super+arrows focus, Super+Z/X drag and resize, groups, special workspaces, media and volume keys, and the shell actions on CEDAR surfaces (tap Super for applications, Super+N Quick Controls, Super+K Field Station, Super+L lock, Ctrl+Alt+Delete power, Super+V clipboard, Super+G Gaming Mode, Super+Shift+Space Go menu). The installer offers "Use CEDAR's keybinds", on by default for plain Hyprland and Waybar setups; the copy lands in `~/.config/cedar/hypr/` and loads through CEDAR's journaled Hyprland loader, so your other bindings stay. See docs/KEYBINDS.md.

# 0.1.1 — Installer fixes from the first real installations

- The session handoff no longer mistakes the CEDAR Installer's own window for an existing Quickshell desktop, which stopped every plain-Hyprland installation at the Session step with "An existing Quickshell desktop is running".
- A refused session handoff is a warning, not a failed installation: CEDAR stays installed, verification still runs, the finish screen shows the reason, and `cedar try` then `cedar keep` start it later.
- The installer tightens its own store folders (`~/.local/state/cedar`, `~/.local/share/cedar`) when an earlier interrupted run left them readable, instead of refusing with "needs a private, user-owned recovery directory".
- The installer no longer hangs at the CEDAR runtime step in window mode; the engine's events and the terminal's progress lines go to the console stream saved at startup.
- Imported monitor modes are spelled the way the compositor lists them, so they pass CEDAR's validator instead of being dropped.
- A copy of the run's log is placed beside the backup manifest under `~/.local/state/cedar/installations/<timestamp>/`.
- The privacy scan ignores generic account names such as the CI runner's, so the validation and release workflows run again.

# 0.1.0 — First release: the CEDAR Installer, Shield, Gaming Mode and the Settings remaster

The first non-development release. `main` is now the default branch; the previous `Main` history is kept as `legacy-main`. Everything below was developed as 0.1.0-dev.15.

- CEDAR Installer: `curl -fsSL …/installer/bootstrap/install.sh | sh` runs a short bootstrap that verifies the release by SHA-256 and opens a CEDAR Installer window (terminal flow without a display). One scan builds one fact model; the installer recognizes Omarchy, HyDE, Caelestia, Noctalia, Ryoku, end-4, ML4W, JaKooLit, Waybar setups and plain Hyprland from several markers each, shows what it keeps and replaces, builds a plan with a digest, stops on risky states, backs up what it may touch (manifest, restore script, services and packages), installs through the existing journaled engine, translates monitor, keyboard, application and wallpaper intent into CEDAR’s own settings, hands the session over through the existing adapters where validated, verifies the result and resumes interrupted runs. `--dry-run`, `--restore`, `--uninstall`, `--repair` and `--last-log`; `cedar installer …` after installation. See docs/INSTALLATION.md.
- The Core pill stays out of games: it hides on an output covered by a fullscreen window, by a focused window the size of the output (borderless games) or by Gaming Mode. Alerts, the hub and Canopies still bring it back; recording and microphone or camera use, which used to keep the whole pill over the game, now leave one ember dot at the top edge that takes no input.
- Gaming Mode shows what it is doing: Super+G brings up a small CEDAR GAMING card above the centre of the focused monitor with one row per optimization that moves waiting → applying → ready as the backend verifies it (amber "Could not apply" for an optional step, quiet "Not installed" for a missing provider), a live "3 / 5 ready" count, "Gaming Mode Ready" with one sweep when the last provider answers, and a fade-out 1.2 s later; leaving shows the same card restoring each step. The power profile and the compositor are now asked at the same time instead of in turn, a game that entered through GameMode is named on the card, and the Power page lists every step of the last entry or exit.
- CEDAR is the session's polkit authentication agent while it is the shell: a privileged action (Shield's firewall, stopping Avahi, a package manager) prompts in a CEDAR card on the main display; the password goes to polkit's helper inside the process and is never logged. Shield's network-discovery action now reports a refused prompt instead of silently skipping Avahi.
- CEDAR Shield, a first-party application (`cedar shield`, Go › Shield, the Shield tile in Quick Controls): its own tiled window with Overview, Protections, Network, Activity and Settings; twelve protections in four groups (firewall, encrypted DNS, network discovery, local exposure, private Wi-Fi address, IPv6 privacy, VPN, lock privacy, idle lock, local-only, clipboard, trails) read from the services that own them and changed through those services with verification and rollback; a posture from the recommended set; per-network Trusted/Public profiles; an activity log of what Shield observed; and one CEDAR shield whose branches light as protections turn on. See docs/SHIELD.md.
- Gaming Mode (Super+G, Quick Controls, Power & Lock): a capture → apply → verify → active transaction over an explicit registry (visual quality, do not disturb, stay awake, performance profile, compositor blur, GameMode observation) with crash recovery; the pill reports "N / M optimizations active" and what failed. See docs/GAMING.md.
- A capability registry discovers the host's providers once (firewall manager, resolver, GameMode, GPU, power, privilege helper, distribution), and one visual-quality policy (normal, efficient, gaming) drives every decorative loop.
- Field Station gains an Update CEDAR button beside Terminal, Browser and Files. It opens a terminal in its own scope and runs the documented checkout update: `git pull --ff-only` in `~/cedar-shell` (or `$CEDAR_CHECKOUT`), `cedar restore` only while a session is active, then the interactive installer. Git decides whether local edits block the pull and nothing is reset; the installer still asks before changing anything. `desktop_runtime.py launch terminal CMD...` now runs a command inside the chosen terminal, with the right flag per emulator.
- Performance mode (Settings › Power & Lock, and a Quick Controls tile): runs only the basics, stopping the breathing light, spores, entrance sweeps, spectrum and ambient telemetry while keeping every control; Automatic turns it on for the power-saver profile or a fullscreen game, and the Power page and Health card say when it is on and why.
- Wallpapers from your own folder: Settings › Desktop › Background gains a "Wallpaper folder" preference (for example `~/Pictures/Wallpapers/CEDAR`). The wallpaper picker and the Desktop page list every image in that folder and its subfolders beside CEDAR’s bundled backgrounds, hidden entries are skipped, and an unset, missing or non-folder value simply shows the bundled set. The picker names the folder it searched.
- Telemetry is read in-process: CPU, memory, network, uptime and the CPU temperature come straight from /proc and hwmon on their own cadence, so the shell no longer spawns a Python helper every 20 seconds; the Forest state recomputes on events instead of once a second; only the selected bar style is built per display; and Settings › Health shows a "Shell cost" card with the shell's memory, threads, cadence and wakeups.
- The launchers answer arithmetic and search the web: typing a sum into Applications or the Go menu shows the result (Enter copies it), a bare address offers to open it, and every other query ends with "Search Brave for …" in your default browser; the engine is a Default Apps setting.
- The Core pill morphs open instead of scaling: width leads, height follows on an expressive curve with a hint of overshoot, content settles in after the shape moves, the ember line rides up to the bar seam and the chamfers open with the panel. Reduced Motion still snaps.
- Fix a false "Network connection lost" signal whenever a network panel closed: every network snapshot now carries the active links, only real links count, and Trailwatch's VPN readout no longer depends on an open panel.
- Network and VPN changes now show on the network button, which pulses and reveals a short label beside its glyph, instead of occupying the Core pill.
- Connections opens as its own panel from the network button: it descends from the chip, has no Canopy tabs or footer, the button stays lit while it is open, and the Core pill keeps its clock instead of switching to the panel title.
- Notifications opens as its own panel from the bell button, descending from the bell and kept inside the screen edge; any bar control with a Canopy topic now anchors its panel the same way.
- Everything that drops from the bar is now one morphing surface: a panel grows straight down out of the control that opened it and joins the bar with inverted chamfers instead of floating below it. Every panel is its own: switching collapses the open one back into the bar and drops the next from its own control, and closing shrinks it back up. Content fades under the motion; Reduced Motion snaps.
- Field Station drops from the CEDAR bar button like the other panels instead of opening as a centred overlay: 760 px wide, full height, no veil, the same motion and silhouette. The keybinding and `hud toggle` IPC follow it; the centred overlay remains when Canopy is off.
- Field Station refined: a one-second entrance on a single clock (the title settles, a filament lights from the left, the dial blooms, telemetry rows stagger in with their bars sweeping and readouts counting up, then each lower section settles), tick marks on section labels, a breathing LIVE dot, uptime, network and telemetry as status pills, hot tips on the metric bars and an ember rule beside the verse. Hosted bare inside the bar drop, so it no longer paints a second card or spore field.
- Quick Controls, Connections and Notifications get the same entrance and flare: a shared one-second clock staggers each instrument in as the panel opens (level rows slide in with a filament lighting along their foot and percentages counting up, tiles and power choices pop in, networks arrive with a signal bar sweeping to strength, notices settle with a rule growing down their side), with ticked section marks and status pills throughout.
- Applications is a new bar drop from the apps button: a search field with a filament that lights as the panel enters and turns green or amber with the query, the last four apps you launched as chips, and an icon grid of every app that scrolls under the fixed search field and answers the arrow keys, Enter and Escape, keeping the selection in view. Tiles pop in one beat apart. The Go menu and Omarchy prompts are unchanged; `menu toggle apps` opens the drop.
- Launcher favourites: press F while browsing the tiles with the arrow keys, or click the star on a tile, to pin an app. Favourites sit in their own section above the rest, keep the order you marked them in, and persist in settings.
- Startup is a new Canopy topic: every autostart entry (yours and the system's) with the live state of the unit that ran it, an on/off switch, run or stop now and remove; type an app name to add it from the catalog or any command to run it at login; Hyprland autostart.lua lines show read-only. `menu toggle` route `cedar.canopy.startup`, IPC `canopy open startup`.
- Canopy IPC gains `open <topic>`: `qs ipc call canopy show …` was swallowed by the CLI's own `ipc show` subcommand, so the Go menu's Canopy routes and `cedar:canopy <topic>` now call `open`.
- Power is its own panel: Super+Esc drops it from the pill with lock, suspend, log out, reboot and shut down as glyph tiles, uptime and battery pills, and a two-step arm-then-confirm for the destructive choices, fully keyboard driven. It is no longer a tab inside Quick Controls.
- Redesign the Core pill around a single "ember line": the clock alone at rest, one line of text for the top signal, a priority-colored line (ember for recording and privacy) and up to three dots instead of glyphs and counters. Volume stays inside the pill, there are only two widths, and the network icon becomes its own chip with a click-through gap. The expanded hub drops the duplicate timer field and compacts other signals. The line breathes through `Breath` and rests with Motion.
- Give Canopy panels the Core pill's chamfered silhouette, compact chip tabs and content-hugging height, and rebuild Quick Controls with slim level rows, lit toggle tiles, a three-way power row, labeled device pickers and a now-playing row.
- Give every desktop destination one button: Canopy's Full Settings is the only Settings button; Canopy tabs omit destinations that already have a bar button; peek, Field Station, the wallpaper picker, System and Weather Canopies, the Core hub and Core signals no longer carry duplicate routes. Keyboard, IPC and Go routes are unchanged.
- Remaster every Settings page on shared section, status and readout components. The sidebar is now the only page navigation and each preference has one control: remove duplicate jump buttons, embedded copies and repeated privacy toggles; add a read-only Overview dashboard, stepper setup, gallery tiles for themes, wallpapers, bar layouts, power profiles and time/date formats, a dedicated Notifications page and a summarized Health page. A regression test enforces single entry points.
- Regroup Settings under Personalize, System, Daily use and Station, with a System breadcrumb and tabs; the service-health page is now labeled Health. Rebuild Displays (detect, snapping arrangement, refresh/scale/rotation chips, mirroring, saved layouts that load into the existing 20-second trial), Input (layout chips, repeat timeline and test field, pointer and touchpad cards), Keybinds (keycaps, your-shortcuts section, category chips) and Connections (status tiles with Wi-Fi, Bluetooth and hotspot sections). Live hardware application of mirroring and layouts remains unverified.

# 0.1.0-dev.14 — Trailwatch on Omarchy, after a verified lock cycle

- `cedar try --adapter omarchy --trailwatch` loads CEDAR's own lock surface (PAM service `omarchy-lock-password`) beside the existing locker. `cedar keep` then opens the local password test window, locks once with Trailwatch and waits for a secure unlock; only after that does it disable the existing lock plugin or clone and mark CEDAR the locker. A failed or skipped step leaves the previous locker selected.
- The bridge bar now answers Omarchy's `lock` IPC (`lock`, `isLocked`, `status`) from a lock-state file CEDAR writes on every change and as a 5 s heartbeat. Keyboard, idle, lid and sleep lock requests keep using `omarchy-system-lock` and reach Trailwatch unchanged; a stale file reads as "no lock screen", never as unlocked.
- Trailwatch enters with a lantern bloom behind the dial, contours drifting up, the header filament lighting from the center outward and the instrument cards settling in with a short stagger, all inside about a second and driven by one clock. The surface is opaque from its first frame; Reduced Motion shows the settled view immediately. Spores drift on the lock surface and rest with Motion.
- Weather finds its location from the public IP by default once weather is enabled: `weatherAutomatic` now defaults to true, the policy helper treats a missing key as true, and the settings page says so. A saved city still overrides it and automatic location can still be turned off.
- While CEDAR is the locker the supervisor reads lock state from the compositor's lock indicator and CEDAR's session info, so a CEDAR crash restores the previous locker instead of deferring forever. `cedar lock [--suspend]` works on Omarchy in this mode. Malformed Omarchy lock status is reported as such instead of a JSON parse message.

# 0.1.0-dev.13 — rest when unwatched, refuse what IPC does not need

- Add `Motion`, one gate for decorative loops: ambience pauses after 120 s without input, under Reduced Motion and in tests. Add `Breath`, a 12-step-per-second sine for always-mapped surfaces. Core's filament, gauge pulses and the lock-surface status pulse no longer commit a frame every refresh for the life of the session; spores and the Field Station core rest with the user.
- Read the backlight only while a brightness control or OSD is visible; sample the ambient CPU hint every 20 s instead of 10 s; wake the recorder probe once per second and scan `/proc` every third second; ignore NetworkManager access-point strength churn while no network list is shown.
- Build Control Center, Power, Themes, Wallpapers and notification history on first show and release them on close, per output, like Go and Settings already did.
- Refuse `settings set`/`get` for application commands, network, location, lock-privacy, clipboard and trail settings (`Config.ipcProtected`); type-check values; refuse writes while locked. Bound `core publish` (16 KiB), `menu summon` (256 KiB, capped prompt/options) and strip control characters from provider text.
- Answer Go prompts through `scripts/menu_reply.py`: temporary-directory paths only, selection file must be an owned regular file opened without following symlinks, done marker created exclusively, replies queued in order. No shell string is built from caller paths. Never run a bare `python3` when the session helper path is missing.
- Remove two binding loops the live smoke test reported on every open: the Settings loader bound `active` through its own item's `dirty`, and the Field Station loader bound `height` through the scroll view's content height. Both now copy the value from the page's signal.
- Document the trust model and IPC surface in `docs/SECURITY.md` and the resource rules in `docs/PERFORMANCE.md`. Measurements remain per-device; no frame-rate or battery figure is claimed here.

# 0.1.0-dev.12 — shared services, quiet controls and reviewed handoffs

- Follow-up from Ubuntu CI: support older PyGObject/GioUnix method bindings; exit failed catalog callbacks so the shared service can retry instead of stalling.

- Load Go, Settings, Field Station and Canopy content on demand; retain input drafts outside unloaded views. Preserve native hosts, monitor routing and authentication lifetime.
- Share a GIO application catalog, defer hidden rescans, launch desktop entries through GIO and preserve unchanged default associations. Reconcile Go/network rows by stable IDs.
- Subscribe to NetworkManager changes, bound scans and requests, gate hotspot disconnect approval, and isolate the optional Bluetooth import. Schedule telemetry by actual consumers with timeout/backoff.
- Apply consistent quiet buttons, keyboard focus, responsive settings rows, control sizing and contained dropdown placement. Add Desktop Setup inside existing Settings using the existing transaction backend.
- Bind approval to a pure plan digest, source fingerprint and provider evidence. Require a durable recovery-supervisor acknowledgment, verify trial generation, record operation states and refuse incomplete confirmation. Preserve later user edits and existing private-directory permissions.
- Inspect bounded Hyprland include graphs and managed Caelestia/Ryoku state without executing upstream hooks. Managed-shell takeover remains unavailable pending installed-version review.
- Add real offscreen pointer/focus, missing-import and page-lifetime checks; real GIO execution/catalog checks; interruption/ownership tests; private resource inspection and measurement tools. No native compatibility or performance improvement is claimed from these tests.

# 0.1.0-dev.11 — select CEDAR Go and Trailwatch during setup

- Offer explicit launcher and lockscreen choices during the portable installer trial. Detect and disclose recognized existing shortcuts, verify applied bindings, and restore their original configuration with the desktop.
- Add native Noctalia 5.2.1 Trailwatch replacement after both a local PAM test and a real secure-lock/successful-unlock cycle. Failed/canceled authentication leaves the previous locker configured. No PAM files change.
- Reuse Noctalia's ordinary idle timings, redirect built-in lock actions, and use a private reviewed hypridle 0.1.7 instance for logind locks and sleep requests. Verify its identity and sleep inhibitor before disabling the old locker. Restore the old locker before stopping CEDAR.
- Provide `cedar launcher`, `cedar lock` and coverage-gated `cedar lock --suspend`. Keep the existing Omarchy integration unchanged. Special shortcut behavior, other idle daemons and locked-state idle timeouts require review.
- Add public-workflow tests for complete control adoption, login, restoration, conflicts, authentication/bridge failure, manual edits, canceled login changes and suspend coverage. Native target lock/hotplug/suspend acceptance remains outstanding.

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
