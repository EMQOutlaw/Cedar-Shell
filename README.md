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

- Arch Linux, CachyOS or Omarchy on x86_64
- A working Hyprland session

## Install

**1. Install the dependencies.**

```bash
sudo pacman -Syu --needed \
  git python python-gobject python-dbus \
  hyprland quickshell qt6-declarative \
  networkmanager libnm libpulse polkit xdg-utils \
  brightnessctl power-profiles-daemon lm_sensors \
  wl-clipboard grim slurp jq cava \
  hypridle hyprsunset pacman-contrib \
  ttf-jetbrains-mono-nerd
```

The first two lines are required. The rest power individual features (network, audio, brightness, screenshots, clipboard, the audio visualizer, idle and night light), and CEDAR tells you if one is missing.

**2. Clone and run the installer.**

```bash
git clone https://github.com/EMQOutlaw/Cedar-Shell.git
cd Cedar-Shell
./install.sh
```

The installer scans your system, shows a plan, and changes nothing until you approve it. It backs up everything it touches first.

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

[Installation](docs/INSTALLATION.md) · [Keybinds](docs/KEYBINDS.md) · [Calendar](docs/CALENDAR.md) · [Privacy](docs/PRIVACY.md) · [Shield](docs/SHIELD.md) · [Gaming Mode](docs/GAMING.md) · [Recovery](docs/RECOVERY.md) · [Troubleshooting](docs/TROUBLESHOOTING.md)

## License

The first-party source and artwork are unlicensed by the owner's decision; please do not redistribute them. Upstream notices are in [credits](docs/LICENSES.md).
