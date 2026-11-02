#!/usr/bin/env python3
"""Nursery: the plugin registry behind Settings › Nursery.

Companion services (CEDAR Ai first) describe themselves with a small JSON
descriptor in ~/.config/cedar/plugins.d/<id>.json:

    {"id": "cedar-ai", "name": "CEDAR Ai", "tagline": "...",
     "unit": "cedar-ai.service", "dashboard": "http://127.0.0.1:3650/",
     "setup": "cedar-ai setup", "docs": "..."}

This helper is the shell's only hand on them, and it is deliberately small:
  list                — descriptors + live status + installable known
                        companions, JSON on stdout
  install <id>        — run the known companion's installer (plants the
                        descriptor, a desktop entry, and the command)
  enable <id>         — via the descriptor's `setup --enable` when present,
  disable <id>          else systemctl --user verbs on its unit
  open <id>           — xdg-open the descriptor's dashboard URL

Descriptors are data, but `setup` is a command: it is argv-split, matched
against a strict character set, and run without a shell. A same-user process
could plant one — but a same-user process can already run anything; what this
guard prevents is a malformed or metachar-laced descriptor becoming a shell
line in the user's session.
"""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import urllib.parse
import urllib.request
from pathlib import Path

SAFE_ARGV = re.compile(r"^[A-Za-z0-9_./:@%+=,~-]+$")
UNIT_NAME = re.compile(r"^[A-Za-z0-9_.@-]+\.service$")

# Companions CEDAR can install for the user, even before a descriptor is
# planted. `installer` names a sibling script that speaks the install half of
# the ServiceRequest protocol ({"action": "install"} on stdin, one JSON
# object back); a successful install plants the descriptor itself.
KNOWN = {
    "cedar-ai": {
        "id": "cedar-ai",
        "name": "CEDAR Ai",
        "tagline": "The companion agent-OS: an exact, local-only map of the machine, a loopback dashboard, and Hermes wiring.",
        "unit": "cedar-ai.service",
        "dashboard": "http://127.0.0.1:3650/",
        "setup": "cedar-ai setup",
        "docs": "https://github.com/EMQOutlaw/cedar-ai",
        "installer": "cedar_ai_update.py",
    },
}


def plugins_dir() -> Path:
    cfg = os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config"
    return Path(cfg) / "cedar" / "plugins.d"


def state_dir(plugin_id: str) -> Path:
    state = os.environ.get("XDG_STATE_HOME") or Path.home() / ".local" / "state"
    return Path(state) / plugin_id


def descriptors() -> list[dict]:
    out = []
    directory = plugins_dir()
    if not directory.is_dir():
        return out
    for path in sorted(directory.glob("*.json")):
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            out.append({"id": path.stem, "name": path.stem, "error": "descriptor unreadable"})
            continue
        if not isinstance(data.get("id"), str) or not data["id"]:
            data["id"] = path.stem
        data.setdefault("name", data["id"])
        out.append(data)
    return out


def unit_file(unit: str) -> Path:
    cfg = os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config"
    return Path(cfg) / "systemd" / "user" / unit


def systemctl(*args: str) -> str:
    out = subprocess.run(["systemctl", "--user", *args],
                         capture_output=True, text=True, timeout=20)
    return out.stdout.strip()


def openable_dashboard(url: str) -> bool:
    """Exact-host loopback (or explicit https) — no prefix tricks, no userinfo."""
    try:
        parts = urllib.parse.urlsplit(url)
    except ValueError:
        return False
    if parts.username or parts.password:
        return False
    host = (parts.hostname or "").lower()
    if parts.scheme == "https":
        return bool(host)
    if parts.scheme != "http":
        return False
    return host in ("127.0.0.1", "localhost", "::1")


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


_NO_REDIRECT_OPENER = urllib.request.build_opener(_NoRedirect)


def dashboard_ok(url: str) -> bool:
    if not openable_dashboard(url):
        return False
    try:
        with _NO_REDIRECT_OPENER.open(url, timeout=1) as r:
            return r.status == 200
    except urllib.error.HTTPError as error:
        return error.code == 200
    except Exception:
        return False


