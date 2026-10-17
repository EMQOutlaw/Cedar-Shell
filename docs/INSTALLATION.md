# Installing CEDAR

Choose a native package, a published release, or a source checkout. Each leads
to the same installer and a plan you approve before your desktop changes.

## Native packages: Arch and Fedora

The `cedar-shell` packages are project-owned, not official Arch Linux or Fedora
repository inclusion. The hosted repositories require activation; see
[Packages and repositories](PACKAGING.md) for status, repository configuration
and signing-key setup. Once configured:

```bash
# Arch Linux / CachyOS
sudo pacman -Syu cedar-shell

# Fedora
sudo dnf install cedar-shell
```

On Omarchy, use `omarchy update` for system updates, then
`sudo pacman -S --needed cedar-shell`; its package guard reserves system
upgrades for Omarchy's own updater.

Fedora needs Hyprland, Quickshell and their dependencies available from
repositories you enabled yourself. Check the providers for your Fedora
release before installing; CEDAR does not enable COPR or any other dependency
repository. The reviewed dnf backend is experimental and stops if a required
package cannot be found. The native package is built in Fedora 43; that does
not certify a desktop installation on Fedora 43 or other releases.

Both native packages put the same release payload under `/usr/share/cedar`
and install `/usr/bin/cedar`. They have no install hooks or RPM scriptlets that
change your session, login configuration or home directory. Installing the
package alone does not start CEDAR. As your normal desktop user, run:

```bash
cedar installer
# Or use the same installer in the terminal:
cedar installer --no-gui
```

Review the plan. The installer makes a versioned per-user copy under
`~/.local/share/cedar/releases/`, selects it through
`~/.local/share/cedar/current`, and records the **System package** update
channel after successful first installation from the system tree. Do not run
the installer with sudo. Package upgrades refresh `/usr/share/cedar` only;
each user applies that update through the installer when ready.

If CEDAR was already installed from a checkout or release, adding the package
does not silently switch its remembered channel. Use
`cedar installer --update --channel package` to switch explicitly.

If an older per-user installation does not recognize the package channel,
start the newly installed package's installer directly once:

```bash
python3 /usr/share/cedar/installer/cedar_install.py --update --channel package
```

This still runs as your user and shows the normal installation plan.

## Published release or source checkout

```bash
curl -fsSL https://raw.githubusercontent.com/EMQOutlaw/Cedar-Shell/main/installer/bootstrap/install.sh | sh
```

```text
GitHub → bootstrap → CEDAR Installer opens → machine scan → plan → you review it
       → CEDAR installs → the result is verified → start CEDAR
```

Releases carry `cedar-<version>-x86_64.tar.gz` and its `.sha256`; the
bootstrap verifies them. Contributors can use the development channel, which
downloads the `dev` source branch over TLS without a release checksum:

```bash
curl -fsSL https://raw.githubusercontent.com/EMQOutlaw/Cedar-Shell/main/installer/bootstrap/install.sh | CEDAR_CHANNEL=development sh
```

From a checkout, `bash ./install.sh` opens the same installer from that tree.

## The bootstrap

`installer/bootstrap/install.sh` is the only thing that runs from the pipe,
and it is short enough to read before running. It checks for Linux on
x86_64, Python 3.11+, `tar` and `sha256sum`; picks a release (`CEDAR_VERSION`
or the latest published one on `CEDAR_REPO`); downloads
`cedar-<version>-x86_64.tar.gz` and its `.sha256` from GitHub Releases;
verifies the checksum and stops on a mismatch without extracting; extracts
under `~/.cache/cedar/installer/<version>/`; and runs the CEDAR Installer as
you. Every argument is passed through, so `… | sh -s -- --dry-run` works.
Nothing in it installs packages or touches your configuration.

Release assets are built by `scripts/package_release.py --release-assets`
from the reviewed source inventory and attached by the release workflow
(`.github/workflows/release.yml`) for a stable `vMAJOR.MINOR` tag matching
`VERSION`. That workflow also builds native packages from the same archive
and synchronizes the package repositories after both builds succeed. The
bootstrap verifies SHA-256 checksums, not signatures. Optional repository
signing is separate from these release assets; see [Packaging](PACKAGING.md).
The existing signed local-archive update command remains available.

