# Installing CEDAR

One command, one window, one plan you approve before anything changes.

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
(`.github/workflows/release.yml`) on a `v*` tag. They are SHA-256 verified;
signed release metadata is not published yet (see `cedar update` for the
signature-verified update path).

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
| `--update` | the Update stage in the installer window (or terminal with `--no-gui`): find the newest CEDAR (fast-forward of the checkout when one exists, else the latest verified release), fetch it with visible steps, explain any stop with what to do, then run its installer; an active CEDAR session is handed back and re-entered by the plan itself. See Updating below |
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
renders, one visible step at a time:

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
| Dependencies | `pacman -Syu --needed` for the missing manifest packages (on Omarchy `pacman -S --needed`, the way `omarchy pkg add` does, because Omarchy's pacman guard refuses a direct system upgrade and keeps those for `omarchy update`), through polkit (`pkexec`) when an agent is running or `sudo` on the terminal that started the installer; a failed transaction is explained (guard, stale databases, lock, file conflict, mirror, dismissed prompt, signature) | each package's command present afterwards |
| CEDAR runtime | `scripts/distribution.py install`: the versioned copy under `~/.local/share/cedar/releases/`, the `cedar` command, offline recovery, launcher entries, all journaled | release tree checksums |
| CEDAR shell | loads the required QML imports and renders five offscreen checks with the installed Quickshell and Qt | the checks pass |
| Configuration | translates monitor rules (`monitor`, `monitorv2`, `hl.monitor`), keyboard layout, preferred applications and the wallpaper library into `~/.config/cedar/hypr/settings.json` and `settings.json`; existing CEDAR settings win; with the keybinds option, copies CEDAR's keybinds (Caelestia layout, `docs/KEYBINDS.md`) beside them and loads them through CEDAR's journaled Hyprland loader | CEDAR's own validators; `hyprctl configerrors` |
| Session | the existing adapters: trial, health check, keep, enable at login (`cedar restore` undoes it) | the session record reads kept with login |
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

## Privilege and logs

The window and the engine run as you. Only the package transaction is
privileged, and only for that one command. Nothing runs the installer under
sudo. Logs are JSON lines under `~/.local/state/cedar/installer/logs/`, one
per run, with paths, hostnames, tokens and password-looking values
redacted; environment variables are never written.

## Support

| | |
| --- | --- |
| Supported | Arch Linux, CachyOS, Omarchy on x86_64 (pacman; package setup experimental per `data/dependencies.json`) |
| Experimental | other Arch-based distributions |
| Unsupported | everything else: CEDAR installs when its dependencies are already present; no package automation |

The package abstraction (`installer/providers/packages.py`) has apt, dnf
and zypper entries that say "unsupported" instead of guessing.

## Tests

`tests/test_installer.py` runs the engine against scripted machines:
distribution and environment detection, marker thresholds, conflict
classes, plan generation and digests, attention states, backup manifests
and selective restore, interrupted-run resume, grouped operations and the
dry-run CLI. `tests/check_installer_ui.py` renders every window stage from
fixture state and starts the real program root. Native package
transactions and session handoff on a clean machine remain to be exercised
on real hardware.
