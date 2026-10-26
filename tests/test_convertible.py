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


class OwnershipTest(unittest.TestCase):
    def test_owns_internal_keyboard_and_touchpad_only(self):
        names = convertible.owned_devices(DEVICES)
        self.assertEqual(sorted(names), ["at-translated-set-2-keyboard", "elan06fa:00-04f3:3293-touchpad"])

    def test_env_override(self):
        os.environ["CEDAR_CONVERTIBLE_TOUCHPADS"] = "usb-receiver"
        try:
            names = convertible.owned_devices(DEVICES)
            self.assertIn("logitech-usb-receiver-mouse", names)
        finally:
            del os.environ["CEDAR_CONVERTIBLE_TOUCHPADS"]


class PostureTest(unittest.TestCase):
    def setUp(self):
        self.applied = {}
        patcher = mock.patch.object(convertible, "set_enabled",
                                    side_effect=lambda n, e: self.applied.setdefault(n, e) is None or True)
        patcher.start()
        self.addCleanup(patcher.stop)
        devices = mock.patch.object(convertible, "hypr_devices", return_value=DEVICES)
        devices.start()
        self.addCleanup(devices.stop)

    def test_fold_disables_both_and_remembers(self):
        p = convertible.Posture()
        p.apply(True)
        self.assertEqual(self.applied, {"at-translated-set-2-keyboard": False,
                                        "elan06fa:00-04f3:3293-touchpad": False})
        self.assertEqual(len(p.disabled), 2)

    def test_unfold_restores_only_what_it_disabled(self):
        p = convertible.Posture()
        p.apply(True)
        self.applied.clear()
        p.apply(False)
        self.assertEqual(self.applied, {"at-translated-set-2-keyboard": True,
                                        "elan06fa:00-04f3:3293-touchpad": True})
        self.assertEqual(p.disabled, [])

    def test_repeated_fold_is_idempotent(self):
        p = convertible.Posture()
        p.apply(True)
        self.applied.clear()
        p.apply(True)  # a second fold event must not re-apply
        self.assertEqual(self.applied, {})

    def test_restore_on_exit_enables_everything_held(self):
        p = convertible.Posture()
        p.apply(True)
        self.applied.clear()
        p.restore()
        self.assertTrue(all(v is True for v in self.applied.values()))
        self.assertEqual(p.disabled, [])

    def test_failed_apply_is_not_held(self):
        with mock.patch.object(convertible, "set_enabled", return_value=False):
            p = convertible.Posture()
            result = p.apply(True)
        self.assertEqual(p.disabled, [])
        self.assertEqual(len(result["failed"]), 2)


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
