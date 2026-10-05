# Omarchy desktop trial

`cedar try` runs the actual CEDAR shell from its installed, verified release path. This is separate from the ordinary-window fixture preview. The first adapter targets inspected Omarchy 4.0.4 interfaces; source hashes and upstream revision are recorded in `integrations/omarchy/adapter.json`. Unexpected versions, modified interfaces, competing providers, managed target files, or unknown lock state stop the handoff.

The adapter uses Omarchy's existing bar-plugin and `disabledPlugins` mechanisms. It selects the included empty `cedar.integration` bar and disables only `omarchy.notifications` and `omarchy.osd`. Quickshell keeps the notification bus name for the life of any process that loaded a notification server, so disabling those plugins cannot free it. While the session is unlocked, the adapter then restarts the Omarchy shell once through Omarchy's own lock-safe `omarchy-restart-shell`; the new shell loads without them. It never kills the Omarchy process directly. Omarchy's lock remains required. Existing idle, polkit, background, secret service and portal configuration is preserved; disabled services are not enabled. A disabled stock lock requires a reviewed enabled Omacale clone; unknown lockers stop safely. CEDAR suppresses its own locker and wallpaper in this mode, mirrors the existing lock state, and delegates Lock/Suspend to the existing locker. Suspend requires explicit secure-lock confirmation. Missing/stale supervisor state blocks unlocked CEDAR controls. The existing Omarchy configuration has not been replaced by an authentication overlay.

