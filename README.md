# CEDAR Shell

**Contextual Environment & Desktop Automation Runtime**

A living desktop environment for Hyprland. **Rooted in faith. Built with care.**

CEDAR is an existing Qt Quick/Quickshell shell, previously Foxfire. It includes consolidated center controls, six bar styles, Field Station, Canopy, searchable Settings, Go, notifications, persistent OSDs, real system instruments and the Trailwatch session-lock interface. Its woodland design and local Christian identity remain available offline.

**Development candidate—not yet a certified public distribution.** First-party source is currently unlicensed by the owner's decision. Do not redistribute the artwork or original code under an invented license. Required upstream notices remain in [credits](docs/LICENSES.md).

## Installation and preview

With Git installed, copy and paste this command into your terminal:

```bash
git clone --branch distribution-hardening https://github.com/EMQOutlaw/Cedar-Shell.git cedar-shell && cd cedar-shell && bash ./install.sh
```

The repository is public; no GitHub sign-in is needed to clone it. This downloads the development candidate and opens the installer for your approval. Installation preserves your current desktop. The installer then offers Install Only, an isolated preview, or a reversible full desktop trial on Hyprland. Run it from a folder that does not already contain a `cedar-shell` directory.

**Already cloned into your home folder?** Update that checkout instead of cloning again:

```bash
cd "$HOME/cedar-shell" && git pull --ff-only && bash ./install.sh
```

If Git reports local changes or divergent history, stop and preserve your edits; do not reset or delete the checkout. The installer copies only the reviewed source inventory, so an accidentally nested clone or local settings file is not included and is left untouched.

**Already running a kept CEDAR session?** Restore its desktop integration before updating the installed release:

```bash
"$HOME/.local/bin/cedar" restore && cd "$HOME/cedar-shell" && git pull --ff-only && bash ./install.sh
```

Candidate **0.1.0-dev.12** adds Settings → Desktop Setup, quiet controls, lazy views, shared application/network subscriptions and stricter handoff journals. See [implementation and verification](docs/IMPLEMENTATION-REPORT.md) for the exact scope and outstanding native gates. Desktop Setup uses the same backend as the terminal installer; it does not bypass local authentication, ownership checks or separate login approval.

The launcher and lockscreen choices introduced in **0.1.0-dev.11** remain available. Choose **3**, then **yes** for **CEDAR Go** and, on native Noctalia 5.2.1, **Trailwatch**. The plan lists the exact shortcuts being redirected. Trailwatch first checks your password in a local window, then opens one real lockscreen test: unlock normally to continue. Your previous locker remains configured until that secure unlock succeeds and the sleep bridge is ready. Never enter your password in chat. Keep the desktop after checking it, then approve login activation separately.

The Trailwatch replacement uses **hypridle 0.1.7** for logind lock and sleep requests; the dependency plan includes it when missing without enabling its global service. CEDAR starts a private instance with no extra idle timers. Noctalia's ordinary idle timings are retained. An existing independent idle daemon, special locked-state timeout or unreviewed runtime is left for review instead of being silently replaced. Go can be selected independently of Trailwatch.

`git pull` updates the checkout; successful installation updates the installed `cedar` command. If setup was canceled or failed, the previous installed version remains selected. An old installed command may still report “Omarchy activation requires omarchy.” Finish installing the current candidate above before running `cedar try` again. Do not install Omarchy to resolve that message.

Versions before `0.1.0-dev.8` could also stop with “Cannot inspect a same-user process” when an unrelated application protected its executable metadata. Update the checkout and rerun installation; no system permission changes are needed. CEDAR still refuses to switch a running release or change desktop providers when their identity or lock state cannot be verified.

If candidate 8 installs but **Try** reports “Expecting value: line 1 column 1”, update and reinstall **0.1.0-dev.9 or newer** using the existing-checkout command above, then choose **3**. With native Noctalia running, Quickshell normally has no instances and can return a plain-text message even in JSON mode; candidate 9 handles that response and Noctalia 5.2.1's actual version/configuration format. This does not require installing Omarchy, stopping Noctalia, or deleting your checkout. If another check fails, its message now identifies the affected interface; leave your existing desktop running.

