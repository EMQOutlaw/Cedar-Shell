#!/bin/sh
# CEDAR checkout installer: opens the CEDAR Installer from this source tree.
# The curl-pipe bootstrap lives in installer/bootstrap/install.sh.
set -eu
here="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
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
