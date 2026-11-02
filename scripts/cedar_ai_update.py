#!/usr/bin/env python3
"""Install or update CEDAR Ai (EMQOutlaw/cedar-ai) from GitHub's most recent release.

Two faces:

* Service protocol (no arguments): read one JSON request from stdin and answer
  one JSON object on stdout, matching components/ServiceRequest.qml.
  {"action": "status"} reports the locally installed cedar-ai version without
  touching the network; {"action": "install"} runs the install and returns its
  full output, so Settings never needs a terminal.
* CLI: `cedar_ai_update.py install` runs in a terminal the user opened. It
  asks GitHub for the latest release and installs its source tarball for the
  current user — with pipx when present, otherwise with a private virtual
  environment under the data home (PEP 668 systems refuse pip --user). When
  no release is tagged yet it says so plainly and falls back to the newest
  `main` tarball. The terminal stays open until Enter so the outcome is
  always visible. Nothing runs unless the user pressed the button.

No credentials are needed or accepted; the repository is public.
"""
import fcntl
import importlib.metadata
import json
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.error
import urllib.request
from pathlib import Path

REPO = "EMQOutlaw/cedar-ai"
LATEST_RELEASE = f"https://api.github.com/repos/{REPO}/releases/latest"
MAIN_TARBALL = f"https://github.com/{REPO}/archive/refs/heads/main.tar.gz"
DISTRIBUTION = "cedar-ai"
STATE_DIR = Path(os.environ.get("XDG_STATE_HOME", Path.home()/".local/state"))/"cedar-ai/src"
DATA_DIR = Path(os.environ.get("XDG_DATA_HOME", Path.home()/".local/share"))/"cedar-ai"


def candidate_pythons():
    """Interpreters that could own the cedar-ai install, most specific first."""
    pipx_home = Path(os.environ.get("PIPX_HOME", Path.home()/".local/share/pipx"))
    return [pipx_home/"venvs/cedar-ai/bin/python",
            DATA_DIR/"venv/bin/python",
            Path(sys.executable)]


def installed_version():
    """Version string, None when absent everywhere. Probe failures (a broken
    interpreter, a timeout) are reported, never raised: callers must not
    mistake 'unreadable' for 'not installed'."""
    global probe_error
    probe_error = ""
    errors = []
    for python in candidate_pythons():
        python = Path(python)
        if not python.is_file():
            continue
        try:
            result = subprocess.run(
                [str(python), "-c",
                 "import importlib.metadata as m\n"
                 "try: print(m.version('cedar-ai'))\n"
                 "except m.PackageNotFoundError: pass\n"],
                capture_output=True, text=True, timeout=15)
        except (OSError, subprocess.SubprocessError) as error:
            errors.append(f"{python}: {error}")
            continue
        version = result.stdout.strip()
        if result.returncode == 0 and version:
            return version
        if result.returncode != 0:
            errors.append(f"{python}: {(result.stderr or result.stdout).strip()[:120]}")
    probe_error = "; ".join(errors)
    return None


probe_error = ""


def respond(ok, payload):
    key = "data" if ok else "error"
    print(json.dumps({"ok": ok, key: payload}))


def serve():
    try:
        request = json.loads(sys.stdin.readline() or "{}")
    except ValueError:
        respond(False, "Invalid request.")
        return 1
    action = request.get("action")
    if action == "status":
        respond(True, {"installed": installed_version(),
                       "probe_error": probe_error,
                       "command": cedar_ai_command()})
        return 0
    if action == "install":
        # Capture at the file-descriptor level: pip's own notices write to
        # fd 1 directly and would corrupt the single-JSON protocol.
        saved_out, saved_err = os.dup(1), os.dup(2)
        with tempfile.TemporaryFile(mode="w+") as capture:
            os.dup2(capture.fileno(), 1)
            os.dup2(capture.fileno(), 2)
            try:
                code = install()
            except (OSError, tarfile.TarError, subprocess.SubprocessError) as error:
                print(f"The install failed: {error}")
                code = 1
            finally:
                sys.stdout.flush()
                sys.stderr.flush()
                os.dup2(saved_out, 1)
                os.dup2(saved_err, 2)
                os.close(saved_out)
                os.close(saved_err)
            capture.seek(0)
            output = capture.read(262144)
        if code == 0:
            respond(True, {"output": output,
                           "installed": installed_version(),
                           "command": cedar_ai_command()})
        else:
            respond(False, output.strip() or "The install did not complete.")
        return code
    respond(False, "Unknown action.")
    return 1


