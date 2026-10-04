# CEDAR Shell

**Contextual Environment & Desktop Automation Runtime**

A living desktop environment for Hyprland. **Rooted in faith. Built with care.**

CEDAR is an existing Qt Quick/Quickshell shell, previously Foxfire. It includes consolidated center controls, six bar styles, Field Station, Canopy, searchable Settings, Go, notifications, persistent OSDs, real system instruments and the Trailwatch session-lock interface. Its woodland design and local Christian identity remain available offline.

**Private development candidate—not yet a certified public distribution.** First-party source is currently unlicensed by the owner's decision. Do not redistribute the artwork or original code under an invented license. Required upstream notices remain in [credits](docs/LICENSES.md).

## Installation and preview

With Git installed, copy and paste this command into your terminal:

```bash
git clone --branch distribution-hardening https://github.com/EMQOutlaw/Cedar-Shell.git cedar-shell && cd cedar-shell && bash ./install.sh
```

The repository is currently private, so your GitHub account needs access and Git authentication must be configured. This downloads the development candidate and opens the installer for your approval. Installation preserves your current desktop; activation is not included yet. Run it from a folder that does not already contain a `cedar-shell` directory.

For a provided private candidate archive:

1. Download the CEDAR archive.
2. Extract it and open a terminal in the extracted `cedar-shell` folder.
3. Run `bash ./install.sh`.

A checkout works too. Python 3 and ordinary shell utilities bootstrap setup. On Arch, a missing Python can be installed only after approving the displayed full-upgrade plan. Quickshell is required for preview and desktop use. `python3 scripts/distribution.py dependencies` shows missing software; `--approve-packages --approve-system-upgrade` explicitly authorizes configured Arch repository packages and a full supported upgrade. No AUR helper or repository is silently added. Compositors, drivers and service replacements are excluded.

The installer shows an **Install Only** plan and copies complete source into versioned user data storage; the extracted folder can then be removed. It preserves current preferences and desktop startup. A command collision or managed/symlinked target stops safely. `--plan` inspects without installation; `--approve-install-only` encodes that limited unattended choice. There is no generic yes flag authorizing takeover.

`cedar preview` opens an ordinary window with explicitly labeled fixtures, isolated preferences and local-only operation. It does not own notifications, replace wallpaper, reserve desktop space or lock the session. **Try/Keep/login takeover is a release blocker and currently refuses**; this candidate will not guess how to disable another shell.

After installation, open that preview with this command (it also works when `~/.local/bin` is not on your PATH):

```bash
"$HOME/.local/bin/cedar" preview
```

If the installer says **Desktop activation: not performed**, installation succeeded. The preview is currently the available way to try the interface; switching your full desktop to CEDAR is not implemented in this distribution candidate yet.

## Recovery and updates

`cedar doctor` performs local read-only checks. `cedar restore`, `cedar rollback` and the standalone Python recovery tool use recorded hashes and preserve later edits. Read [offline recovery](docs/RECOVERY.md) before testing an installation. Uninstall keeps preferences, backups, source releases, recovery and shared dependencies by default.

Updates are manual: `cedar update ARCHIVE --signature SIGNATURE --trusted-key PUBLIC_KEY`. The key must be obtained through a separately trusted publisher channel; a checksum is not publisher authentication. No publisher identity has been established for this development candidate. The System Settings page offers a local archive/signature/key review action. No silent downloads or updates run in the background.

## Privacy and compatibility

Local-only mode is on by default. Weather, approximate IP location and remote artwork require separate opt-in. Clipboard history and window-title Trails remain opt-in. See [privacy](docs/PRIVACY.md), the [dependency manifest](data/dependencies.json), [component inventory](data/plugins.json), and [compatibility evidence](data/compatibility.json).

The observed development environment is Arch/Omarchy, Hyprland 0.56.2, Quickshell 0.3.1 and Qt 6.11.2 on x86_64. Offscreen tests do not certify those versions for every host. No other compositor or broad hardware support is promised. [Release readiness](docs/RELEASE-READINESS.md) lists the incomplete and untested gates.

## Why CEDAR?

CEDAR takes inspiration from the cedar of Lebanon in Scripture: patient growth in Psalm 92:12 and cedar used in temple construction in 1 Kings 6:9–10. The project applies that imagery to steadfast faith and care in what we build; its technical acronym is its own creation. Field Station's ROOTED section and Settings → About include the approved locally stored KJV passages, including both John 3:16–17 verses. Everyone can use CEDAR without an account or religious acknowledgment.

## Maintainers

Build a private candidate with `python3 scripts/package_release.py /tmp/cedar-shell-development.tar.gz`, then test those exact bytes with `python3 tests/check_artifact.py /tmp/cedar-shell-development.tar.gz`. CI is read-only and never publishes releases or installs updates on users' machines. Public publication requires licensing, the documented acceptance gates and explicit owner approval.