def setup_state(plugin_id: str) -> str:
    try:
        data = json.loads((state_dir(plugin_id) / "setup.json").read_text(encoding="utf-8"))
        return str(data.get("state", ""))
    except (OSError, ValueError):
        return ""


def status(d: dict) -> dict:
    row = {k: d.get(k, "") for k in ("id", "name", "tagline", "unit", "dashboard", "setup", "docs")}
    if d.get("error"):
        row["error"] = d["error"]
        return row
    unit = d.get("unit", "")
    row["installed"] = bool(unit and UNIT_NAME.match(unit) and unit_file(unit).is_file())
    row["active"] = row["installed"] and systemctl("is-active", unit) == "active"
    row["enabled"] = row["installed"] and systemctl("is-enabled", unit) == "enabled"
    row["setup_state"] = setup_state(d["id"])
    row["dashboard_ok"] = dashboard_ok(d["dashboard"]) if d.get("dashboard") else False
    return row


def available_rows(planted_ids: set[str]) -> list[dict]:
    """Known companions without a planted descriptor: installable, not installed."""
    rows = []
    for plugin_id, known in KNOWN.items():
        if plugin_id in planted_ids:
            continue
        row = {k: known.get(k, "") for k in ("id", "name", "tagline", "unit", "dashboard", "setup", "docs")}
        row["available"] = True
        row["planted"] = False
        row["installed"] = False
        row["active"] = False
        row["enabled"] = False
        row["setup_state"] = setup_state(plugin_id)
        row["dashboard_ok"] = dashboard_ok(known["dashboard"]) if known.get("dashboard") else False
        rows.append(row)
    return rows


def cmd_list(_args: list[str]) -> int:
    rows = []
    for d in descriptors():
        row = status(d)
        row["available"] = d["id"] in KNOWN
        row["planted"] = True
        rows.append(row)
    rows.extend(available_rows({d["id"] for d in descriptors()}))
    print(json.dumps({"plugins_dir": str(plugins_dir()),
                      "plugins": rows}))
    return 0


def cmd_install(plugin_id: str) -> int:
    known = KNOWN.get(plugin_id)
    if not known:
        print(json.dumps({"ok": False, "error": "no such installable plugin"}))
        return 1
    installer = Path(__file__).resolve().parent / known["installer"]
    if not installer.is_file():
        print(json.dumps({"ok": False, "error": "the installer is missing: " + installer.name}))
        return 1
    child = subprocess.Popen([sys.executable, str(installer)],
                             stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                             stderr=subprocess.PIPE, text=True,
                             start_new_session=True)
    try:
        out_text, err_text = child.communicate(input='{"action": "install"}\n', timeout=600)
        out = subprocess.CompletedProcess(child.args, child.returncode, out_text, err_text)
    except subprocess.TimeoutExpired:
        # The installer holds the install flock; its pip/pipx descendants must
        # not outlive it or a retry could overlap a still-running mutation.
        import signal
        try:
            os.killpg(child.pid, signal.SIGTERM)
            child.wait(timeout=10)
        except (ProcessLookupError, subprocess.TimeoutExpired):
            try:
                os.killpg(child.pid, signal.SIGKILL)
                child.wait(timeout=10)
            except (ProcessLookupError, subprocess.TimeoutExpired):
                pass
        print(json.dumps({"ok": False, "error": "the install timed out and was stopped with its children; check status before retrying"}))
        return 1
    try:
        response = json.loads(out.stdout)
    except ValueError:
        print(json.dumps({"ok": False, "error": "the installer returned an unreadable response"}))
        return 1
    if response.get("ok"):
        print(json.dumps({"ok": True, "output": (response.get("data") or {}).get("output", "")}))
        return 0
    print(json.dumps({"ok": False, "error": str(response.get("error") or "the install did not complete")}))
    return 1


def user_env() -> dict:
    """The shell's PATH is a service PATH, not the user's: plugin setup
    commands call their own helpers (cedar-ai calls `hermes`). Hand the
    child the user's well-known bin directories appended to the current
    PATH. argv[0] is already resolved to an absolute path before this, so
    no PATH entry can substitute the plugin's own binary."""
    env = dict(os.environ)
    extras = [str(Path.home()/".local/bin"),
              str(Path.home()/".hermes/hermes-agent/.hermes/bin"),
              str(Path.home()/".hermes/bin")]
    current = (env.get("PATH") or os.defpath).split(os.pathsep)
    env["PATH"] = os.pathsep.join(current + [e for e in extras if e not in current])
    return env


