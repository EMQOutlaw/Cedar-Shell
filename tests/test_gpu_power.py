"""Regression coverage for scripts/gpu_power.py — the Graphics & Power
telemetry helper. Read-only by contract: every test pins that the helper
reports what the machine exposes and invents nothing (honest absence), and
that the ServiceRequest protocol shape holds. nvidia-smi rows are mocked;
everything else runs against the real machine (this helper only reads)."""
import json
import subprocess
import sys
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

import gpu_power  # noqa: E402

HELPER = str(ROOT / "scripts" / "gpu_power.py")


def serve(request):
    """One request through the helper's real main(), as the shell would."""
    proc = subprocess.run([sys.executable, HELPER], input=json.dumps(request),
                          capture_output=True, text=True, timeout=20)
    if proc.returncode:
        raise RuntimeError(proc.stderr[-300:])
    return json.loads(proc.stdout)


class Nvidia(unittest.TestCase):
    def test_full_row_parses_into_typed_fields(self):
        """The live RTX 4080 row shape: numbers stay numbers, state stays text."""
        row = ("NVIDIA GeForce RTX 4080, 21, 37, 2121, 16376, 28.25, 340.00, "
               "P8, 210, 3150, 0, Disabled, GPU-4dd10772-f4c4-da37-9022-c96d2f26f9aa, "
               "150.00, 400.00")
        with mock.patch.object(gpu_power.shutil, "which", return_value="/usr/bin/nvidia-smi"), \
             mock.patch.object(gpu_power.subprocess, "run",
                               return_value=mock.Mock(returncode=0, stdout=row + "\n")):
            gpus = gpu_power.nvidia_gpus()
        self.assertEqual(len(gpus), 1)
        gpu = gpus[0]
        self.assertEqual(gpu["name"], "NVIDIA GeForce RTX 4080")
        self.assertEqual(gpu["load"], 21.0)
        self.assertEqual(gpu["temperature"], 37.0)
        self.assertEqual(gpu["memoryUsed"], 2121.0)
        self.assertEqual(gpu["memoryTotal"], 16376.0)
        self.assertEqual(gpu["powerDraw"], 28.25)
        self.assertEqual(gpu["powerLimit"], 340.0)
        self.assertEqual(gpu["pstate"], "P8")
        self.assertEqual(gpu["clock"], 210.0)
        self.assertEqual(gpu["fan"], 0.0)
        self.assertEqual(gpu["persistence"], "disabled")
        self.assertEqual(gpu["uuid"], "GPU-4dd10772-f4c4-da37-9022-c96d2f26f9aa")
        self.assertEqual(gpu["powerMinLimit"], 150.0)
        self.assertEqual(gpu["powerMaxLimit"], 400.0)
        self.assertEqual(gpu["source"], "nvidia")

    def test_absent_driver_is_honest_absence(self):
        """No nvidia-smi: an empty list, never an invented card."""
        with mock.patch.object(gpu_power.shutil, "which", return_value=None):
            self.assertEqual(gpu_power.nvidia_gpus(), [])

    def test_failed_query_is_empty_not_fatal(self):
        with mock.patch.object(gpu_power.shutil, "which", return_value="/usr/bin/nvidia-smi"), \
             mock.patch.object(gpu_power.subprocess, "run",
                               return_value=mock.Mock(returncode=1, stdout="")):
            self.assertEqual(gpu_power.nvidia_gpus(), [])

    def test_short_row_is_skipped_not_guessed(self):
        with mock.patch.object(gpu_power.shutil, "which", return_value="/usr/bin/nvidia-smi"), \
             mock.patch.object(gpu_power.subprocess, "run",
                               return_value=mock.Mock(returncode=0, stdout="Some GPU, 10, 40")):
            self.assertEqual(gpu_power.nvidia_gpus(), [])


