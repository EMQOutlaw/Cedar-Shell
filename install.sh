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
# has no checkupdates and does not package the Nerd font, and Workstation's
# tuned-ppd conflicts with power-profiles-daemon (it serves the same D-Bus
# interface), so that one is left to you. Hyprland, hypridle, hyprsunset and a
# current Quickshell are not in Fedora's own repositories: enable a repository
# that provides them first. CEDAR adds no repository.
fedora_packages="git python3 python3-gobject python3-dbus gcc-c++ pkgconf-pkg-config qt6-qtbase-devel qt6-qtdeclarative-devel
hyprland quickshell qt6-qtdeclarative qt6-qtsvg
NetworkManager NetworkManager-libnm pulseaudio-utils polkit xdg-utils
brightnessctl lm_sensors
wl-clipboard grim slurp jq cava
hypridle hyprsunset"

# Which family this is comes from /etc/os-release (ID and ID_LIKE), the same
# answer scripts/system_family.py gives the installer; a package manager that
# merely happens to be installed never decides. Unknown families skip packages.
family=""
if [ -r /etc/os-release ]; then
    ids="$(. /etc/os-release 2>/dev/null; printf '%s %s' "${ID:-}" "${ID_LIKE:-}" | tr '[:upper:]' '[:lower:]')"
    case " $ids " in
        *" arch "*) family=arch ;;
        *" fedora "*) family=fedora ;;
    esac
fi

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

if [ "$install_packages" = "1" ] && [ "$family" = "arch" ] && command -v pacman >/dev/null 2>&1; then
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
elif [ "$install_packages" = "1" ] && [ "$family" = "fedora" ] && command -v dnf >/dev/null 2>&1 && command -v rpm >/dev/null 2>&1; then
    # Test rpm's exit status, not its translated output. dnf resolves the
    # missing packages from the enabled repositories without a system upgrade.
    missing="$(for package in $fedora_packages; do
        rpm -q "$package" >/dev/null 2>&1 || printf '%s\n' "$package"
    done)"
    if [ -n "$missing" ]; then
        echo "CEDAR needs these packages:"
        echo "$missing" | sed 's/^/  /'
        echo "Only your enabled repositories are used; CEDAR adds none. Hyprland and Quickshell need a repository you enable yourself."
        # shellcheck disable=SC2086
        sudo dnf install $missing
    fi
fi

if [ "$install_packages" = "1" ] && [ -z "$family" ]; then
    echo "CEDAR has no automatic package setup for this distribution; install the packages listed at the top of install.sh yourself if the installer reports any missing."
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "CEDAR needs Python 3.11 or newer before its installer can run."
    if [ "$family" = "arch" ]; then
        echo "  sudo pacman -S --needed python"
    elif [ "$family" = "fedora" ]; then
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