## The installer

`cedar-install` (`installer/cedar_install.py`) is one engine with two front
ends. With a display and Quickshell it opens the **CEDAR Installer**
window; otherwise, or with `--no-gui`, it runs the same stages in the
terminal. When Quickshell is not installed yet the terminal flow installs
the dependencies first.

```text
CEDAR Installer window (installer.qml, installer/ui/)
        ↓ JSON lines
Installer state model (InstallerModel.qml)
        ↓
Installation engine (installer/engine/)
        ↓
System providers (installer/providers/, installer/migration/, scripts/)
```

No package installation logic lives in QML. The window sends commands
(`scan`, `plan`, `install`, `resume`, `restore`, …) to `cedar-install --serve`
and renders the operation records it sends back; it never parses terminal
output to guess progress.

| Flag | What it does |
| --- | --- |
| `--dry-run` | scan and build the plan with the same engine; change nothing (`--json` prints facts and plan) |
| `--yes` | apply the default plan without asking (terminal flow) |
| `--no-gui` / `--gui` | force the terminal flow or the window |
| `--resume` / `--start-over` | continue or discard an interrupted installation |
| `--restore` | restore the previous system from the latest backup |
| `--uninstall` | undo CEDAR-owned changes; keep packages and your data |
| `--repair` | verify the installed copy and reinstall what does not match |
| `--last-log` | print the most recent installer log |
| `--update` | check the remembered channel, prepare its source and open its installation plan; the package channel checks the system copy without downloading, while Stable and Development fetch an isolated branch snapshot. See Updating below |
| `--channel stable` / `--channel development` / `--channel package` | select the source explicitly; requires `--update` and remembers the choice only after successful installation |
| `--no-session`, `--cedar-launcher`, `--trailwatch`, `--fonts`, `--keybinds` / `--no-keybinds` | plan options |

After installation the same tool is available as `cedar installer …`.

## Stages

1. **Welcome.** Install CEDAR, or Advanced for the plan options.
2. **Scan.** One scan builds one fact model (`installer/engine/facts.py`):
   distribution and package manager, architecture, compositor and Hyprland
   version, Quickshell, GPU vendor and driver, display manager, network
   manager, Secure Boot, the Hyprland configuration and its includes,
   monitors, keyboard, preferred applications, wallpaper libraries,
   existing CEDAR, conflicting daemons, dependencies and an interrupted
   previous run. Every later decision derives from it; nothing re-detects.
3. **Existing environment.** What was found, what CEDAR keeps and what it
   replaces. Recognized by several markers each (a folder name alone never
   counts): plain Hyprland, Omarchy, HyDE, Caelestia, Noctalia, Ryoku,
   end-4, ML4W, JaKooLit, other Quickshell profiles, Waybar setups.
4. **Plan.** SYSTEM, MIGRATION and CEDAR sections, the options, and "Show
   technical details". The plan has a digest; an approved plan that no
   longer matches the machine is refused.
5. **Attention.** Risky states stop here with the actual risk: unsupported
   distribution with missing dependencies, insufficient space, a busy
   package database, a read-only data directory, no network when packages
   are needed, no way to ask for a password, a locked session, an active
   CEDAR session, a default Quickshell profile masking named shells.
   NVIDIA with Secure Boot and no loaded driver, and unreadable Hyprland
   includes, warn without blocking.
6. **Install.** Operations with real states (waiting, active, finished,
   warning, failed, skipped), the current step's detail, and "View details"
   for the technical log.
7. **Finish.** What was imported, where the backup is, Start CEDAR or
   Start Later.

## Updating

**Field Station → Update CEDAR** and `cedar installer --update` open the
CEDAR Installer window on an **Update** stage (`installer/engine/update.py`)
before anything else. It runs the same operation list the install stage
renders, one visible step at a time. Normal updates follow the last
successfully installed channel.