def _run_setup(setup_cmd: str, flag: str, plugin_id: str = "") -> int:
    argv = setup_cmd.split() + [flag]
    if not all(SAFE_ARGV.match(a) for a in argv):
        print(json.dumps({"ok": False, "error": "the setup command failed the safety filter"}))
        return 1
    # A descriptor may only drive its OWN command: argv[0]'s basename must be
    # the plugin's id — a planted descriptor cannot borrow another binary.
    if plugin_id and Path(argv[0]).name != plugin_id:
        print(json.dumps({"ok": False, "error": "the setup command must be the plugin's own (" + plugin_id + ")"}))
        return 1
    # The shell's PATH is not the user's login PATH; a plugin installed for
    # the user typically lives in ~/.local/bin. Resolve honestly.
    resolved = shutil.which(argv[0])
    if resolved is not None:
        resolved = str(Path(resolved).resolve())  # PATH entries may be relative
    if resolved is None:
        local = Path.home()/".local/bin"/argv[0]
        if local.is_file():
            resolved = str(local)
    if resolved is None:
        print(json.dumps({"ok": False, "error": "the plugin's command is not installed or not on PATH: " + argv[0]}))
        return 1
    argv[0] = resolved
    try:
        out = subprocess.run(argv, capture_output=True, text=True, timeout=120, env=user_env())
    except subprocess.TimeoutExpired:
        print(json.dumps({"ok": False, "error": "the setup command timed out; it may have partially completed — check the plugin's status before retrying"}))
        return 1
    except OSError as error:
        print(json.dumps({"ok": False, "error": "the setup command could not start: " + str(error)}))
        return 1
    print(json.dumps({"ok": out.returncode == 0,
                      "output": (out.stdout + out.stderr).strip()[-2000:]}))
    return out.returncode


def _run_unit(unit: str, verb: str) -> int:
    if not UNIT_NAME.match(unit):
        print(json.dumps({"ok": False, "error": "the unit name failed the safety filter"}))
        return 1
    if verb == "enable":
        out = subprocess.run(["systemctl", "--user", "enable", "--now", unit],
                             capture_output=True, text=True, timeout=30)
    else:
        out = subprocess.run(["systemctl", "--user", "disable", "--now", unit],
                             capture_output=True, text=True, timeout=30)
    print(json.dumps({"ok": out.returncode == 0,
                      "output": (out.stdout + out.stderr).strip()[-2000:]}))
    return out.returncode


def _find(plugin_id: str) -> dict | None:
    for d in descriptors():
        if d["id"] == plugin_id:
            return d
    return None


def cmd_toggle(plugin_id: str, verb: str) -> int:
    d = _find(plugin_id)
    if not d:
        print(json.dumps({"ok": False, "error": "no such plugin"}))
        return 1
    if d.get("setup"):
        return _run_setup(d["setup"], "--" + verb, plugin_id=d["id"])
    if d.get("unit"):
        return _run_unit(d["unit"], verb)
    print(json.dumps({"ok": False, "error": "the descriptor names neither setup nor unit"}))
    return 1


def cmd_open(plugin_id: str) -> int:
    d = _find(plugin_id)
    url = (d or {}).get("dashboard", "")
    if not openable_dashboard(url):
        print(json.dumps({"ok": False, "error": "no openable dashboard URL"}))
        return 1
    subprocess.Popen(["xdg-open", url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print(json.dumps({"ok": True}))
    return 0


def main(argv: list[str]) -> int:
    if not argv or argv[0] == "list":
        return cmd_list(argv[1:])
    if argv[0] in ("enable", "disable") and len(argv) == 2:
        return cmd_toggle(argv[1], argv[0])
    if argv[0] == "install" and len(argv) == 2:
        return cmd_install(argv[1])
    if argv[0] == "open" and len(argv) == 2:
        return cmd_open(argv[1])
    print(json.dumps({"ok": False, "error": "usage: nursery.py list|enable <id>|disable <id>|open <id>"}))
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
