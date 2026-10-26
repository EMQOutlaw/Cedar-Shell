"""Convertible: switch discovery, device ownership, posture state machine, rules."""
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

import convertible  # noqa: E402

DEVICES = {
    "mice": [{"name": "elan06fa:00-04f3:3293-touchpad"}, {"name": "logitech-usb-receiver-mouse"}],
    "keyboards": [{"name": "at-translated-set-2-keyboard"}, {"name": "video-bus"},
                  {"name": "ideapad-extra-buttons"}],
}


def make_switch(root: Path, name: str = "Lenovo Yoga Tablet Mode Control switch", sw: int = 0x2):
    dev = root / "input10"
    (dev / "capabilities").mkdir(parents=True)
    (dev / "name").write_text(name)
    (dev / "capabilities" / "sw").write_text(hex(sw))
    (dev / "event9").write_text("")


class DiscoveryTest(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix="cedar-conv-"))

    def test_finds_the_tablet_switch(self):
        make_switch(self.root)
        row = convertible.find_switch(str(self.root))
        self.assertTrue(row["detected"])
        self.assertEqual(row["name"], "Lenovo Yoga Tablet Mode Control switch")
        self.assertEqual(row["node"], "/dev/input/event9")

    def test_ignores_devices_without_tablet_bit(self):
        make_switch(self.root, name="Lid Switch", sw=0x1)  # SW_LID only
        row = convertible.find_switch(str(self.root))
        self.assertFalse(row["detected"])

    def test_no_switch_is_a_plain_no(self):
        row = convertible.find_switch(str(self.root))
        self.assertFalse(row["detected"])
        self.assertEqual(row["node"], "")


class IoctlTest(unittest.TestCase):
    def test_eviocgsw_request_matches_the_kernel_macro(self):
        # EVIOCGSW(2) = _IOC(_IOC_READ=2, 'E'=0x45, 0x1b, 2). Shipped once
        # with 0x21 and got EINVAL on the real switch; pin the encoding.
        captured = {}

        def fake_ioctl(fd, req, buf, mutate):
            captured["req"] = req
            buf[0] = 0b10  # SW_TABLET_MODE asserted
            return 0

        with mock.patch("convertible.fcntl.ioctl", side_effect=fake_ioctl):
            state = convertible._eviocgsw(0)
        expected = (2 << 30) | (2 << 16) | (0x45 << 8) | 0x1B
        self.assertEqual(captured["req"], expected)
        self.assertTrue(state & (1 << convertible.SW_TABLET_MODE))


def make_owned(root: Path):
    for idx, (name, ev) in enumerate([("AT Translated Set 2 keyboard", "event3"),
                                      ("ELAN06FA:00 04F3:3293 Touchpad", "event6"),
                                      ("Logitech USB Receiver Mouse", "event7"),
                                      ("Video Bus", "event8")]):
        dev = root / ("input%d" % (20 + idx))
        dev.mkdir(parents=True)
        (dev / "name").write_text(name)
        (dev / ev).write_text("")


class OwnershipTest(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix="cedar-conv-own-"))
        make_owned(self.root)

    def test_owns_internal_keyboard_and_touchpad_only(self):
        nodes = convertible.owned_nodes(str(self.root))
        self.assertEqual(sorted(d["name"] for d in nodes),
                         ["AT Translated Set 2 keyboard", "ELAN06FA:00 04F3:3293 Touchpad"])
        kinds = {d["name"]: d["kind"] for d in nodes}
        self.assertEqual(kinds["AT Translated Set 2 keyboard"], "keyboard")
        self.assertEqual(kinds["ELAN06FA:00 04F3:3293 Touchpad"], "touchpad")
        self.assertEqual({d["node"] for d in nodes}, {"/dev/input/event3", "/dev/input/event6"})

    def test_env_override(self):
        os.environ["CEDAR_CONVERTIBLE_TOUCHPADS"] = "usb receiver"
        try:
            names = [d["name"] for d in convertible.owned_nodes(str(self.root))]
            self.assertIn("Logitech USB Receiver Mouse", names)
        finally:
            del os.environ["CEDAR_CONVERTIBLE_TOUCHPADS"]