### System package

Update the system copy with your package manager first:

```bash
# Arch Linux / CachyOS
sudo pacman -Syu

# Fedora
sudo dnf upgrade cedar-shell
```

On Omarchy, use `omarchy update` instead. Then, as your normal user:

```bash
cedar installer --update --channel package
```

The updater checks `/usr/share/cedar`, prepares a verified snapshot, compares
it with your per-user copy, and hands it to the normal installer. It does not
run pacman or dnf, query the hosted repositories, or need Git or the network
for that check. “Up to date” means your copy matches the installed system
package, not necessarily the newest hosted release. The installation plan
may still need network access if runtime dependencies are missing.

Once the package channel is remembered, `cedar installer --update`,
**Field Station → Update CEDAR**, and `cedar update` use it by default.
`--no-gui` selects the terminal flow. See [Update channels](UPDATE-CHANNELS.md)
for switching between packages and branches.

### Stable and Development

These channels use GitHub source branches, not the package repository:

| Step | What it does |
| --- | --- |
| Source | the selected channel: Stable (`main`) or Development (`dev`) |
| Checkout | CEDAR's isolated Git store; your own checkout stays untouched |
| Fetch | retrieve the selected branch from GitHub and resolve its commit |
| Apply | prepare the exact source snapshot without switching or resetting your checkout |
| Installer | compare installed content, then hand the candidate to its installer: scan, review the plan, install |

When the selected branch's contents match the installed release, the stage
says **CEDAR is up to date** with Close, Reinstall anyway, and the other
branch's button: **Development Branch** or **Stable Branch**. The window
shows the installed and selected channel; successful installation remembers
the choice. Identical version numbers alone never establish that a branch
is current. See [Update channels](UPDATE-CHANNELS.md).

A stop shows what happened and the steps to resolve it. **Try again** keeps
the selected channel; the other channel remains available after a failed
check. A failed check never appears as “up to date.” In a terminal
(`--no-gui`) the same guidance prints as text; `--channel stable` and
`--channel development` select the branch explicitly.

### Operations

