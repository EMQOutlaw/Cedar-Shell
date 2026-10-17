# CEDAR

**A living desktop environment for Hyprland.** *Rooted in faith. Built with care.*

![Trailwatch lock screen](docs/images/trailwatch.png)

CEDAR is a complete desktop shell for Hyprland: a bar, quick controls, a calendar, searchable settings, notifications, a lock screen, network privacy tools and a Gaming Mode. It works offline and keeps your existing apps, displays and settings.

![The Strata bar](docs/images/bar.png)

<p>
  <img src="docs/images/quick-controls.png" alt="Quick Controls" width="49%">
  <img src="docs/images/calendar.png" alt="Calendar" width="49%">
</p>

![Settings](docs/images/settings.png)

## Requirements

- Arch Linux, CachyOS, Omarchy or Fedora on x86_64
- A working Hyprland session
- Quickshell and the runtime dependencies available from your configured repositories

Package setup is experimental, especially on Fedora; clean-machine package
installation and native desktop acceptance are not yet certified.

## Install

### Native packages

CEDAR includes project-owned pacman and dnf repositories. **They require
maintainer activation before these commands work**; the URLs are not yet
claimed live. Follow [repository setup](docs/PACKAGING.md), including its
signing-key instructions, then use the command for your distribution:

```bash
# Arch Linux / CachyOS
sudo pacman -Syu cedar-shell

# Fedora
sudo dnf install cedar-shell
```

Then, as your normal desktop user:

```bash
cedar installer
```

Installing the package only places CEDAR under `/usr/share/cedar` and provides
`/usr/bin/cedar`; it does not change your desktop. The installer shows the plan
before creating your own copy under `~/.local/share/cedar`. Use
`cedar installer --no-gui` for the terminal flow. See [Installation](docs/INSTALLATION.md)
for Fedora prerequisites and Omarchy's package-update procedure.

### Source checkout

```bash
git clone https://github.com/EMQOutlaw/Cedar-Shell.git
cd Cedar-Shell
./install.sh
```

`install.sh` asks your package manager to install missing dependencies: yay or
pacman on Arch-based systems, dnf on Fedora. It then opens the CEDAR Installer,
which shows a plan before changing your desktop and backs up what it touches.
CEDAR adds no dependency repositories; Fedora users must configure providers
for Hyprland and Quickshell themselves.

The packages it installs are listed at the top of [install.sh](install.sh). To manage packages yourself, run `CEDAR_SKIP_PACKAGES=1 ./install.sh`.

## Update

Open **Field Station → Update CEDAR**, or run:

```bash
~/.local/bin/cedar installer --update
```

For a package installation, update `cedar-shell` through pacman or dnf first,
then run the command above to review and apply it to your per-user copy.
The **System package** channel does not download or upgrade packages itself.
[Stable and Development branches](docs/UPDATE-CHANNELS.md) remain available.

## Undo

```bash
~/.local/bin/cedar restore                # go back to your previous desktop
~/.local/bin/cedar installer --uninstall  # remove CEDAR, keep your data and packages
```

Every install leaves a backup in `~/.local/state/cedar/installations/`.

## Learn more

[Installation](docs/INSTALLATION.md) · [Packages and repositories](docs/PACKAGING.md) · [Update channels](docs/UPDATE-CHANNELS.md) · [Keybinds](docs/KEYBINDS.md) · [Calendar](docs/CALENDAR.md) · [Privacy](docs/PRIVACY.md) · [Shield](docs/SHIELD.md) · [Gaming Mode](docs/GAMING.md) · [Recovery](docs/RECOVERY.md) · [Troubleshooting](docs/TROUBLESHOOTING.md)

## License

The first-party source and artwork are unlicensed by the owner's decision; please do not redistribute them. Upstream notices are in [credits](docs/LICENSES.md).
