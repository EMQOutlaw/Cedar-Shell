#!/bin/sh
# CEDAR bootstrap — the only thing that runs from `curl -fsSL … | sh`.
#
# It gets the real installer onto this machine and nothing more:
#   1. checks that this is Linux on x86_64 with Python 3.11+
#   2. picks a published CEDAR release (CEDAR_VERSION or the latest release)
#   3. downloads the release archive and its .sha256 from GitHub Releases
#   4. verifies the checksum; a mismatch stops here, nothing is extracted
#   5. extracts it under ~/.cache/cedar/installer and runs the CEDAR Installer as you
#
# Every argument is passed to the installer: --dry-run, --no-gui, --yes, …
# CEDAR_FETCH_ONLY=1 stops after the verified download and prints
# CEDAR_SOURCE=<dir>; the installer's update stage uses that.
# Overrides: CEDAR_REPO (owner/name), CEDAR_VERSION (tag), CEDAR_CHANNEL=development
# (the dev source branch, over TLS only, with no release checksum).
set -eu

REPO="${CEDAR_REPO:-EMQOutlaw/Cedar-Shell}"
CHANNEL="${CEDAR_CHANNEL:-stable}"
case "$CHANNEL" in
    stable) BRANCH="${CEDAR_BRANCH:-main}" ;;
    development) BRANCH="${CEDAR_BRANCH:-dev}" ;;
    *) printf '%s\n' 'CEDAR: CEDAR_CHANNEL must be stable or development.' >&2; exit 1 ;;
esac
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/cedar/installer"
MAX_DOWNLOAD=603979776  # 576 MiB, including archive headers/padding

say() { printf '%s\n' "$*"; }
fail() { say "CEDAR: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || fail "$2"; }

[ "$(uname -s)" = "Linux" ] || fail "CEDAR runs on Linux."
[ "$(uname -m)" = "x86_64" ] || fail "CEDAR is published for x86_64 only; $(uname -m) is not supported yet."
[ "$(id -u)" -ne 0 ] || fail "Run this as your ordinary user, never root. CEDAR installs into your home directory."
if command -v curl >/dev/null 2>&1; then
    fetch_raw() { curl -fsSL --proto '=https' --proto-redir '=https' --tlsv1.2 --connect-timeout 20 --max-time 900 "$1"; }
elif command -v wget >/dev/null 2>&1; then
    fetch_raw() { wget -q --https-only --timeout=30 --tries=3 -O - "$1"; }
else
    fail "curl or wget is needed to download the installer."
fi

fetch() {
    # POSIX sh has no portable pipefail. Preserve producer failure separately;
    # the consumer enforces a byte cap even without HTTP Content-Length.
    (fetch_raw "$1" || { printf '%s\n' failed > "$2.failed"; exit 1; }) |
        python3 -c '
import os, sys
limit = int(sys.argv[2])
try:
    with open(os.open(sys.argv[1], os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "wb") as target:
        total = 0
        while block := sys.stdin.buffer.read(min(64 * 1024, limit + 1 - total)):
            total += len(block)
            if total > limit:
                raise ValueError("Download exceeds the permitted byte limit.")
            target.write(block)
except (OSError, ValueError) as error:
    print("CEDAR: " + str(error), file=sys.stderr)
    raise SystemExit(1)
' "$2" "${3:-$MAX_DOWNLOAD}" || return $?
    [ ! -e "$2.failed" ] || fail "Download failed; the incomplete file was not used."
}

fetch_text() {
    fetch "$1" "$DIR/release-metadata.json" 1048576 || return $?
    cat "$DIR/release-metadata.json"
}
if ! command -v python3 >/dev/null 2>&1 || ! python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)'; then
    say "CEDAR needs Python 3.11 or newer before its installer can run."
    if command -v pacman >/dev/null 2>&1; then say "  sudo pacman -S --needed python"; fi
    fail "Install Python with your package manager, then run this command again."
fi

# Keep this verifier embedded: a downloaded helper cannot authenticate itself.
# Each invocation owns a fresh private directory; queued installers keep their
# source bytes even when another bootstrap starts for the same version.
prepare() {
    python3 - "$@" <<'PYTHON'
import gzip
import hashlib
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import sys
import tarfile
import tempfile

MEMBERS = 10000
PAYLOAD = 512 * 1024 * 1024
STREAM = PAYLOAD + 64 * 1024 * 1024


def refuse(message):
    raise ValueError(message)


def workspace(cache, repo, branch, tag):
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repo):
        refuse('Invalid CEDAR_REPO; expected owner/name.')
    if (not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._/-]{0,127}', branch)
            or '..' in branch or '//' in branch):
        refuse('Invalid CEDAR_BRANCH.')
    if tag and not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._+-]{0,127}', tag):
        refuse('Invalid CEDAR_VERSION or release tag.')
    root = Path(cache)
    if not root.is_absolute():
        refuse('XDG_CACHE_HOME must be an absolute path.')
    for path in reversed((root, *root.parents)):
        if path.is_symlink():
            refuse('The installer cache must not traverse symlinks.')
        if not path.exists():
            path.mkdir(mode=0o700)
        info = path.lstat()
        if not stat.S_ISDIR(info.st_mode) or (info.st_mode & 0o022 and not info.st_mode & stat.S_ISVTX):
            refuse('The installer cache has an unsafe parent directory.')
    info = root.lstat()
    if info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) & 0o077:
        refuse('The installer cache must be private (0700) and owned by you.')
    print(tempfile.mkdtemp(prefix='fetch-', dir=root))


