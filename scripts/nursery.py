#!/usr/bin/env python3
"""Nursery: the plugin registry behind Settings › Nursery.

Companion services (CEDAR Ai first) describe themselves with a small JSON
descriptor in ~/.config/cedar/plugins.d/<id>.json:

    {"id": "cedar-ai", "name": "CEDAR Ai", "tagline": "...",
     "unit": "cedar-ai.service", "dashboard": "http://127.0.0.1:3650/",
     "setup": "cedar-ai setup", "docs": "..."}

This helper is the shell's only hand on them, and it is deliberately small:
  list                — descriptors + live status, JSON on stdout
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
import subprocess
import sys
import urllib.request
from pathlib import Path

SAFE_ARGV = re.compile(r"^[A-Za-z0-9_./:@%+=,~-]+$")
UNIT_NAME = re.compile(r"^[A-Za-z0-9_.@-]+\.service$")


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


def dashboard_ok(url: str) -> bool:
    if not (url.startswith("http://127.0.0.1") or url.startswith("http://localhost")
            or url.startswith("http://[::1]") or url.startswith("https://")):
        return False
    try:
        with urllib.request.urlopen(url, timeout=1) as r:
            return r.status == 200
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


def cmd_list(_args: list[str]) -> int:
    print(json.dumps({"plugins_dir": str(plugins_dir()),
                      "plugins": [status(d) for d in descriptors()]}))
    return 0


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
    out = subprocess.run(argv, capture_output=True, text=True, timeout=120)
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
    if not (url.startswith("http://127.0.0.1") or url.startswith("http://localhost")
            or url.startswith("http://[::1]") or url.startswith("https://")):
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
    if argv[0] == "open" and len(argv) == 2:
        return cmd_open(argv[1])
    print(json.dumps({"ok": False, "error": "usage: nursery.py list|enable <id>|disable <id>|open <id>"}))
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
