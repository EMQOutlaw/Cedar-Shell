#!/bin/sh
# CEDAR checkout installer: installs missing Arch or Fedora packages, then
# opens the CEDAR Installer from this source tree.
# The curl-pipe bootstrap lives in installer/bootstrap/install.sh.
set -eu
here="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

# Everything CEDAR uses, all from the official Arch repositories. Keep in step
# with data/dependencies.json and the README.
packages="git python python-gobject python-dbus gcc pkgconf qt6-base
hyprland quickshell qt6-declarative
networkmanager libnm libpulse polkit xdg-utils
brightnessctl power-profiles-daemon lm_sensors
wl-clipboard grim slurp jq cava
hypridle hyprsunset pacman-contrib
ttf-jetbrains-mono-nerd"
# The same list with Fedora names (data/dependencies.json fedoraPackage). Fedora
# has no checkupdates and does not package the Nerd font, hyprsunset, or (since
# Fedora 42) hypridle. Hyprland is in Fedora's repositories; a current Quickshell
# is not (Fedora 44+ ships a 0.2.1 snapshot CEDAR cannot load), so enable a
# repository that provides Quickshell 0.3 or newer first. CEDAR adds no
# repository: packages none of your repositories provide are listed and skipped.
fedora_packages="git python3 python3-gobject python3-dbus gcc-c++ pkgconf-pkg-config qt6-qtbase-devel qt6-qtdeclarative-devel
hyprland quickshell qt6-qtdeclarative qt6-qtsvg
NetworkManager NetworkManager-libnm pulseaudio-utils polkit xdg-utils
brightnessctl power-profiles-daemon lm_sensors
wl-clipboard grim slurp jq cava"
# Optional Hyprland tools Fedora does not package (hypridle since Fedora 42,
# hyprsunset ever): installed only when a repository you enabled provides them.
fedora_optional="hypridle hyprsunset"
fedora_quickshell_floor="0.3"

# Plans, previews and information never change packages. CEDAR_SKIP_PACKAGES=1
# skips this step for people who manage packages themselves.
install_packages=1
for arg in "$@"; do
    case "$arg" in
        --plan|--dry-run|--json|-h|--help|--version|--last-log|--restore|--uninstall) install_packages=0 ;;
    esac
done
[ "${CEDAR_SKIP_PACKAGES:-}" = "1" ] && install_packages=0
[ "$(id -u)" = "0" ] && install_packages=0

if [ "$install_packages" = "1" ] && command -v pacman >/dev/null 2>&1; then
    # pacman -T prints only what is not installed, so an up-to-date system (and
    # every CEDAR update after the first install) skips straight to the installer.
    # shellcheck disable=SC2086
    missing="$(pacman -T $packages || true)"
    if [ -n "$missing" ]; then
        echo "CEDAR needs these packages:"
        echo "$missing" | sed 's/^/  /'
        # Arch does not support partial upgrades, so installing means -Syu.
        # shellcheck disable=SC2086
        if command -v yay >/dev/null 2>&1; then
            yay -Syu --needed $missing
        else
            sudo pacman -Syu --needed $missing
        fi
    fi
elif [ "$install_packages" = "1" ] && command -v dnf >/dev/null 2>&1 && command -v rpm >/dev/null 2>&1; then
    if [ -e /run/ostree-booted ]; then
        echo "This is an rpm-ostree system (Fedora Atomic). CEDAR does not layer packages; install them yourself with rpm-ostree, reboot, then rerun bash ./install.sh."
        exit 1
    fi
    # Test rpm's exit status, not its translated output. dnf resolves the
    # missing packages from the enabled repositories without a system upgrade.
    # dnf stops the whole transaction on a name no repository provides, so
    # those are set aside and named instead of taking the rest down with them.
    missing=""; unavailable=""
    for package in $fedora_packages $fedora_optional; do
        rpm -q "$package" >/dev/null 2>&1 && continue
        if dnf -q info "$package" >/dev/null 2>&1; then
            missing="$missing $package"
        else
            unavailable="$unavailable $package"
        fi
    done
    if [ -n "$unavailable" ]; then
        echo "None of your enabled repositories provide:$unavailable"
        echo "CEDAR adds no repository. hyprsunset (night light) and hypridle (idle lock) are optional; Quickshell is required."
    fi
    case " $missing " in *" quickshell "*)
        candidate="$(dnf -q repoquery --qf '%{version}\n' quickshell 2>/dev/null | tail -n 1 | sed 's/[^0-9.].*//')"
        if [ -n "$candidate" ] && [ "$(printf '%s\n%s\n' "$fedora_quickshell_floor" "$candidate" | sort -V | head -n 1)" != "$fedora_quickshell_floor" ]; then
            echo "Your repositories offer Quickshell $candidate; CEDAR needs $fedora_quickshell_floor or newer. Enable a repository with a current Quickshell (or build it), then rerun bash ./install.sh."
            exit 1
        fi
    ;; esac
    if [ -n "$missing" ]; then
        echo "CEDAR needs these packages:"
        for package in $missing; do echo "  $package"; done
        echo "Only your enabled repositories are used; no system upgrade is run."
        # shellcheck disable=SC2086
        sudo dnf install $missing
    fi
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "CEDAR needs Python 3.11 or newer before its installer can run."
    if command -v pacman >/dev/null 2>&1; then
        echo "  sudo pacman -S --needed python"
    elif command -v dnf >/dev/null 2>&1; then
        echo "  sudo dnf install python3"
    fi
    echo "Install Python with your distribution's package manager, then rerun bash ./install.sh."
    exit 1
fi
# The reviewed terminal flow keeps its exact automation flags (--plan,
# --approve-install-only, …) for scripts and the artifact check.
for arg in "$@"; do
    case "$arg" in
        --plan|--approve-install-only|--approve-packages|--approve-system-upgrade|--include-recommended|--source) CEDAR_CLASSIC_INSTALL=1 ;;
    esac
done
if [ "${CEDAR_CLASSIC_INSTALL:-}" = "1" ]; then
    exec python3 "$here/scripts/install.py" "$@"
fi
exec python3 "$here/installer/cedar_install.py" "$@"
