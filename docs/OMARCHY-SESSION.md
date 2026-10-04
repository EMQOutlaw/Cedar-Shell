# Omarchy desktop trial

`cedar try` runs the actual CEDAR shell from its installed, verified release path. This is separate from the ordinary-window fixture preview. The first adapter targets inspected Omarchy 4.0.4 interfaces; source hashes and upstream revision are recorded in `integrations/omarchy/adapter.json`. Unexpected versions, modified interfaces, competing providers, managed target files, or unknown lock state stop the handoff.

The adapter uses Omarchy's existing bar-plugin and `disabledPlugins` mechanisms. It selects the included empty `cedar.integration` bar and disables only `omarchy.notifications` and `omarchy.osd`. It never kills or restarts the Omarchy process. Omarchy's lock, idle, polkit, background, secret service and portals remain in place. CEDAR suppresses its own locker and wallpaper in this mode, mirrors the existing lock state, and delegates Lock/Suspend to the existing locker. Suspend requires explicit secure-lock confirmation. Missing/stale supervisor state blocks unlocked CEDAR controls. The existing Omarchy configuration has not been replaced by an authentication overlay.

The source/API review used [Omarchy v4.0.4](https://github.com/omacom/omarchy/tree/c668141e9c42b13c80c9ca4ea108e11708c5e8a5). That version reads its user shell, plugin and hook files from `~/.config/omarchy` directly; the adapter follows the inspected upstream paths while CEDAR code/state continue using XDG locations.

## Trial and confirmation

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
- Third-party service plugins and prior CEDAR theme-switch hooks require their own review. The adapter refuses those conflicts.
- No claim is made that upstream software or other applications have no network traffic. CEDAR's private defaults are preserved.

## Offline recovery

`python3 ~/.local/share/cedar/recovery/distribution.py restore` also works when PATH is broken (substitute your actual XDG data directory). When no graphical session or Quickshell instance remains, it can restore recorded files without compositor IPC. In a running session it requires reliable unlocked state. A text console alone is not proof that the graphical session ended.

`cedar status` reports the last local error. Later edits to an owned target cause conflict refusal and leave both the edited file and verified backups intact. Do not delete those files blindly. No automatic reboot or logout is performed.

## Evidence

Unit fixtures cover configuration preservation, protected services, ambiguous/locked state, timeout, crash, separate confirmation, rollback conflicts and offline restoration. An offscreen QML test covers missing, stale, invalid and locked status. These are simulated tests, not live acceptance of Omarchy 4.0.4 on the user's machine. Login/reboot, real authentication, monitor hotplug, suspend/resume and GPU compatibility remain unverified until tested in controlled native sessions.
