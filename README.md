# CEDAR

**A living desktop environment for Hyprland.** *Rooted in faith. Built with care.*

![Trailwatch lock screen](docs/images/trailwatch.png)

CEDAR is a complete desktop shell for Hyprland: a bar, quick controls, a calendar, searchable settings, notifications, a lock screen, network privacy tools and a Gaming Mode. It works offline and keeps your existing apps, displays and settings.

![The Strata bar](docs/images/bar.png)

<p>
  <img src="docs/images/quick-controls.png" alt="Quick Controls" width="49%">
  <img src="docs/images/calendar.png" alt="Calendar" width="49%">
</p>

![CEDAR Settings — Appearance and bundled themes](docs/images/settings.png)

## Requirements

- Arch Linux, CachyOS or Omarchy on x86_64; or Fedora Linux on x86_64
  (experimental: Hyprland and a current Quickshell are not in Fedora's own
  repositories, so you enable a repository that provides them first)
- A working Hyprland session

## Install

```bash
git clone https://github.com/EMQOutlaw/Cedar-Shell.git
cd Cedar-Shell
./install.sh
```

`install.sh` installs any missing packages with yay (or pacman if you don't have yay) on Arch-based systems, or with dnf on Fedora, asking before it does, then opens the CEDAR Installer. The installer shows a plan, changes nothing until you approve it, and backs up everything it touches first.

The packages it installs are listed at the top of [install.sh](install.sh). To manage packages yourself, run `CEDAR_SKIP_PACKAGES=1 ./install.sh`.

### Fedora RPM

There is no dnf repository. A project-owned RPM can be built from the release
archive with the spec in [packaging/fedora](packaging/fedora/cedar-shell.spec),
and releases published after this change carry one built on Fedora 44:

```bash
sudo dnf install ./cedar-shell-*.rpm
cedar installer
```

The package only places CEDAR under `/usr/share/cedar` and provides `cedar`
and `cedar-task-manager`; it has no scriptlets and changes nothing about your
desktop. `cedar installer`, run as your user, shows the plan and makes your
own copy under `~/.local/share/cedar`. The RPM is an unsigned build output:
check its `.sha256` next to it. See [Installation](docs/INSTALLATION.md#fedora)
and [Distribution packaging](docs/compatibility/PACKAGING.md#fedora).

## Preferred applications

CEDAR’s choices are **Strata** for files, **Zen Browser** for the web, **kitty**
for the terminal, and **VSCodium** for text and code. In **Settings → Default
apps**, installed choices appear first and have a **Use…** button to set their
associations and CEDAR launchers.

Your existing choices survive installation and updates. When no association is
set, CEDAR can use its installed preferred app; kitty is the first terminal
fallback after your selected terminal, XDG terminal provider and `$TERMINAL`.
These apps are optional and are not downloaded automatically.

## Task Manager

Open **Field Station → Task Manager**, find **CEDAR Task Manager** in your
application launcher, or run `cedar-task-manager`. It opens independently with
live hardware metrics, searchable processes, protected process controls and
user-service inspection. Field Station keeps its existing Overview.

See [Task Manager](docs/TASK-MANAGER.md) for source builds, optional NVIDIA
telemetry, shortcut registration and process-control limitations.

## Update

Open **Field Station → Update CEDAR**, or run:

```bash
~/.local/bin/cedar installer --update
```

## Undo

```bash
~/.local/bin/cedar restore                # go back to your previous desktop
~/.local/bin/cedar installer --uninstall  # remove CEDAR, keep your data and packages
```

Every install leaves a backup in `~/.local/state/cedar/installations/`.

## Learn more

[Installation](docs/INSTALLATION.md) · [Keybinds](docs/KEYBINDS.md) · [Calendar](docs/CALENDAR.md) · [Privacy](docs/PRIVACY.md) · [Shield](docs/SHIELD.md) · [Gaming Mode](docs/GAMING.md) · [Understory](docs/UNDERSTORY.md) · [Recovery](docs/RECOVERY.md) · [Troubleshooting](docs/TROUBLESHOOTING.md)

## License

The first-party source and artwork are unlicensed by the owner's decision; please do not redistribute them. Upstream notices are in [credits](docs/LICENSES.md).
