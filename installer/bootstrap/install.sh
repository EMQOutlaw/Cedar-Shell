#!/bin/sh
# CEDAR bootstrap — the only thing that runs from `curl -fsSL … | sh`.
#
# It gets the real installer onto this machine and nothing more:
#   1. checks that this is Linux on x86_64 with Python 3.11+, tar and sha256sum
#   2. picks a published CEDAR release (CEDAR_VERSION or the latest release)
#   3. downloads the release archive and its .sha256 from GitHub Releases
#   4. verifies the checksum; a mismatch stops here, nothing is extracted
#   5. extracts it under ~/.cache/cedar/installer and runs the CEDAR Installer as you
#
# Every argument is passed to the installer: --dry-run, --no-gui, --yes, …
# CEDAR_FETCH_ONLY=1 stops after the verified download and prints
# CEDAR_SOURCE=<dir>; the installer's update stage uses that.
# Overrides: CEDAR_REPO (owner/name), CEDAR_VERSION (tag), CEDAR_CHANNEL=development
# (the current source branch, over TLS only, with no checksum: for contributors).
set -eu

REPO="${CEDAR_REPO:-EMQOutlaw/Cedar-Shell}"
CHANNEL="${CEDAR_CHANNEL:-stable}"
BRANCH="${CEDAR_BRANCH:-main}"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/cedar/installer"

say() { printf '%s\n' "$*"; }
fail() { say "CEDAR: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || fail "$2"; }

[ "$(uname -s)" = "Linux" ] || fail "CEDAR runs on Linux."
[ "$(uname -m)" = "x86_64" ] || fail "CEDAR is published for x86_64 only; $(uname -m) is not supported yet."
[ "$(id -u)" -ne 0 ] || fail "Run this as your ordinary user, never root. CEDAR installs into your home directory."
need tar "tar is needed to unpack the installer."
need sha256sum "sha256sum (coreutils) is needed to verify the download."
if command -v curl >/dev/null 2>&1; then
    fetch() { curl -fsSL --proto '=https' --tlsv1.2 -o "$2" "$1"; }
    fetch_text() { curl -fsSL --proto '=https' --tlsv1.2 "$1"; }
elif command -v wget >/dev/null 2>&1; then
    fetch() { wget -q --https-only -O "$2" "$1"; }
    fetch_text() { wget -q --https-only -O - "$1"; }
else
    fail "curl or wget is needed to download the installer."
fi
if ! command -v python3 >/dev/null 2>&1 || ! python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)'; then
    say "CEDAR needs Python 3.11 or newer before its installer can run."
    if command -v pacman >/dev/null 2>&1; then say "  sudo pacman -S --needed python"; fi
    fail "Install Python with your package manager, then run this command again."
fi

mkdir -p "$CACHE"
chmod 700 "$CACHE"

if [ "$CHANNEL" = "development" ]; then
    say "Development channel: downloading the $BRANCH source branch over TLS (no release checksum)."
    DIR="$CACHE/development"
    rm -rf "$DIR"; mkdir -p "$DIR"
    fetch "https://codeload.github.com/$REPO/tar.gz/refs/heads/$BRANCH" "$DIR/source.tar.gz"
    tar -xzf "$DIR/source.tar.gz" -C "$DIR" --no-same-owner
    SOURCE="$(find "$DIR" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
else
    if [ -n "${CEDAR_VERSION:-}" ]; then
        TAG="$CEDAR_VERSION"
    else
        TAG="$(fetch_text "https://api.github.com/repos/$REPO/releases/latest" | sed -n 's/^[[:space:]]*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
        if [ -z "$TAG" ]; then
            say "No published CEDAR release was found for $REPO yet."
            say "To install the current source branch instead, run:"
            say "  curl -fsSL https://raw.githubusercontent.com/$REPO/$BRANCH/installer/bootstrap/install.sh | CEDAR_CHANNEL=development sh"
            exit 1
        fi
    fi
    VERSION="${TAG#v}"
    ASSET="cedar-$VERSION-x86_64.tar.gz"
    BASE="https://github.com/$REPO/releases/download/$TAG"
    DIR="$CACHE/$VERSION"
    mkdir -p "$DIR"
    say "Downloading CEDAR $VERSION…"
    fetch "$BASE/$ASSET" "$DIR/$ASSET"
    fetch "$BASE/$ASSET.sha256" "$DIR/$ASSET.sha256"
    say "Verifying the download…"
    if ! (cd "$DIR" && sha256sum -c --quiet "$ASSET.sha256"); then
        rm -f "$DIR/$ASSET"
        fail "Download verification failed. CEDAR did not install the downloaded file because its checksum did not match. Run the command again to retry; if it keeps failing, the release or your network path needs checking."
    fi
    rm -rf "$DIR/cedar-shell"
    tar -xzf "$DIR/$ASSET" -C "$DIR" --no-same-owner
    SOURCE="$DIR/cedar-shell"
fi

[ -f "$SOURCE/installer/cedar_install.py" ] || fail "The downloaded CEDAR source has no installer."
if [ "${CEDAR_FETCH_ONLY:-}" = "1" ]; then
    say "CEDAR_SOURCE=$SOURCE"
    exit 0
fi
say "Opening the CEDAR Installer…"
exec python3 "$SOURCE/installer/cedar_install.py" "$@"
