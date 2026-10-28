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
import shutil
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
KEYBOARD_PATTERNS = [r"^AT Translated Set 2 keyboard$"]
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


def owned_nodes(root: str = "/sys/class/input") -> list[dict]:
    """The INTERNAL keyboard and touchpad as evdev nodes, matched by the
    kernel's device name (stable across sessions; event numbers are not).
    Externals, buttons and buses are never touched. Patterns overridable
    via CEDAR_CONVERTIBLE_KEYBOARDS / CEDAR_CONVERTIBLE_TOUCHPADS."""
    kb_re = [re.compile(p, re.I) for p in os.environ.get("CEDAR_CONVERTIBLE_KEYBOARDS", "").split(",") if p] or \
            [re.compile(p, re.I) for p in KEYBOARD_PATTERNS]
    tp_re = [re.compile(p, re.I) for p in os.environ.get("CEDAR_CONVERTIBLE_TOUCHPADS", "").split(",") if p] or \
            [re.compile(p, re.I) for p in TOUCHPAD_PATTERNS]
    out = []
    for name_file in sorted(Path(root).glob("input*/name")):
        try:
            name = name_file.read_text().strip()
        except OSError:
            continue
        kind = "keyboard" if any(r.search(name) for r in kb_re) else \
               "touchpad" if any(r.search(name) for r in tp_re) else ""
        if not kind:
            continue
        events = sorted(name_file.parent.glob("event*"))
        if events:
            out.append({"name": name, "kind": kind, "node": "/dev/input/" + events[0].name})
    return out


EVIOCGRAB = 0x40044590  # _IOW('E', 0x90, int)


class Posture:
    """Owns the devices at the kernel: EVIOCGRAB takes exclusive hold of a
    node's events, so the compositor's libinput sees nothing while held.
    Deterministic and compositor-independent — the grab fails loudly
    (EBUSY) if anyone else holds the device, and closing the fd releases
    the grab, so a dead watcher can never leave a device captured."""

    def __init__(self):
        self.held: dict[str, int] = {}   # node -> fd
        self.failed: list[str] = []

    def apply(self, tablet: bool) -> dict:
        applied, failed = [], []
        if tablet:
            for dev in owned_nodes():
                if dev["node"] in self.held:
                    continue
                try:
                    fd = os.open(dev["node"], os.O_RDONLY | os.O_NONBLOCK)
                    fcntl.ioctl(fd, EVIOCGRAB, 1)
                    self.held[dev["node"]] = fd
                    applied.append(dev["name"])
                except OSError as e:
                    failed.append(dev["name"] + ": " + (e.strerror or str(e)))
        else:
            for node, fd in list(self.held.items()):
                try:
                    fcntl.ioctl(fd, EVIOCGRAB, 0)
                except OSError:
                    pass  # closing the fd releases it regardless
                os.close(fd)
                del self.held[node]
                applied.append(node)
        self.failed = failed
        return {"applied": applied, "failed": failed, "held": list(self.held)}

    def restore(self):
        self.apply(False)


def emit(**row):
    print(json.dumps(row), flush=True)


def find_osk() -> str:
    """The on-screen keyboard for tablet mode, first available wins."""
    for name in ("squeekboard", "wvkbd"):
        path = shutil.which(name)
        if path:
            return path
    return ""


def cmd_state() -> int:
    sw = find_switch()
    tablet = switch_state(sw["node"]) if sw["detected"] else None
    owned = []
    for dev in owned_nodes():
        try:
            fd = os.open(dev["node"], os.O_RDONLY | os.O_NONBLOCK)
            os.close(fd)
            owned.append(dict(dev, reachable=True))
        except OSError:
            owned.append(dict(dev, reachable=False))
    emit(kind="state", detected=sw["detected"], device=sw["name"], node=sw["node"],
         tablet=tablet, osk=find_osk(), owned=owned,
         note="" if tablet is not None or not sw["detected"]
         else "switch unreadable — run the `rules` step for seat access")
    return 0


def cmd_laptop() -> int:
    """Laptop posture is the ABSENCE of a grab: a fresh process holds none,
    and a dying watcher releases its own. So this verb reports whether the
    owned nodes are reachable (the rules step) rather than pretending to
    toggle anything — honest about what a grab-based design can do."""
    nodes = owned_nodes()
    reachable, failed = [], []
    for dev in nodes:
        try:
            fd = os.open(dev["node"], os.O_RDONLY | os.O_NONBLOCK)
            os.close(fd)
            reachable.append(dev["name"])
        except OSError as e:
            failed.append(dev["name"] + ": " + (e.strerror or str(e)))
    emit(kind="laptop", reachable=reachable, failed=failed,
         note="" if not failed else "run the `rules` step: the watcher needs read access to grab these")
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
# switch and to the internal keyboard + touchpad it owns during the
# transition (an EVIOCGRAB needs an open fd). KERNEL=="event*" is required:
# udev tags/properties live on the event nodes, not the parent devices.
# Two independent grants, because they fail differently:
#  - TAG+="uaccess" asks logind for a seat ACL (correct, but on this stack
#    logind did not apply it to the already-added device);
#  - the setfacl RUN line is deterministic and needs NO relogin.
SUBSYSTEM=="input", KERNEL=="event*", ATTRS{{name}}=="Lenovo Yoga Tablet Mode Control switch", TAG+="uaccess", RUN+="/usr/bin/setfacl -m u:{user}:r $env{{DEVNAME}}"
SUBSYSTEM=="input", KERNEL=="event*", ATTRS{{name}}=="Intel HID switches", TAG+="uaccess", RUN+="/usr/bin/setfacl -m u:{user}:r $env{{DEVNAME}}"
SUBSYSTEM=="input", KERNEL=="event*", ATTRS{{name}}=="AT Translated Set 2 keyboard", TAG+="uaccess", RUN+="/usr/bin/setfacl -m u:{user}:r $env{{DEVNAME}}"
SUBSYSTEM=="input", KERNEL=="event*", ATTRS{{name}}=="*Touchpad", TAG+="uaccess", RUN+="/usr/bin/setfacl -m u:{user}:r $env{{DEVNAME}}"
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
