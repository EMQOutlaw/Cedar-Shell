"""Nursery registry: descriptor reading, status, and the action safety filters."""
import contextlib
import io
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
        # Restore the real environment after the run: a leaked XDG_CONFIG_HOME
        # breaks env-sensitive tools (the mise node shim) for later tests.
        self._old_env = {k: os.environ.get(k) for k in ("XDG_CONFIG_HOME", "XDG_STATE_HOME")}
        for key, value in self._old_env.items():
            if value is None:
                self.addCleanup(os.environ.pop, key, None)
            else:
                self.addCleanup(os.environ.__setitem__, key, value)
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

    @mock.patch.object(nursery.shutil, "which", return_value="/usr/bin/cedar-ai")
    def test_setup_must_be_the_plugins_own_command(self, _which):
        self.plant(setup="/usr/bin/bash -c /tmp/planted.sh")
        code = nursery._run_setup("/usr/bin/bash -c /tmp/planted.sh", "--enable", plugin_id="cedar-ai")
        self.assertEqual(code, 1)
        self.plant()
        with mock.patch.object(nursery.subprocess, "run") as r:
            r.return_value = mock.Mock(returncode=0, stdout="", stderr="")
            self.assertEqual(nursery._run_setup("cedar-ai setup", "--enable", plugin_id="cedar-ai"), 0)

    def test_unit_name_filter(self):
        self.assertEqual(nursery._run_unit("evil.service;id", "enable"), 1)
        self.assertTrue(nursery.UNIT_NAME.match("cedar-ai.service"))
        self.assertFalse(nursery.UNIT_NAME.match("../x.service"))

    def test_toggle_routes_through_setup_when_present(self):
        self.plant()
        with mock.patch.object(nursery, "_run_setup", return_value=0) as rs:
            self.assertEqual(nursery.cmd_toggle("cedar-ai", "enable"), 0)
            rs.assert_called_once_with("cedar-ai setup", "--enable", plugin_id="cedar-ai")

    def test_toggle_falls_back_to_unit_verbs(self):
        self.plant(setup="")
        with mock.patch.object(nursery, "_run_unit", return_value=0) as ru:
            self.assertEqual(nursery.cmd_toggle("cedar-ai", "disable"), 0)
            ru.assert_called_once_with("cedar-ai.service", "disable")

    def test_open_rejects_non_loopback_http(self):
        self.plant(dashboard="http://evil.example.com/")
        self.assertEqual(nursery.cmd_open("cedar-ai"), 1)

    def call(self, fn, *args, **kwargs):
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            code = fn(*args, **kwargs)
        return code, json.loads(buf.getvalue())

    def test_list_includes_known_installable_when_unplanted(self):
        with mock.patch.object(nursery, "dashboard_ok", return_value=False):
            _, out = self.call(nursery.cmd_list, [])
        row = {p["id"]: p for p in out["plugins"]}["cedar-ai"]
        self.assertTrue(row["available"])
        self.assertFalse(row["planted"])
        self.assertFalse(row["installed"])

    def test_list_marks_planted_rows(self):
        self.plant()
        with mock.patch.object(nursery, "dashboard_ok", return_value=False), \
                mock.patch.object(nursery, "systemctl", return_value=""):
            _, out = self.call(nursery.cmd_list, [])
        row = {p["id"]: p for p in out["plugins"]}["cedar-ai"]
        self.assertTrue(row["planted"])
        self.assertTrue(row["available"])

    def test_install_rejects_unknown_plugin(self):
        code, out = self.call(nursery.cmd_install, "nope")
        self.assertEqual(code, 1)
        self.assertFalse(out["ok"])

    class FakeInstaller:
        """Popen double: communicates a canned installer response."""
        def __init__(self, argv, response, **kw):
            self.args = argv
            self.kw = kw
            self.returncode = 0
            self._response = response
        def communicate(self, input=None, timeout=None):
            self.input = input
            return json.dumps(self._response), ""

    def test_install_runs_the_known_installer_protocol(self):
        response = {"ok": True, "data": {"output": "installed 0.1.0"}}
        with mock.patch.object(nursery.subprocess, "Popen",
                               lambda argv, **kw: self.FakeInstaller(argv, response, **kw)) as popen:
            code, out = self.call(nursery.cmd_install, "cedar-ai")
        self.assertEqual(code, 0)
        self.assertTrue(out["ok"])
        self.assertEqual(out["output"], "installed 0.1.0")

    def test_install_forwards_full_output_untruncated(self):
        response = {"ok": True, "data": {"output": "x" * 3027}}
        with mock.patch.object(nursery.subprocess, "Popen",
                               lambda argv, **kw: self.FakeInstaller(argv, response, **kw)):
            code, out = self.call(nursery.cmd_install, "cedar-ai")
        self.assertEqual(code, 0)
        self.assertEqual(len(out["output"]), 3027)

    def test_install_surfaces_installer_failure(self):
        response = {"ok": False, "error": "Download failed"}
        with mock.patch.object(nursery.subprocess, "Popen",
                               lambda argv, **kw: self.FakeInstaller(argv, response, **kw)):
            code, out = self.call(nursery.cmd_install, "cedar-ai")
        self.assertEqual(code, 1)
        self.assertIn("Download failed", out["error"])

    def test_install_timeout_kills_the_process_group(self):
        class Hanging:
            def __init__(self, argv, **kw):
                self.pid = 42424
            def communicate(self, input=None, timeout=None):
                raise subprocess.TimeoutExpired("cedar_ai_update.py", timeout)
            def wait(self, timeout=None):
                return 0
        kills = []
        with mock.patch.object(nursery.subprocess, "Popen", lambda argv, **kw: Hanging(argv, **kw)), \
                mock.patch.object(nursery.os, "killpg", lambda pgid, sig: kills.append((pgid, sig))):
            code, out = self.call(nursery.cmd_install, "cedar-ai")
        self.assertEqual(code, 1)
        self.assertFalse(out["ok"])
        self.assertIn("timed out", out["error"])
        self.assertIn((42424, __import__("signal").SIGTERM), kills)


    def test_dashboard_host_must_be_exactly_loopback(self):
        self.assertFalse(nursery.openable_dashboard("http://127.0.0.1.evil.example/"))
        self.assertFalse(nursery.openable_dashboard("http://user@127.0.0.1:3650/"))
        self.assertFalse(nursery.openable_dashboard("http://127.0.0.1@evil.example/"))
        self.assertFalse(nursery.openable_dashboard("http://169.254.0.1/"))
        self.assertTrue(nursery.openable_dashboard("http://127.0.0.1:3650/"))
        self.assertTrue(nursery.openable_dashboard("http://localhost:3650/"))
        self.assertTrue(nursery.openable_dashboard("http://[::1]:3650/"))
        self.assertTrue(nursery.openable_dashboard("https://status.example.com/"))

    def test_dashboard_probe_does_not_follow_redirects(self):
        import urllib.error
        def raise_redirect(url, timeout):
            raise urllib.error.HTTPError(url, 302, "Found", {"Location": "http://evil.example/"}, None)
        with mock.patch.object(nursery._NO_REDIRECT_OPENER, "open", side_effect=raise_redirect):
            self.assertFalse(nursery.dashboard_ok("http://127.0.0.1:3650/"))

    def test_open_rejects_prefix_trick(self):
        self.plant(dashboard="http://127.0.0.1.evil.example/")
        self.assertEqual(nursery.cmd_open("cedar-ai"), 1)


    def test_setup_resolves_user_local_command_off_path(self):
        with tempfile.TemporaryDirectory() as home:
            local = Path(home) / ".local" / "bin"
            local.mkdir(parents=True)
            command = local / "cedar-ai"
            command.write_text("#!/bin/sh\necho ran")
            command.chmod(0o755)
            with mock.patch.object(nursery.shutil, "which", return_value=None), \
                    mock.patch.object(nursery.Path, "home", return_value=Path(home)):
                argv_seen = {}
                def fake_run(argv, **kw):
                    argv_seen["argv"] = argv
                    return subprocess.CompletedProcess(argv, 0, stdout="ok", stderr="")
                with mock.patch.object(nursery.subprocess, "run", side_effect=fake_run):
                    self.assertEqual(nursery._run_setup("cedar-ai setup", "--enable", plugin_id="cedar-ai"), 0)
            self.assertEqual(argv_seen["argv"][0], str(command))

    def test_setup_missing_command_is_an_honest_error(self):
        with mock.patch.object(nursery.shutil, "which", return_value=None), \
                mock.patch.object(nursery.Path, "home", return_value=Path("/nonexistent")):
            self.assertEqual(nursery._run_setup("cedar-ai setup", "--enable", plugin_id="cedar-ai"), 1)

    @mock.patch.object(nursery.shutil, "which", return_value="/usr/bin/cedar-ai")
    def test_setup_oserror_becomes_json_not_traceback(self, _which):
        with mock.patch.object(nursery.subprocess, "run", side_effect=OSError("No such file")) as run:
            self.assertEqual(nursery._run_setup("cedar-ai setup", "--enable", plugin_id="cedar-ai"), 1)
        run.assert_called_once()

    @mock.patch.object(nursery.shutil, "which", return_value="/usr/bin/cedar-ai")
    def test_setup_timeout_is_an_honest_json_error(self, _which):
        with mock.patch.object(nursery.subprocess, "run", side_effect=nursery.subprocess.TimeoutExpired("cedar-ai", 120)) as run:
            code, out = self.call(nursery._run_setup, "cedar-ai setup", "--enable", plugin_id="cedar-ai")
        run.assert_called_once()
        self.assertEqual(code, 1)
        self.assertFalse(out["ok"])
        self.assertIn("timed out", out["error"])


    def test_user_env_appends_user_bins_without_clobbering(self):
        with mock.patch.object(nursery.Path, "home", return_value=Path("/home/u")), \
                mock.patch.dict(os.environ, {"PATH": "/usr/bin"}, clear=False):
            env = nursery.user_env()
        parts = env["PATH"].split(os.pathsep)
        self.assertEqual(parts[0], "/usr/bin")
        self.assertIn("/home/u/.local/bin", parts)
        self.assertIn("/home/u/.hermes/hermes-agent/.hermes/bin", parts)

    @mock.patch.object(nursery.shutil, "which", return_value="/usr/bin/cedar-ai")
    def test_setup_child_runs_with_user_env(self, _which):
        seen = {}
        def fake_run(argv, **kw):
            seen.update(kw)
            return subprocess.CompletedProcess(argv, 0, stdout="ok", stderr="")
        with mock.patch.object(nursery.subprocess, "run", side_effect=fake_run):
            self.assertEqual(nursery._run_setup("cedar-ai setup", "--enable", plugin_id="cedar-ai"), 0)
        self.assertIn("/.local/bin", seen["env"]["PATH"])


if __name__ == "__main__":
    unittest.main()
