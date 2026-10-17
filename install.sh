#!/bin/sh
# CEDAR checkout installer: installs missing Arch or Fedora packages, then
# opens the CEDAR Installer from this source tree.
# The curl-pipe bootstrap lives in installer/bootstrap/install.sh.
set -eu
here="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

# Everything CEDAR uses, all from the official Arch repositories. Keep in step
# with data/dependencies.json and the README.
packages="git python python-gobject python-dbus
hyprland quickshell qt6-declarative
networkmanager libnm libpulse polkit xdg-utils
brightnessctl power-profiles-daemon lm_sensors
wl-clipboard grim slurp jq cava
hypridle hyprsunset pacman-contrib
ttf-jetbrains-mono-nerd"
# The same list with Fedora names (data/dependencies.json fedoraPackage). Fedora
# has no checkupdates and does not package the Nerd font. Runtime package
# availability varies by Fedora release; any additional repository must be
# enabled by the user. CEDAR adds no repository.
fedora_packages="git python3 python3-gobject python3-dbus
hyprland quickshell qt6-qtdeclarative
NetworkManager NetworkManager-libnm pulseaudio-utils polkit xdg-utils
brightnessctl power-profiles-daemon lm_sensors
wl-clipboard grim slurp jq cava
hypridle hyprsunset"

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
    # Test rpm's exit status, not its translated output. dnf resolves the
    # missing packages from enabled repositories without a full system upgrade.
    # shellcheck disable=SC2086
    missing="$(for package in $fedora_packages; do
        rpm -q "$package" >/dev/null 2>&1 || printf '%s\n' "$package"
    done)"
    if [ -n "$missing" ]; then
        echo "CEDAR needs these packages:"
        echo "$missing" | sed 's/^/  /'
        echo "Runtime package availability varies by Fedora release. Ensure your enabled repositories provide the listed packages; CEDAR adds no repository."
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
