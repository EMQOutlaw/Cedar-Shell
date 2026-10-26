"""Nursery registry: descriptor reading, status, and the action safety filters."""
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

import nursery  # noqa: E402


class NurseryTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp(prefix="cedar-nursery-test-")
        os.environ["XDG_CONFIG_HOME"] = self.dir
        os.environ["XDG_STATE_HOME"] = self.dir
        self.pd = Path(self.dir) / "cedar" / "plugins.d"
        self.pd.mkdir(parents=True)

    def plant(self, plugin_id="cedar-ai", **over):
        data = {"id": plugin_id, "name": "CEDAR Ai", "tagline": "map",
                "unit": "cedar-ai.service", "dashboard": "http://127.0.0.1:3650/",
                "setup": "cedar-ai setup"}
        data.update(over)
        (self.pd / (plugin_id + ".json")).write_text(json.dumps(data), encoding="utf-8")
        return data

    def test_empty_registry(self):
        self.assertEqual(nursery.descriptors(), [])

    def test_descriptor_read_and_defaults(self):
        self.plant()
        rows = nursery.descriptors()
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["id"], "cedar-ai")
        self.assertEqual(rows[0]["name"], "CEDAR Ai")

    def test_unreadable_descriptor_is_reported_not_fatal(self):
        self.plant()
        (self.pd / "broken.json").write_text("{no", encoding="utf-8")
        rows = nursery.descriptors()
        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[0]["error"], "descriptor unreadable")

    def test_setup_state_read_from_state_file(self):
        self.plant()
        sd = Path(self.dir) / "cedar-ai"
        sd.mkdir()
        (sd / "setup.json").write_text(json.dumps({"state": "enabled"}), encoding="utf-8")
        self.assertEqual(nursery.setup_state("cedar-ai"), "enabled")
        self.assertEqual(nursery.setup_state("ghost"), "")

    def test_status_without_unit_file(self):
        self.plant()
        row = nursery.status(nursery.descriptors()[0])
        self.assertFalse(row["installed"])
        self.assertFalse(row["active"])
        self.assertEqual(row["setup_state"], "")

    def test_setup_argv_filter_rejects_metacharacters(self):
        self.plant(setup="cedar-ai setup; rm -rf ~")
        code = nursery._run_setup("cedar-ai setup; rm -rf ~", "--enable")
        self.assertEqual(code, 1)

    def test_unit_name_filter(self):
        self.assertEqual(nursery._run_unit("evil.service;id", "enable"), 1)
        self.assertTrue(nursery.UNIT_NAME.match("cedar-ai.service"))
        self.assertFalse(nursery.UNIT_NAME.match("../x.service"))

    def test_toggle_routes_through_setup_when_present(self):
        self.plant()
        with mock.patch.object(nursery, "_run_setup", return_value=0) as rs:
            self.assertEqual(nursery.cmd_toggle("cedar-ai", "enable"), 0)
            rs.assert_called_once_with("cedar-ai setup", "--enable")

    def test_toggle_falls_back_to_unit_verbs(self):
        self.plant(setup="")
        with mock.patch.object(nursery, "_run_unit", return_value=0) as ru:
            self.assertEqual(nursery.cmd_toggle("cedar-ai", "disable"), 0)
            ru.assert_called_once_with("cedar-ai.service", "disable")

    def test_open_rejects_non_loopback_http(self):
        self.plant(dashboard="http://evil.example.com/")
        self.assertEqual(nursery.cmd_open("cedar-ai"), 1)


if __name__ == "__main__":
    unittest.main()
