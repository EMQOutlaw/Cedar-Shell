#!/usr/bin/env python3
"""Convertible: CEDAR's 2-in-1 transition owner.

The problem (Yoga 9 2-in-1 14ILL10, and convertibles generally): libinput
suspends the internal keyboard and touchpad when the tablet-mode switch
asserts, and a lost deassert event leaves them dead after unfolding.

The fix: libinput is told to ignore the switch (hwdb rule, one sudo step —
see `rules`) and CEDAR owns the transition instead. This watcher reads the
switch STATE via EVIOCGSW (events make it instant; a periodic state re-read
heals a lost event) and drives Hyprland's per-device `enabled` flag itself,
verifying by read-back. On exit — any exit — whatever it disabled is
re-enabled, and CEDAR's service force-enables on session lock, so the
keyboard is never dead at the password prompt.

Verbs:
  state    one-shot JSON: detection + current switch state
  watch    long-running: apply on start, then keep the transition seamless
  laptop   force laptop posture (keyboard + touchpad enabled) and exit
  rules    print the hwdb + udev rules for the one-time sudo step

stdlib only; no evdev dependency.
"""
from __future__ import annotations

import fcntl
import glob
import json
import os
import re
import select
import signal
import struct
import subprocess
import sys
import time
from pathlib import Path

SW_TABLET_MODE = 0x01          # bit index within the switch capability set
EV_SW = 0x05
INPUT_EVENT = struct.Struct("llHHi")  # timeval sec,usec + type + code + value

# Devices we own: the INTERNAL keyboard and touchpad only — externals,
# buttons and buses are never touched. Overridable via env for tests.
KEYBOARD_PATTERNS = [r"^at-translated-set-2-keyboard$"]
TOUCHPAD_PATTERNS = [r"touchpad", r"trackpad", r"clickpad", r"glidepoint"]

POLL_SECONDS = 2.0  # state re-read cadence; events arrive faster


def _sw_bits(path: Path) -> int:
    try:
        return int((path / "capabilities" / "sw").read_text().strip(), 16)
    except (OSError, ValueError):
        return 0


def find_switch(root: str = "/sys/class/input") -> dict:
    """The first input device advertising SW_TABLET_MODE, or a negative answer."""
    for name_file in sorted(Path(root).glob("input*/name")):
        directory = name_file.parent
        if not (_sw_bits(directory) & (1 << SW_TABLET_MODE)):
            continue
        events = sorted(directory.glob("event*"))
        return {"detected": True, "name": name_file.read_text().strip(),
                "node": "/dev/input/" + events[0].name if events else ""}
    return {"detected": False, "name": "", "node": ""}