def cedar_ai_command():
    candidate = Path.home()/".local/bin/cedar-ai"
    if candidate.exists():
        return str(candidate)
    return shutil.which("cedar-ai") or ""


def fetch_json(url):
    request = urllib.request.Request(url, headers={"User-Agent": "cedar-shell/cedar-ai-update"})
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.loads(response.read().decode())


def latest_release():
    """(tag, tarball_url) for the newest release, or None when none is tagged."""
    try:
        data = fetch_json(LATEST_RELEASE)
    except urllib.error.HTTPError as error:
        if error.code == 404:
            return None
        raise
    return data.get("tag_name") or "release", data["tarball_url"]


def ensure_installer(source):
    """Install `source` (an extracted release tree) for the current user.

    Arch and other PEP 668 systems refuse `pip install --user`, so the
    dependency is an installer, not pip itself: pipx when the user has it,
    otherwise a managed virtual environment under the data home with the
    cedar-ai command linked into ~/.local/bin. Returns the cedar-ai command
    path, or None after printing the honest failure.
    """
    pipx = shutil.which("pipx")
    if pipx:
        print("Installing with pipx …")
        result = subprocess.run([pipx, "install", "--force", str(source)])
        if result.returncode == 0:
            # Retire our own managed environment so the status probe cannot
            # read back a stale version from it; pipx owns the command now.
            shutil.rmtree(DATA_DIR/"venv", ignore_errors=True)
            return str(Path.home()/".local/bin/cedar-ai")
        print("pipx reported a failure; see the output above.")
        return None
    venv = DATA_DIR/"venv"
    python = venv/"bin/python"
    if not (python.is_file() and subprocess.run(
            [str(python), "-m", "pip", "--version"], capture_output=True).returncode == 0):
        if venv.exists():
            print("The existing environment is incomplete; rebuilding it …")
            shutil.rmtree(venv)
        staging = DATA_DIR/("venv.tmp-" + str(os.getpid()))
        print(f"Creating a private Python environment at {venv} …")
        result = subprocess.run([sys.executable, "-m", "venv", str(staging)])
        if result.returncode != 0:
            shutil.rmtree(staging, ignore_errors=True)
            print("Could not create a virtual environment.")
            return None
        staging.replace(venv)
    print("Installing with the environment's pip …")
    result = subprocess.run(
        [str(python), "-m", "pip", "install", "--upgrade", str(source)],
    )
    if result.returncode != 0:
        print("pip reported a failure; see the output above.")
        return None
    link = Path.home()/".local/bin/cedar-ai"
    link.parent.mkdir(parents=True, exist_ok=True)
    if link.is_symlink() or link.exists():
        link.unlink()
    link.symlink_to(venv/"bin/cedar-ai")
    return str(link)


DESCRIPTOR = {
    "id": "cedar-ai",
    "name": "CEDAR Ai",
    "tagline": "The companion agent-OS: an exact, local-only map of the machine, a loopback dashboard, and Hermes wiring.",
    "unit": "cedar-ai.service",
    "dashboard": "http://127.0.0.1:3650/",
    "setup": "cedar-ai setup",
    "docs": "https://github.com/EMQOutlaw/cedar-ai",
}

DESKTOP_ENTRY = """[Desktop Entry]
Type=Application
Name=CEDAR Ai
Comment=The CEDAR companion agent-OS — start the local dashboard and open it
Exec=sh -c "systemctl --user start cedar-ai.service 2>/dev/null; exec xdg-open http://127.0.0.1:3650/"
Categories=Utility;
Keywords=cedar;ai;dashboard;
StartupNotify=false
"""


def config_dir():
    return Path(os.environ.get("XDG_CONFIG_HOME", Path.home()/".config"))