If candidate 9 fails with **`CEDAR: 'root'`** after trial approval, update and reinstall **0.1.0-dev.10 or newer** with the existing-checkout command, then choose **3** again. This was a missing internal installation-path field, not a request to run as root. It occurred before the trial changed provider settings. Candidate 10 initializes that field before checking lock/IPC state and tests the complete approved workflow. Keep CEDAR only after its desktop appears and works; the installer then offers login activation separately.

For a provided private candidate archive:

1. Download the CEDAR archive.
2. Extract it and open a terminal in the extracted `cedar-shell` folder.
3. Run `bash ./install.sh`.

A checkout works too. Python 3.11+ and ordinary shell utilities bootstrap setup. Omarchy is not required or installed. A working Hyprland session is the prerequisite. With pacman, a missing Python can be installed only after approving the displayed full-upgrade plan. Quickshell is required for preview and desktop use. Automatic dependency preparation explicitly recognizes **Arch Linux and CachyOS on x86_64**, using existing configured repositories. It checks package availability before asking permission. No AUR helper or repository is silently added; no replacement compositor, driver or service provider is requested. A full system upgrade can update packages you already have.

Recommended fonts use readable fallbacks and **do not block installation**. From the checkout, `python3 scripts/distribution.py dependencies` shows the required and feature dependency plan. Add `--include-recommended` to also request available recommended font packages. Package changes require both `--approve-packages --approve-system-upgrade`; these flags authorize a full supported upgrade, not just the listed additions. On other distributions, provide dependencies through your own package manager. A machine with complete dependencies does not need automatic package support to install CEDAR.

The installer shows a dependency plan, asks before any package installation, then shows an **Install Only** plan and copies complete source into versioned user data storage; the extracted folder can then be removed. It preserves current preferences and desktop startup. A command collision or managed/symlinked target stops safely. `--plan` inspects without installation; `--approve-install-only` encodes that limited unattended choice. There is no generic yes flag authorizing takeover.

`cedar preview` opens an ordinary window with explicitly labeled fixtures, isolated preferences and local-only operation. It does not own notifications, replace wallpaper, reserve desktop space or lock the session.

After installation, open that preview with this command (it also works when `~/.local/bin` is not on your PATH):

```bash
"$HOME/.local/bin/cedar" preview
```

If the installer says **Desktop activation: not performed**, installation succeeded. Choose either the isolated preview above or the full desktop trial below.

### Use CEDAR on stock Hyprland or alongside Noctalia

The installer can walk through the following steps for you. They are also available as separate commands:

```bash
"$HOME/.local/bin/cedar" try
```

Approve the displayed plan. A 120-second trial opens the full CEDAR desktop. If you want to keep it, run:

```bash
"$HOME/.local/bin/cedar" keep
```

Then, optionally, enable it at login:

```bash
"$HOME/.local/bin/cedar" activate
```

To go back:

```bash
"$HOME/.local/bin/cedar" restore
```

`keep` and `activate` require a healthy trial first. Reinstalling alone does not activate the desktop. `cedar status` explains a failed or pending trial. Use the center Core for Quick Controls and the Go button for applications. CLI users can explicitly select the same controls with `cedar try --cedar-launcher --trailwatch` on native Noctalia 5.2.1. Plain `cedar try` preserves existing shortcuts and authentication. `cedar launcher` opens Go; `cedar lock` uses the selected locker; `cedar lock --suspend` waits for compositor lock coverage before requesting suspend.

On **stock Hyprland**, the adapter coordinates known Waybar/Mako/Dunst instances without replacing your compositor, portals, authentication agent, audio/network services, display layout or default apps. Existing Hyprlock and wallpaper providers are retained when detected. If no existing locker is configured, a local password-test window must succeed before Trailwatch is enabled. Enter passwords only in that local window. No PAM files are edited.