The source/API review used [Omarchy v4.0.4](https://github.com/omacom/omarchy/tree/c668141e9c42b13c80c9ca4ea108e11708c5e8a5). That version reads its user shell, plugin and hook files from `~/.config/omarchy` directly; the adapter follows the inspected upstream paths while CEDAR code/state continue using XDG locations.

## Omacale 0.45.0

The optional adapter preserves the existing Omacale lock clone, its view, PAM and authentication host. It never edits or removes Omacale code, settings, packages or clone files. `integrations/omarchy/omacale.json` records the inspected public source revision and runtime hashes. Clone identities are discovered locally from `clonedFrom`, enabled state and matching files/contracts, independently of the selected bar and never inferred from an account name. A retained Omacale locker can therefore be recognized after switching back to the stock bar. Installed but disabled plugins do not count as running providers. Symlinked, stale, modified or additional runtime code requires separate review.

A small CEDAR-owned service first pauses the existing notification and OSD handover timers, file watchers and update callbacks through reversible QML bindings. It waits for in-flight work to finish. Only then does a second journaled configuration write select CEDAR and disable overlapping stock/clone notification and OSD entries. The lock clone remains enabled throughout. Both configuration states can be restored after interruption; later user edits cause a conflict instead of being overwritten. Removing the coordinator restores original bindings. No health response is spoofed and no third-party helper is executed by the Python adapter.

Do not update Omacale or Omarchy during a trial; restore the original desktop first. Their existing processes, including any previously enabled upstream network activity, remain outside CEDAR's local-only guarantee. Existing Omacale shortcuts are preserved but may target its now-inactive bar; use CEDAR's visible controls. Native locking, login and full switching remain unverified. A source hash match is not proof of authentication correctness.

## Trial and confirmation

### Reviewed companion plugins

With the reviewed Omacale locker present, candidate 5 can also recognize the supplied Aegis 1.0.0 bar and the inspected Omaland, Omacord and VoxType OSD 1.0.0 sources. `integrations/omarchy/companions.json` records exact source fingerprints, lifecycle contracts and upstream revisions. Version labels alone do not qualify. The private Aegis source, manifest, author and plugin identifier are not redistributed; its installed identity is discovered locally. The imported OmaConnect helper files are checked as well. This is a compatibility review, not a sandbox or a native test certificate.

Only the selected bar is replaced. Companion plugins stay enabled; notification/OSD clones are the only additional entries disabled. A dictation overlay is distinct from the volume OSD. The adapter reports all unknown companion profiles together, with local plugin IDs and the first mismatching file where available. Disabled plugins are ignored; an enabled plugin with `active: false` still needs review.

Aegis focus timers must finish or be canceled in Aegis first. Close its Operations panel and wait for its telemetry/backend readiness. Those conditions are checked again before preparation and the final bar switch. CEDAR does not cancel timers or overwrite tasks, profiles or EQ preferences. The independent Aegis EQ service remains as it was; CEDAR does not adopt its controls. Existing Aegis bar shortcuts remain configured but will not operate its unloaded bar.

Omarchy reloads non-resident plugins when integration files change. Omaland may recreate its own launcher entry; close its editor before switching. Omacord reruns its existing theme installer, which refreshes the current Omarchy theme and invokes existing app-retint hooks. VoxType may briefly recreate its overlay/audio bridge; its independent dictation daemon is not stopped. These behaviors are disclosed in the trial plan. CEDAR does not undo third-party theme-installer effects when restoring its own configuration. Do not update these plugins during a trial. Unknown enabled phone-service implementations still need their own lifecycle review; a reviewed bar import does not automatically approve an independently enabled service.

1. Install the candidate, then run `cedar try` and approve the listed changes.
2. Run `cedar keep` within 120 seconds of the desktop becoming ready to keep the current session.
3. Optionally run `cedar activate` to approve starting CEDAR at login.
4. Run `cedar restore` to restore the previous Omarchy configuration.

Use `"$HOME/.local/bin/cedar"` when the command is not on PATH. To update an already active trial/session, restore it first, install the new candidate, then trial it again. Source switching and uninstall refuse while an integration is active.

The detached supervisor runs as a uniquely named user systemd service with restart-on-failure. Its code lives beside the stable offline recovery script. The trial backs up every affected file before mutation, including the original shell configuration, bridge files and owned post-boot hook. The hook restores an unconfirmed trial after login; it starts CEDAR only after the separate login opt-in. A timeout or CEDAR crash requests restoration; an active or unknown lock defers it. Recovery checks later edits before stopping CEDAR. It never signals the Omarchy authentication host or arbitrary Quickshell instances.

## Boundaries

- Existing keyboard shortcuts remain unchanged. The bridge forwards Omarchy's notification dismissal/history/action and OSD IPC to CEDAR without rebinding keys. Existing Omarchy application/menu shortcuts continue using their original destinations; CEDAR Go is available from its bar.
- Trailwatch stays in the project but does not replace the existing authentication service in this integration. Native authentication handoff needs separate device validation.
- This is not an authentication sandbox. Omarchy and CEDAR remain trusted local code.
- Plugins outside the reviewed Omacale providers and companion fingerprints, and prior CEDAR theme-switch hooks, require their own review. The adapter refuses those conflicts.
- No claim is made that upstream software or other applications have no network traffic. CEDAR's private defaults are preserved.

## Offline recovery

`python3 ~/.local/share/cedar/recovery/distribution.py restore` also works when PATH is broken (substitute your actual XDG data directory). When no graphical session or Quickshell instance remains, it can restore recorded files without compositor IPC. In a running session it requires reliable unlocked state. A text console alone is not proof that the graphical session ended.

`cedar status` reports the last local error. Later edits to an owned target cause conflict refusal and leave both the edited file and verified backups intact. Do not delete those files blindly. No automatic reboot or logout is performed.

## Evidence

Unit fixtures cover configuration preservation, protected services, ambiguous/locked state, timeout, crash, separate confirmation, rollback conflicts and offline restoration. An offscreen QML test covers missing, stale, invalid and locked status. These are simulated tests, not live acceptance of Omarchy 4.0.4 on the user's machine. Login/reboot, real authentication, monitor hotplug, suspend/resume and GPU compatibility remain unverified until tested in controlled native sessions.