def plant_descriptor():
    """Add cedar-ai to the Nursery (~/.config/cedar/plugins.d/). An existing
    descriptor keeps any keys this installer does not own. Directories are
    0700 and the file 0600 (docs/SECURITY.md), replaced atomically."""
    directory = config_dir()/"cedar/plugins.d"
    directory.mkdir(parents=True, exist_ok=True)
    path = directory/"cedar-ai.json"
    existing = {}
    if path.is_file():
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            if isinstance(data, dict):
                existing = data
        except ValueError:
            path.rename(path.with_suffix(".json.bak"))
    merged = {**existing, **DESCRIPTOR}
    staging = path.with_suffix(".json.tmp")
    staging.write_text(json.dumps(merged, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    staging.chmod(0o600)
    staging.replace(path)
    directory.chmod(0o700)
    directory.parent.chmod(0o700)
    path.chmod(0o600)
    return path


def plant_desktop_entry():
    """Add CEDAR Ai to the Applications menu: starts the dashboard unit when
    it exists, then opens the loopback dashboard."""
    directory = Path(os.environ.get("XDG_DATA_HOME", Path.home()/".local/share"))/"applications"
    directory.mkdir(parents=True, exist_ok=True)
    path = directory/"cedar-ai.desktop"
    path.write_text(DESKTOP_ENTRY, encoding="utf-8")
    return path


def plant_unit(command):
    """Write the dashboard's user unit without enabling it (off by default,
    matching cedar-ai's own posture) so the Applications entry and the
    Nursery's Enable button work from a fresh install. An existing unit is
    the user's and is left alone. The ExecStart goes through the stable
    ~/.local/bin/cedar-ai command, whichever installer owns it."""
    directory = config_dir()/"systemd/user"
    path = directory/"cedar-ai.service"
    if path.exists():
        return None
    directory.mkdir(parents=True, exist_ok=True)
    path.write_text(
        "[Unit]\n"
        "Description=CEDAR Ai dashboard (loopback vault view)\n"
        "After=graphical-session.target\n\n"
        "[Service]\n"
        "ExecStart=%h/.local/bin/cedar-ai serve\n"
        "Restart=on-failure\n"
        "RestartSec=5\n\n"
        "[Install]\n"
        "WantedBy=default.target\n",
        encoding="utf-8")
    subprocess.run(["systemctl", "--user", "daemon-reload"], capture_output=True, timeout=20)
    return path


def pause_when_interactive():
    if sys.stdin.isatty():
        try:
            input("\nPress Enter to close. ")
        except EOFError:
            pass


def install():
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    lock = open(STATE_DIR/"install.lock", "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        print("Another install is already running; wait for it to finish.")
        return 1
    try:
        return _install_locked()
    finally:
        fcntl.flock(lock, fcntl.LOCK_UN)
        lock.close()


def _install_locked():
    print("CEDAR Ai — install from GitHub")
    print(f"Repository: {REPO}")
    try:
        release = latest_release()
    except (urllib.error.URLError, TimeoutError, ValueError) as error:
        print(f"Could not reach GitHub: {error}")
        return 1
    if release:
        label, tarball = release
        print(f"Latest release: {label}")
    else:
        label, tarball = "main (no release is tagged yet)", MAIN_TARBALL
        print("No release is tagged yet; installing the newest main instead.")
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    archive = STATE_DIR/"cedar-ai.tar.gz"
    print(f"Downloading {tarball}")
    try:
        with urllib.request.urlopen(
            urllib.request.Request(tarball, headers={"User-Agent": "cedar-shell/cedar-ai-update"}),
            timeout=60,
        ) as response:
            archive.write_bytes(response.read(50 * 1024 * 1024 + 1))
        if archive.stat().st_size > 50 * 1024 * 1024:
            archive.unlink()
            print("The download exceeded the 50 MB budget; nothing was installed.")
            return 1
    except (urllib.error.URLError, TimeoutError) as error:
        print(f"Download failed: {error}")
        return 1
    with tempfile.TemporaryDirectory(dir=STATE_DIR) as staging:
        with tarfile.open(archive) as bundle:
            bundle.extractall(staging, filter="data")
        roots = [p for p in Path(staging).iterdir() if (p/"pyproject.toml").is_file()]
        if not roots:
            print("The archive did not contain a pyproject.toml; nothing was installed.")
            return 1
        source = roots[0]
        command = ensure_installer(source)
        if command is None:
            return 1
    descriptor = plant_descriptor()
    entry = plant_desktop_entry()
    unit = plant_unit(command)
    print(f"Nursery descriptor: {descriptor}")
    print(f"Applications entry: {entry}")
    if unit:
        print(f"Dashboard unit (not enabled): {unit}")
    version = installed_version()
    command = cedar_ai_command()
    print()
    if version:
        print(f"Installed cedar-ai {version}.")
    else:
        print("The install finished but the cedar-ai version could not be read back.")
    if command:
        print(f"Command: {command}  (ensure ~/.local/bin is on PATH)")
        print("Next: cedar-ai scan, then cedar-ai serve or cedar-ai ask.")
    return 0


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "install":
        code = install()
        pause_when_interactive()
        return code
    if len(sys.argv) > 1:
        print(__doc__)
        return 2
    return serve()


if __name__ == "__main__":
    raise SystemExit(main())