class Snapshot(unittest.TestCase):
    def test_nvidia_wins_over_drm_when_present(self):
        with mock.patch.object(gpu_power, "nvidia_gpus",
                               return_value=[{"source": "nvidia", "name": "NVIDIA"}]), \
             mock.patch.object(gpu_power, "drm_gpus", return_value=[{"source": "drm"}]), \
             mock.patch.object(gpu_power, "cpu", return_value={"threads": 16}):
            snap = gpu_power.snapshot()
        self.assertEqual(len(snap["gpus"]), 1)
        self.assertEqual(snap["gpus"][0]["source"], "nvidia")
        self.assertEqual(snap["source"], "nvidia-smi")

    def test_no_source_at_all_reports_empty(self):
        with mock.patch.object(gpu_power, "nvidia_gpus", return_value=[]), \
             mock.patch.object(gpu_power, "drm_gpus", return_value=[]), \
             mock.patch.object(gpu_power, "cpu", return_value={"threads": 0}):
            snap = gpu_power.snapshot()
        self.assertEqual(snap["gpus"], [])
        self.assertEqual(snap["source"], "")

    def test_unknown_action_is_refused(self):
        """A write verb is refused outright: this helper never mutates."""
        with self.assertRaises(ValueError):
            gpu_power.action({"action": "set-power-limit"})


class Cpu(unittest.TestCase):
    def test_real_machine_reports_threads_and_state(self):
        """Integration on the real host: a real CPU block, honest load numbers,
        and a governor/epp pair that are real state or honest empty strings —
        never fabricated values."""
        state = gpu_power.cpu()
        self.assertGreater(state["threads"], 0)
        self.assertLess(state["threads"], 1024)
        if state["freqAvg"] is not None:
            self.assertGreater(state["freqAvg"], 0.2)   # GHz; a running CPU idles above this
            self.assertLess(state["freqAvg"], 8.0)
        self.assertIsInstance(state["governor"], str)
        self.assertIsInstance(state["epp"], str)
        self.assertIsInstance(state["load1"], float)


class Protocol(unittest.TestCase):
    def test_snapshot_comes_back_in_the_service_shape(self):
        reply = serve({"action": "snapshot"})
        self.assertTrue(reply["ok"])
        self.assertIn("gpus", reply["data"])
        self.assertIn("cpu", reply["data"])

    def test_unknown_action_answers_ok_false_with_the_error(self):
        reply = serve({"action": "install-something"})
        self.assertFalse(reply["ok"])
        self.assertIn("Unknown graphics action", reply["error"])


if __name__ == "__main__":
    unittest.main()


class Apply(unittest.TestCase):
    """The privileged write path: whitelisted keys only, pkexec only, and the
    root-owned wrapper re-validates everything itself."""

    def setUp(self):
        self.helper = Path("/tmp") / ("cedar-gpu-apply-fake-%d" % __import__("os").getpid())
        self.helper.write_text("#!/usr/bin/env python3\n")
        self.old = gpu_power.APPLY_HELPER
        gpu_power.APPLY_HELPER = self.helper
        # The stat/ownership checks have their own coverage (CheckHelper);
        # these tests exercise the payload/escalation contract only.
        self.old_check = gpu_power.check_helper
        gpu_power.check_helper = lambda: None

    def tearDown(self):
        gpu_power.check_helper = self.old_check
        gpu_power.APPLY_HELPER = self.old
        self.helper.unlink(missing_ok=True)

    def test_unknown_keys_are_refused_before_any_escalation(self):
        with mock.patch.object(gpu_power.subprocess, "run",
                               side_effect=AssertionError("pkexec must not run for an invalid request")):
            with self.assertRaises(ValueError):
                gpu_power.apply_request({"gpu": {"uuid": "GPU-x", "powerLimit": 300, " clocks": 2000}})

    def test_missing_helper_fails_honestly_through_pkexec(self):
        """Apply.setUp stubs the stat gate, so this exercises the real
        pkexec boundary: a nonexistent helper cannot be escalated, and the
        refusal is a RuntimeError either way (the gate's message, or pkexec's
        own when the gate is stubbed)."""
        gpu_power.APPLY_HELPER = Path("/nonexistent")
        with self.assertRaises(RuntimeError):
            gpu_power.apply_request({"gpu": {"uuid": "GPU-x", "powerLimit": 300}})

    def test_apply_runs_pkexec_with_the_whitelisted_payload(self):
        calls = {}
        def fake_run(args, **kwargs):
            calls["args"] = args
            calls["input"] = kwargs.get("input")
            return mock.Mock(returncode=0, stdout='{"ok": true, "data": {"applied": {}}}', stderr="")
        with mock.patch.object(gpu_power.subprocess, "run", side_effect=fake_run):
            gpu_power.apply_request({"gpu": {"uuid": "GPU-x", "powerLimit": 300, "persistence": 1}})
        self.assertEqual(calls["args"], ["pkexec", str(self.helper)])
        payload = json.loads(calls["input"])
        self.assertEqual(payload["gpu"], {"uuid": "GPU-x", "powerLimit": 300, "persistence": 1})

    def test_apply_surfaces_the_wrapper_error_verbatim(self):
        with mock.patch.object(gpu_power.subprocess, "run",
                               return_value=mock.Mock(returncode=1, stdout='{"ok": false, "error": "Power limit must be a whole number between 150 and 400 W."}', stderr="")):
            with self.assertRaisesRegex(RuntimeError, "150 and 400"):
                gpu_power.apply_request({"gpu": {"uuid": "GPU-x", "powerLimit": 999}})


