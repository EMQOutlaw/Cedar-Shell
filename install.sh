#!/bin/sh
# CEDAR checkout installer: installs missing Arch packages, then opens the
# CEDAR Installer from this source tree.
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
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "CEDAR needs Python 3.11 or newer before its installer can run."
    if command -v pacman >/dev/null 2>&1; then
        echo "  sudo pacman -S --needed python"
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
