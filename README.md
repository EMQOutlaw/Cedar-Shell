# CEDAR

**A living desktop environment for Hyprland.** *Rooted in faith. Built with care.*

CEDAR is a complete desktop shell for the Hyprland compositor: a bar in six styles, a central Core pill, Quick Controls, Field Station, searchable Settings, the Go launcher, notifications, on-screen displays, real system instruments, the Trailwatch lock screen, CEDAR Shield for network privacy, and a Gaming Mode. It is quiet, works offline, and keeps your existing applications, displays and settings.

> **Release 0.1.0.** This is CEDAR's first release. The first-party source and artwork remain unlicensed by the owner's decision: please do not redistribute them under an invented license. Upstream notices are in [credits](docs/LICENSES.md).

## Before you start

- A Linux system that already runs **Hyprland**. CEDAR does not install a compositor or login manager.
- **Arch Linux, CachyOS or Omarchy** on x86_64 for automatic package setup. Other distributions work when Quickshell, Hyprland and the other dependencies are already installed; the installer will say what is missing.
- **Python 3.11 or newer.**

Your current desktop stays in place. CEDAR backs up what it may touch, shows you a plan, and changes nothing until you approve it.

## Install

Run one command. It downloads a short, readable script that verifies the release and opens the **CEDAR Installer**:

```bash
curl -fsSL https://raw.githubusercontent.com/EMQOutlaw/Cedar-Shell/main/installer/bootstrap/install.sh | sh
```

The command installs the latest published release and verifies its checksum. Contributors who want the `dev` source branch instead can add `CEDAR_CHANNEL=development` before `sh`.

Prefer Git? Clone the repository and run the installer from it:

```bash
git clone --branch main https://github.com/EMQOutlaw/Cedar-Shell.git cedar-shell && cd cedar-shell && bash ./install.sh
```

To update later, press **Field Station → Update CEDAR**, or from a terminal:

```bash
"$HOME/.local/bin/cedar" installer --update
```

Both open the CEDAR Installer on an Update stage. **Stable Branch** follows `main`; **Development Branch** follows `dev`. The up-to-date screen shows the selected branch and offers the other branch, so you can try development work and return to stable from the same window. The installer remembers the branch after a successful installation.

Updates fetch an isolated copy of the selected branch and compare its actual contents with the installed copy, including changes that share the same version number. Your own checkout and edits stay untouched. Installation still shows a plan for approval and uses the existing desktop handoff and recovery. See [update channels](docs/UPDATE-CHANNELS.md).

### What the installer does

1. **Scans your system** once: distribution, Hyprland, graphics, your existing desktop, monitors, keyboard and preferred apps.
2. **Recognizes your current environment** (Omarchy, HyDE, Caelestia, Noctalia, Ryoku, end-4, ML4W, JaKooLit, a Waybar setup, or plain Hyprland) and shows what it keeps and what it replaces.
3. **Shows a plan** and waits for your approval.
4. **Backs up** the configuration it may touch, with a manifest and a restore script.
5. **Installs** the dependencies and CEDAR, imports your monitor and keyboard settings, and verifies the result.
6. **Starts CEDAR** in your session where that is supported, and offers it at login.

If something is risky, such as missing packages on an unsupported distribution or a locked session, the installer stops and explains before touching anything. An interrupted installation can be resumed. The full description is in [docs/INSTALLATION.md](docs/INSTALLATION.md).

Without a display, or with `--no-gui`, the same steps run in the terminal. Useful flags: `--dry-run` (plan only), `--restore` (put the previous system back), `--uninstall`, `--repair`.

## After installing

Where the installer did not start CEDAR itself, the `cedar` command does it in steps you can undo:

```bash
"$HOME/.local/bin/cedar" try        # a 120-second trial of the full desktop
"$HOME/.local/bin/cedar" keep       # keep it for this session
"$HOME/.local/bin/cedar" activate   # also start it at login
"$HOME/.local/bin/cedar" restore    # go back to your previous desktop
```