class PostureTest(unittest.TestCase):
    """The grab model: fds opened + EVIOCGRAB 1 on fold, EVIOCGRAB 0 + close
    on unfold. The kernel is faked at os.open / fcntl.ioctl / os.close."""

    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix="cedar-conv-posture-"))
        make_owned(self.root)
        self.grabs = {}      # fd -> grab state
        self.opened = {}     # fd -> node
        self.closed = []
        self.next_fd = 10

        def fake_open(node, flags):
            fd = self.next_fd; self.next_fd += 1
            self.opened[fd] = node
            return fd

        def fake_ioctl(fd, req, arg, *rest):
            self.assertEqual(req, convertible.EVIOCGRAB)
            self.grabs[fd] = arg
            return 0

        def fake_close(fd):
            self.closed.append(fd)

        for target, fake in (("os.open", fake_open), ("fcntl.ioctl", fake_ioctl), ("os.close", fake_close)):
            p = mock.patch("convertible." + target, side_effect=fake)
            p.start(); self.addCleanup(p.stop)
        real = convertible.owned_nodes
        p = mock.patch("convertible.owned_nodes", side_effect=lambda root="unused": real(str(self.root)))
        p.start(); self.addCleanup(p.stop)

    def test_fold_grabs_both_and_holds_fds(self):
        p = convertible.Posture()
        result = p.apply(True)
        self.assertEqual(sorted(result["applied"]), ["AT Translated Set 2 keyboard", "ELAN06FA:00 04F3:3293 Touchpad"])
        self.assertEqual(set(self.opened.values()), {"/dev/input/event3", "/dev/input/event6"})
        self.assertTrue(all(v == 1 for v in self.grabs.values()))
        self.assertEqual(len(p.held), 2)

    def test_unfold_releases_and_closes_only_what_it_held(self):
        p = convertible.Posture()
        p.apply(True)
        held_fds = set(p.held.values())
        p.apply(False)
        self.assertEqual(p.held, {})
        self.assertEqual(set(self.closed), held_fds)
        self.assertTrue(all(self.grabs[fd] == 0 for fd in held_fds))

    def test_repeated_fold_is_idempotent(self):
        p = convertible.Posture()
        p.apply(True)
        opened_before = len(self.opened)
        p.apply(True)
        self.assertEqual(len(self.opened), opened_before)

    def test_restore_releases_everything(self):
        p = convertible.Posture()
        p.apply(True)
        p.restore()
        self.assertEqual(p.held, {})
        self.assertEqual(len(self.closed), 2)

    def test_failed_grab_is_reported_not_held(self):
        with mock.patch("convertible.fcntl.ioctl", side_effect=OSError(16, "Device or resource busy")):
            p = convertible.Posture()
            result = p.apply(True)
        self.assertEqual(p.held, {})
        self.assertEqual(len(result["failed"]), 2)
        self.assertIn("busy", result["failed"][0].lower())


class IoctlConstantsTest(unittest.TestCase):
    def test_eviocgrab_matches_the_kernel_macro(self):
        # _IOW('E', 0x90, int) = dir 1<<30 | size 4<<16 | 'E' 0x45<<8 | 0x90
        self.assertEqual(convertible.EVIOCGRAB, (1 << 30) | (4 << 16) | (0x45 << 8) | 0x90)


class RulesTest(unittest.TestCase):
    def test_rules_cover_known_switches(self):
        self.assertIn("Lenovo Yoga Tablet Mode Control switch", convertible.HWDB)
        self.assertIn("LIBINPUT_IGNORE_DEVICE=1", convertible.HWDB)
        self.assertIn("uaccess", convertible.UDEV)
        self.assertIn("systemd-hwdb update", convertible.APPLY)

    def test_hwdb_records_are_blank_line_separated(self):
        # hwdb rejects every record after the first when they run together —
        # this regression actually shipped and was caught by the user's run.
        records = [r for r in convertible.HWDB.split("\n\n") if "evdev:" in r]
        self.assertEqual(len(records), 2)
        for record in records:
            lines = [l for l in record.splitlines() if l and not l.startswith("#")]
            self.assertTrue(lines[0].startswith("evdev:"))
            self.assertTrue(all(l.startswith(" ") for l in lines[1:]))

    def test_apply_script_is_pure_shell(self):
        # The first user run executed prose lines as commands; outside the
        # heredoc payloads, the script must contain nothing but shell.
        script = convertible.APPLY.format(hwdb=convertible.HWDB, udev=convertible.UDEV)
        heredoc = None
        for line in script.splitlines():
            if heredoc:
                if line == heredoc:
                    heredoc = None
                continue
            if "<<" in line:
                heredoc = line.rsplit("'", 2)[-2]
                continue
            if line and not line.startswith(("#", "sudo", "echo", "set ")):
                self.fail("non-shell line leaked into the rules script: " + line)


if __name__ == "__main__":
    unittest.main()
