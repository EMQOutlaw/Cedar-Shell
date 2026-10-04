#!/bin/sh
set -eu
if ! command -v python3 >/dev/null 2>&1; then
    echo "CEDAR needs Python 3 before its installer can run."
    if command -v pacman >/dev/null 2>&1 && command -v sudo >/dev/null 2>&1; then
        echo "Optional bootstrap: sudo pacman -Syu --needed python"
        echo "This performs Arch's full system upgrade and installs Python from configured repositories."
        echo "It changes packages, not desktop settings. Cancellation stops setup."
        printf 'Type INSTALL PYTHON AND UPGRADE to approve, or press Enter to cancel: '
        IFS= read -r cedar_bootstrap_reply </dev/tty || exit 1
        if [ "$cedar_bootstrap_reply" = 'INSTALL PYTHON AND UPGRADE' ]; then
            sudo pacman -Syu --needed python || exit 1
        else
            echo "Canceled. No desktop changes made."; exit 1
        fi
    else
        echo "Install Python through your distribution's package manager, then rerun bash ./install.sh."
        exit 1
    fi
fi
exec python3 "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/scripts/install.py" "$@"