class BoundedStream:
    def __init__(self, raw):
        self.raw, self.count = raw, 0

    def read(self, size=-1):
        room = STREAM + 1 - self.count
        data = self.raw.read(room if size < 0 else min(size, room))
        self.count += len(data)
        if self.count > STREAM:
            refuse('Release archive exceeds the decompressed size limit.')
        return data


def extract(directory, asset, channel):
    root = Path(directory)
    archive = root / asset
    if archive.stat().st_size > STREAM:
        refuse('Release archive exceeds the download size limit.')
    if channel == 'stable':
        with (root / (asset + '.sha256')).open('rb') as checksum:
            text = checksum.read(4097)
        match = re.fullmatch(rb'([a-fA-F0-9]{64}) [ *]([^\r\n]+)\r?\n?', text)
        if not match or match[2].decode('utf-8') != asset:
            refuse('Download verification failed: checksum must name exactly this release archive.')
        with archive.open('rb') as source:
            actual = hashlib.file_digest(source, 'sha256').hexdigest()
        if actual != match[1].decode('ascii').lower():
            refuse('Download verification failed: release checksum mismatch.')
    tree = root / 'source'
    tree.mkdir(mode=0o700)
    count, total, seen, tops = 0, 0, set(), set()
    with gzip.open(archive, 'rb') as raw, tarfile.open(fileobj=BoundedStream(raw), mode='r|') as tar:
        for member in tar:
            count += 1
            total += member.size
            if count > MEMBERS or total > PAYLOAD:
                refuse('Release archive exceeds the member or payload limit.')
            rel = PurePosixPath(member.name)
            if (rel.is_absolute() or '..' in rel.parts or not rel.parts or '.git' in rel.parts
                    or rel in seen or not (member.isdir() or member.isfile()) or member.size < 0):
                refuse('Unsafe release archive entry.')
            seen.add(rel)
            tops.add(rel.parts[0])
            if len(tops) != 1 or (channel == 'stable' and tops != {'cedar-shell'}):
                refuse('The release archive must contain one source directory.')
            destination = tree / rel
            if member.isdir():
                destination.mkdir(parents=True, exist_ok=True)
            else:
                destination.parent.mkdir(parents=True, exist_ok=True)
                with tar.extractfile(member) as source, destination.open('xb') as target:
                    shutil.copyfileobj(source, target, length=64 * 1024)
                # Keep executables; never propagate special or group-writable bits.
                destination.chmod(0o755 if member.mode & 0o111 else 0o644)
    if len(tops) != 1:
        refuse('The release archive is empty.')
    source = tree / next(iter(tops))
    if not (source / 'installer/cedar_install.py').is_file():
        refuse('The downloaded CEDAR source has no installer.')
    archive.unlink()
    (root / (asset + '.sha256')).unlink(missing_ok=True)
    print(source)


try:
    if sys.argv[1] == 'workspace':
        workspace(*sys.argv[2:])
    else:
        extract(*sys.argv[2:])
except (OSError, ValueError, tarfile.TarError, EOFError) as error:
    print('CEDAR: ' + str(error), file=sys.stderr)
    raise SystemExit(1)
PYTHON
}

DIR="$(prepare workspace "$CACHE" "$REPO" "$BRANCH" "${CEDAR_VERSION:-}")"
# Only remove a directory this invocation created; keep successful handoffs.
KEEP=0
trap '[ "$KEEP" = 1 ] || rm -rf -- "$DIR"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if [ "$CHANNEL" = "development" ]; then
    say "Development channel: downloading the $BRANCH source branch over TLS (no release checksum)."
    fetch "https://codeload.github.com/$REPO/tar.gz/refs/heads/$BRANCH" "$DIR/source.tar.gz"
    SOURCE="$(prepare extract "$DIR" source.tar.gz "$CHANNEL")"
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
    case "$TAG" in
        ''|*[!A-Za-z0-9._+-]*|[!A-Za-z0-9]*) fail "Invalid release tag." ;;
    esac
    VERSION="${TAG#v}"
    ASSET="cedar-$VERSION-x86_64.tar.gz"
    BASE="https://github.com/$REPO/releases/download/$TAG"
    say "Downloading CEDAR $VERSION…"
    fetch "$BASE/$ASSET" "$DIR/$ASSET"
    fetch "$BASE/$ASSET.sha256" "$DIR/$ASSET.sha256" 4096
    say "Verifying the download…"
    SOURCE="$(prepare extract "$DIR" "$ASSET" "$CHANNEL")"
fi

[ -f "$SOURCE/installer/cedar_install.py" ] || fail "The downloaded CEDAR source has no installer."
KEEP=1
if [ "${CEDAR_FETCH_ONLY:-}" = "1" ]; then
    say "CEDAR_SOURCE=$SOURCE"
    exit 0
fi
say "Opening the CEDAR Installer…"
exec python3 "$SOURCE/installer/cedar_install.py" "$@"