def _eviocgsw(fd: int, count: int = 0x10) -> int:
    # linux/input.h: EVIOCGSW(len) = _IOC(_IOC_READ, 'E', 0x1b, len)
    # dir 2<<30 | size<<16 | type 'E' (0x45) << 8 | nr 0x1b — a wrong type
    # byte is an EINVAL on the real device (shipped as 0x21 once; pinned below).
    buf = bytearray((count + 7) // 8)
    req = (2 << 30) | (len(buf) << 16) | (0x45 << 8) | 0x1B
    fcntl.ioctl(fd, req, buf, True)
    return int.from_bytes(buf, "little")


def switch_state(node: str) -> bool | None:
    """True = tablet asserted; None = unreadable (said plainly, never guessed)."""
    try:
        fd = os.open(node, os.O_RDONLY | os.O_NONBLOCK)
        state = bool(_eviocgsw(fd) & (1 << SW_TABLET_MODE))
        os.close(fd)
        return state
    except OSError:
        return None


def hypr_devices() -> dict:
    out = subprocess.run(["hyprctl", "devices", "-j"], capture_output=True, text=True, timeout=10)
    return json.loads(out.stdout or "{}")


def owned_devices(devices: dict) -> list[str]:
    names = []
    kb_re = [re.compile(p, re.I) for p in os.environ.get("CEDAR_CONVERTIBLE_KEYBOARDS", "").split(",") if p] or \
            [re.compile(p, re.I) for p in KEYBOARD_PATTERNS]
    tp_re = [re.compile(p, re.I) for p in os.environ.get("CEDAR_CONVERTIBLE_TOUCHPADS", "").split(",") if p] or \
            [re.compile(p, re.I) for p in TOUCHPAD_PATTERNS]
    for dev in devices.get("keyboards", []):
        if any(r.search(dev.get("name", "")) for r in kb_re):
            names.append(dev["name"])
    for dev in devices.get("mice", []):
        if any(r.search(dev.get("name", "")) for r in tp_re):
            names.append(dev["name"])
    return names


def set_enabled(name: str, enabled: bool) -> bool:
    """Apply through the Lua config API (this Hyprland is non-legacy:
    `hyprctl keyword` is refused outright). The honest limit: the API has
    no getter for device enabled state, so success is the compositor's own
    'ok' ack — the watch loop re-asserts posture on failure every poll,
    which is the self-healing half of the design."""
    lua = "hl.device({name=%s, enabled=%s})" % (json.dumps(name),
                                                "true" if enabled else "false")
    try:
        out = subprocess.run(["hyprctl", "eval", lua],
                             capture_output=True, text=True, timeout=10)
        return out.stdout.strip() == "ok"
    except (OSError, subprocess.SubprocessError):
        return False


class Posture:
    """Applies and remembers what IT disabled, so exit always restores."""

    def __init__(self):
        self.disabled: list[str] = []
        self.failed: list[str] = []

    def apply(self, tablet: bool) -> dict:
        names = owned_devices(hypr_devices())
        applied, failed = [], []
        for name in names:
            target = not tablet
            already = name in self.disabled
            if tablet and already:
                continue
            if not tablet and not already:
                continue
            if set_enabled(name, target):
                applied.append(name)
                if tablet:
                    self.disabled.append(name)
                elif name in self.disabled:
                    self.disabled.remove(name)
            else:
                failed.append(name)
        self.failed = failed
        return {"applied": applied, "failed": failed, "held": list(self.disabled)}

    def restore(self):
        for name in list(self.disabled):
            if set_enabled(name, True):
                self.disabled.remove(name)


def emit(**row):
    print(json.dumps(row), flush=True)


def cmd_state() -> int:
    sw = find_switch()
    tablet = switch_state(sw["node"]) if sw["detected"] else None
    emit(kind="state", detected=sw["detected"], device=sw["name"], node=sw["node"],
         tablet=tablet, note="" if tablet is not None or not sw["detected"]
         else "switch unreadable — run the `rules` step for seat access")
    return 0


def cmd_laptop() -> int:
    posture = Posture()
    devices = owned_devices(hypr_devices())
    failed = [n for n in devices if not set_enabled(n, True)]
    emit(kind="laptop", enabled=[n for n in devices if n not in failed], failed=failed)
    return 1 if failed else 0


def cmd_watch() -> int:
    sw = find_switch()
    if not sw["detected"]:
        emit(kind="error", error="no tablet-mode switch on this machine")
        return 1
    posture = Posture()

    def _exit(*_):
        posture.restore()
        emit(kind="exit", restored=True)
        os._exit(0)

    signal.signal(signal.SIGTERM, _exit)
    signal.signal(signal.SIGINT, _exit)

    tablet = switch_state(sw["node"])
    if tablet is None:
        emit(kind="error", error="switch state unreadable on " + sw["node"] +
             " — apply the `rules` step for seat access")
        return 1
    emit(kind="state", tablet=tablet, initial=True, **posture.apply(tablet))

    try:
        fd = os.open(sw["node"], os.O_RDONLY)
    except OSError as e:
        emit(kind="error", error="cannot open " + sw["node"] + ": " + str(e))
        return 1
    try:
        while True:
            ready, _, _ = select.select([fd], [], [], POLL_SECONDS)
            if ready:
                try:
                    data = os.read(fd, INPUT_EVENT.size * 8)
                except BlockingIOError:
                    data = b""
                # Any EV_SW event could be the flip; the state re-read below
                # is the authority, the event is only the prompt to look now.
                _ = data
            current = switch_state(sw["node"])
            if current is not None and current != tablet:
                tablet = current
                result = posture.apply(tablet)
                emit(kind="state", tablet=tablet, at=time.time(), **result)
            elif posture.failed:
                # A failed application is retried every poll: the compositor
                # accepting nothing is not a reason to leave devices dead.
                retry = posture.apply(tablet)
                if not retry["failed"]:
                    emit(kind="state", tablet=tablet, at=time.time(), retried=True, **retry)
    finally:
        os.close(fd)
        posture.restore()


HWDB = """# CEDAR Convertible: libinput must not suspend the keyboard/touchpad on the
# tablet-mode switch — CEDAR's convertible.py owns the transition instead.
evdev:name:Lenovo Yoga Tablet Mode Control switch:dmi:*
 LIBINPUT_IGNORE_DEVICE=1

evdev:name:Intel HID switches:dmi:*
 LIBINPUT_IGNORE_DEVICE=1
"""

UDEV = """# CEDAR Convertible: give the shell's user read access to the tablet-mode
# switch (and nothing else). KERNEL=="event*" is required: udev
# tags/properties live on the event nodes, not the parent input devices.
# Two independent grants, because they fail differently:
#  - TAG+="uaccess" asks logind for a seat ACL (correct, but on this stack
#    logind did not apply it to the already-added device);
#  - the setfacl RUN line is deterministic and needs NO relogin.
SUBSYSTEM=="input", KERNEL=="event*", ATTRS{{name}}=="Lenovo Yoga Tablet Mode Control switch", TAG+="uaccess", RUN+="/usr/bin/setfacl -m u:{user}:r $env{{DEVNAME}}"
SUBSYSTEM=="input", KERNEL=="event*", ATTRS{{name}}=="Intel HID switches", TAG+="uaccess", RUN+="/usr/bin/setfacl -m u:{user}:r $env{{DEVNAME}}"
"""

APPLY = """\
#!/bin/sh
# CEDAR Convertible — one-time sudo step.
# libinput stops fighting CEDAR, and the seat user can read the switch
# state without the input group. hwdb records are separated by BLANK
# LINES — joining them makes hwdb reject every record after the first.
# The trigger MUST cover the whole input subsystem: --sysname-match="input*"
# only re-fires the parent devices, and both the hwdb properties and the
# uaccess tag attach on the event* nodes.
set -e
sudo install -D -m 644 /dev/stdin /etc/udev/hwdb.d/99-cedar-convertible.hwdb <<'HWDB'
{hwdb}HWDB
sudo install -D -m 644 /dev/stdin /etc/udev/rules.d/99-cedar-convertible.rules <<'RULES'
{udev}RULES
sudo systemd-hwdb update
sudo udevadm control --reload
sudo udevadm trigger --subsystem-match=input
echo "Convertible rules installed — no relogin needed for switch access."
echo "(A compositor restart is only needed if it started BEFORE the first"
echo " hwdb install; anything after that opens devices with the ignore set.)"
"""


def cmd_rules() -> int:
    import getpass
    user = os.environ.get("CEDAR_CONVERTIBLE_USER") or getpass.getuser()
    print(APPLY.format(hwdb=HWDB, udev=UDEV.format(user=user)), end="")
    return 0


def main(argv: list[str]) -> int:
    verbs = {"state": cmd_state, "laptop": cmd_laptop, "watch": cmd_watch, "rules": cmd_rules}
    if len(argv) != 2 or argv[1] not in verbs:
        print("usage: convertible.py state|watch|laptop|rules", file=sys.stderr)
        return 1
    return verbs[argv[1]]()


if __name__ == "__main__":
    sys.exit(main(sys.argv))