With **Noctalia**, CEDAR supplies the bar, Canopy, notifications and OSD while the existing Noctalia process keeps its locker, idle handling, authentication agent and wallpaper. Reviewed interfaces currently cover Quickshell-based **4.7.7** and native **5.2.1**; modified or unknown versions are refused safely. A separate Quickshell installation is still required for CEDAR even when Noctalia itself is native.

These adapters are **experimental**. Source inspection, offscreen UI checks and recovery fixtures have run; clean-machine/native Wayland handoff, login and secure-lock acceptance have not. Unknown providers or unavailable lock status leave the existing desktop in place and offer preview. See [portable integration](docs/PORTABILITY.md) for the exact boundaries.

An independent supervisor restores an unconfirmed trial after timeout or CEDAR failure. It defers changes while locked or when lock state cannot be verified. Later manual edits are preserved as recovery conflicts. No automatic logout, compositor restart or reboot occurs.

### Existing Omarchy installations

Omarchy remains an **optional compatibility adapter** for existing installations. Its commands, menu overlay and theme hooks are not prerequisites for the portable shell. Automatic detection uses a running Omarchy shell, not merely an installed directory. Its reviewed 4.0.4/Omacale path remains available; see [Omarchy integration](docs/OMARCHY-SESSION.md). Installing this release does not alter an independently running local source checkout.

## Recovery and updates

`cedar doctor` performs local read-only checks. `cedar restore`, `cedar rollback` and the standalone Python recovery tool use recorded hashes and preserve later edits. Read [offline recovery](docs/RECOVERY.md) before testing an installation. Uninstall keeps preferences, backups, source releases, recovery and shared dependencies by default.

Updates are manual: `cedar update ARCHIVE --signature SIGNATURE --trusted-key PUBLIC_KEY`. The key must be obtained through a separately trusted publisher channel; a checksum is not publisher authentication. No publisher identity has been established for this development candidate. The System Settings page offers a local archive/signature/key review action. No silent downloads or updates run in the background.

## Privacy and compatibility

Local-only mode is on by default. Weather and remote artwork require opt-in; once weather is on, its location comes from your public IP unless you choose a city. Clipboard history and window-title Trails remain opt-in. See [privacy](docs/PRIVACY.md), the [dependency manifest](data/dependencies.json), [component inventory](data/plugins.json), and [compatibility evidence](data/compatibility.json).

Arch/CachyOS package preparation is experimental: distribution detection and package failure/consent behavior have fixture tests; no clean CachyOS installation or live package upgrade has been tested here. The observed development environment is Arch with Hyprland 0.56.2, Quickshell 0.3.1 and Qt 6.11.2 on x86_64. Offscreen tests do not certify those versions for every host. Stock Hyprland and Noctalia adapters do not imply support for other compositors or untested hardware. [Release readiness](docs/RELEASE-READINESS.md) lists the incomplete and untested gates.

## Why CEDAR?

CEDAR takes inspiration from the cedar of Lebanon in Scripture: patient growth in Psalm 92:12 and cedar used in temple construction in 1 Kings 6:9–10. The project applies that imagery to steadfast faith and care in what we build; its technical acronym is its own creation. Field Station's ROOTED section and Settings → About include the approved locally stored KJV passages, including both John 3:16–17 verses. Everyone can use CEDAR without an account or religious acknowledgment.

## Maintainers

Build a private candidate with `python3 scripts/package_release.py /tmp/cedar-shell-development.tar.gz`, then test those exact bytes with `python3 tests/check_artifact.py /tmp/cedar-shell-development.tar.gz`. CI is read-only and never publishes releases or installs updates on users' machines. Public publication requires licensing, the documented acceptance gates and explicit owner approval.

When adding or removing source files, stage only the intended files, run `python3 scripts/update_source_inventory.py`, and review/stage `data/source-files.json`. CI verifies that the inventory matches tracked files. Installation and archive extraction do not require Git.