The installer can also give you CEDAR's keybinds in the Caelestia layout, Super+T for the terminal, Super+Q to close, Super+1…0 for workspaces, Super+N for Quick Controls, loaded through CEDAR's journaled Hyprland loader so your other bindings stay (see [docs/KEYBINDS.md](docs/KEYBINDS.md)). `cedar preview` opens CEDAR in an ordinary window with sample data, without touching your desktop. `cedar status` explains a pending or failed trial and `cedar doctor` runs local checks.

**On stock Hyprland**, CEDAR pauses Waybar, Mako or Dunst while it runs and leaves your compositor, portals, authentication agent, audio, network, displays and default apps alone. **With Noctalia** (4.7.7 or native 5.2.1), CEDAR supplies the bar, Canopy, notifications and OSD while Noctalia keeps its locker, idle handling, authentication and wallpaper. **On Omarchy**, CEDAR replaces the Omarchy shell and keeps its lock, idle and polkit services. For other environments CEDAR installs beside the existing shell and opens as a preview until a reviewed handoff exists.

These session handoffs are experimental: they have fixture and offscreen tests, not clean-machine acceptance. An unconfirmed trial is restored automatically; nothing logs you out, restarts the compositor or reboots.

## Undo and recover

- `cedar restore` returns your previous desktop. `cedar rollback` returns to the previous installed release.
- `cedar installer --uninstall` undoes CEDAR-owned changes: the session, the `cedar` command, launcher entries and copied configuration. It keeps your preferences, wallpapers, backups and every shared package such as Quickshell or PipeWire.
- Every installation leaves a backup under `~/.local/state/cedar/installations/` with a `restore.sh`, and a standalone recovery tool that needs only Python. See [docs/RECOVERY.md](docs/RECOVERY.md).

Updates are manual and verified: `cedar update ARCHIVE --signature SIGNATURE --trusted-key PUBLIC_KEY`. Nothing downloads or updates in the background. Messages from older candidates and the classic terminal installer are covered in [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

## Privacy

Local-only mode is on by default. Weather and remote artwork are opt-in, and weather uses your public IP for location unless you pick a city. Clipboard history and window-title Trails are opt-in. **CEDAR Shield** (`cedar shield`, or Go › Shield) shows your firewall, encrypted DNS, network discovery, private Wi-Fi and IPv6 addresses and what listens on your network, and changes them only through the services that own them, with verification and rollback. **Gaming Mode** (Super+G) quiets the desktop around a game and restores everything afterwards. See [privacy](docs/PRIVACY.md), [Shield](docs/SHIELD.md) and [Gaming Mode](docs/GAMING.md).

## Compatibility

Developed and tested on Arch with Hyprland 0.56.2, Quickshell 0.3.1 and Qt 6.11.2 on x86_64. Package preparation on Arch, CachyOS and Omarchy has fixture tests but no clean-machine run yet. The [dependency manifest](data/dependencies.json), [component inventory](data/plugins.json), [compatibility evidence](data/compatibility.json) and [release readiness](docs/RELEASE-READINESS.md) list exactly what has and has not been verified.

## Why CEDAR?

CEDAR takes inspiration from the cedar of Lebanon in Scripture: patient growth in Psalm 92:12 and cedar used in temple construction in 1 Kings 6:9–10. The project applies that imagery to steadfast faith and care in what we build; its technical acronym, Contextual Environment & Desktop Automation Runtime, is its own creation. Field Station's ROOTED section and Settings → About include the locally stored KJV passages, including John 3:16–17. Everyone can use CEDAR without an account or religious acknowledgment.

## For maintainers

Build the release assets with `python3 scripts/package_release.py --release-assets dist` and test those exact bytes with `python3 tests/check_artifact.py dist/cedar-*-x86_64.tar.gz`. A `v*` tag runs the release workflow, which attaches them to the GitHub release; CI never installs or updates anything on users' machines. When adding or removing source files, stage them and run `python3 scripts/update_source_inventory.py`; CI checks that `data/source-files.json` matches the tracked files. Public publication requires licensing, the documented acceptance gates and explicit owner approval.