| Operation | What it does | Verified by |
| --- | --- | --- |
| System backup | copies the configuration the plan may touch into `~/.local/state/cedar/installations/<timestamp>/` with `manifest.json`, `restore.sh`, `config/`, `services.json`, `packages.json` | manifest and restore script present |
| Hand back the desktop | only when a CEDAR session is running: `cedar restore` returns the previous desktop (applications stay open) so the release can change; the session step starts CEDAR again at the end | the session record reads restored |
| Dependencies | missing manifest packages with `pacman -Syu --needed` on Arch/CachyOS, `pacman -S --needed` on Omarchy (system upgrades stay with `omarchy update`), or `dnf install` on Fedora (no system upgrade); through polkit (`pkexec`) when an agent is running or `sudo` on the terminal that started the installer. Only enabled repositories are used, and failures are explained | each package's command present afterwards |
| CEDAR runtime | `scripts/distribution.py install`: the versioned copy under `~/.local/share/cedar/releases/`, the `cedar` command, offline recovery, launcher entries, all journaled; then `~/.config/quickshell/cedar` is made a link to `~/.local/share/cedar/current`, so the shell on screen is always the installed release (a link to a source checkout is replaced and recorded in the backup; a real folder there is left alone and reported) | release tree checksums; the profile link |
| CEDAR shell | loads the required QML imports and renders five offscreen checks with the installed Quickshell and Qt | the checks pass |
| Configuration | translates monitor rules (`monitor`, `monitorv2`, `hl.monitor`), keyboard layout, preferred applications and the wallpaper library into `~/.config/cedar/hypr/settings.json` and `settings.json`; existing CEDAR settings win; with the keybinds option, copies CEDAR's keybinds (`docs/KEYBINDS.md`) beside them and loads them through CEDAR's journaled Hyprland loader | CEDAR's own validators; `hyprctl configerrors` |
| Session | a running CEDAR (its Quickshell profile or an installed release) is restarted with the new version through `scripts/cedar_session.py restart`, every install and update, whatever the options; otherwise on Omarchy `cedar_session.py start` (Omarchy's shell is retired once it has loaded); other environments use the existing adapters: trial, health check, keep, enable at login (`cedar restore` undoes it) | `cedar_session.py status` answers running and unlocked; or the session record reads kept with login |
| Verification | release tree, shell imports, command, launcher entry, session; writes `~/.config/cedar/installation.json` | — |

The shell check and the configuration step are independent and run
together; everything else is sequential. Package transactions are never
parallelized.

Session handoff exists for plain Hyprland (Waybar, Mako, Dunst paused),
Noctalia and Omarchy. For HyDE, Caelestia, Ryoku, end-4, ML4W, JaKooLit and
unrecognized Quickshell shells, CEDAR installs, migrates intent and opens as
a preview; the plan says so instead of pretending.

## Migration

Intent, not files. The parser (`installer/migration/intent.py`) follows
`source =` and `hl.include` by name within a bounded walk, never evaluates
configuration, and stops at dynamic expressions. Wildcard monitor rules are
left to the compositor; `auto` positions and `preferred` modes resolve from
the live compositor. Old shell widgets are never transplanted.

Conflicts are classified: **soft** (Waybar, Dunst, Mako, SwayNC, Hyprpaper,
swww, swaybg, launchers) are paused for the CEDAR session and restored;
**compatible** (hypridle, hyprlock, clipboard history, NetworkManager,
PipeWire, polkit) are left alone; **hard** states appear on the attention
screen. Nothing unrelated is uninstalled.

## Backup, resume, restore, uninstall

Every run records completion after each operation in
`~/.local/state/cedar/installer/state.json`. A run that is interrupted is
recognized on the next start: Resume, Start Over or Restore Previous System.

`--restore` leaves an active CEDAR session, puts back the copied files that
you have not edited since (edited files are listed and kept), restarts
paused services, and restores the program entry points from their
journals. `restore.sh` in the backup folder is the plain fallback.

`--uninstall` (or `cedar installer --uninstall`) undoes CEDAR-owned changes
only: the session, the `cedar` command and current-release link, launcher
entries, copied configuration. It never removes PipeWire, NetworkManager,
Quickshell or anything else installed as a dependency, and keeps your
preferences, wallpapers, backups and release files for review.

The native `cedar-shell` package is separate. Per-user uninstall does not
remove `/usr/share/cedar` or `/usr/bin/cedar`; removing the system package does
not undo your per-user desktop setup. To remove both, run
`cedar installer --uninstall` first, then use `sudo pacman -R cedar-shell` or
`sudo dnf remove cedar-shell` and review the package manager's proposed
transaction.

## Privilege and logs

The window and the engine run as you. Only the package transaction is
privileged, and only for that one command. Nothing runs the installer under
sudo. Logs are JSON lines under `~/.local/state/cedar/installer/logs/`, one
per run, with paths, hostnames, tokens and password-looking values
redacted; environment variables are never written.

## Support

| | |
| --- | --- |
| Reviewed package backends, experimental | Arch Linux, CachyOS and Omarchy on x86_64 (pacman); Fedora on x86_64 (dnf, with runtime providers configured by the user) |
| No reviewed package automation | other distributions and architectures: install dependencies yourself; this does not imply native desktop certification |

The package abstraction (`installer/providers/packages.py`) implements pacman
and dnf. apt and zypper remain unsupported. `data/dependencies.json` records
backend scope and evidence; [Release readiness](RELEASE-READINESS.md) lists
the outstanding native acceptance gates.

## Tests

`tests/test_installer.py` runs the engine against scripted machines:
distribution and environment detection, marker thresholds, conflict
classes, plan generation and digests, attention states, backup manifests
and selective restore, interrupted-run resume, grouped operations and the
dry-run CLI. `tests/check_installer_ui.py` renders every window stage from
fixture state and starts the real program root. Native package
transactions and session handoff on a clean machine remain to be exercised
on real hardware.