class CheckHelper(unittest.TestCase):
    def setUp(self):
        self.old = gpu_power.APPLY_HELPER
        self.helper = Path("/tmp") / ("cedar-gpu-apply-guard-%d" % __import__("os").getpid())
        self.helper.write_text("#!/usr/bin/env python3\n")
        gpu_power.APPLY_HELPER = self.helper

    def tearDown(self):
        gpu_power.APPLY_HELPER = self.old
        self.helper.unlink(missing_ok=True)

    def test_missing_helper_refused(self):
        self.helper.unlink()
        with self.assertRaisesRegex(RuntimeError, "not installed"):
            gpu_power.check_helper()

    def test_nonexistent_helper_refused(self):
        gpu_power.APPLY_HELPER = Path("/nonexistent-cedar-gpu-apply")
        with self.assertRaisesRegex(RuntimeError, "not installed"):
            gpu_power.check_helper()

    def _guard(self, uid, mode, same_hash=True):
        import types
        return gpu_power._guard(types.SimpleNamespace(st_uid=uid, st_mode=mode),
                                "a" * 64, "a" * 64 if same_hash else "b" * 64)

    def test_group_or_other_writable_refused(self):
        with self.assertRaisesRegex(RuntimeError, "writable by group or other"):
            self._guard(0, 0o100777)

    def test_non_root_owner_refused(self):
        with self.assertRaisesRegex(RuntimeError, "not root-owned"):
            self._guard(1000, 0o100700)

    def test_stale_helper_refused(self):
        with self.assertRaisesRegex(RuntimeError, "differs from this build"):
            self._guard(0, 0o100700, same_hash=False)

    def test_private_fresh_helper_passes_the_gate(self):
        self._guard(0, 0o100700)  # no raise


class Program(unittest.TestCase):
    def setUp(self):
        self.old = gpu_power.PROGRAM_FILE
        self.file = Path("/tmp") / ("cedar-gpu-program-%d.json" % __import__("os").getpid())
        gpu_power.PROGRAM_FILE = self.file
        self.file.unlink(missing_ok=True)

    def tearDown(self):
        self.file.unlink(missing_ok=True)
        gpu_power.PROGRAM_FILE = self.old

    def test_save_merges_per_profile_and_keeps_unknown_keys(self):
        self.file.parent.mkdir(parents=True, exist_ok=True)
        self.file.write_text(json.dumps({"profiles": {"balanced": {"governor": "powersave"}}, "future": 1}))
        gpu_power.program_save({"profiles": {"performance": {"governor": "performance", "epp": "performance", "bogus": 1}}})
        data = json.loads(self.file.read_text())
        self.assertEqual(data["profiles"]["balanced"], {"governor": "powersave"})
        self.assertEqual(data["profiles"]["performance"]["epp"], "performance")
        self.assertNotIn("bogus", data["profiles"]["performance"])
        self.assertEqual(data["future"], 1)  # unknown top-level keys survive

    def test_save_refuses_unknown_profiles(self):
        with self.assertRaises(ValueError):
            gpu_power.program_save({"profiles": {"turbo": {"governor": "performance"}}})

    def test_get_reports_missing_file_honestly(self):
        state = gpu_power.program_get()
        self.assertEqual(state["profiles"], {})
