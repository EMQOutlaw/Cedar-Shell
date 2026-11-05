"""Regression coverage for scripts/cedar-gpu-apply — the root-owned pkexec
wrapper. securitybot B1–B3 were all probe findings against this file, so it
gets its own suite: the module is loaded from its path with its sysfs root
and subprocess seam patched, and every refusal the docstring promises is
pinned. The request on stdin is never trusted; these tests are how that
claim stays true."""
import importlib.machinery
import importlib.util
import json
import sys
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
WRAPPER = ROOT / "scripts" / "cedar-gpu-apply"

# No .py suffix: hand the loader over explicitly.
spec = importlib.util.spec_from_loader(
    "cedar_gpu_apply", importlib.machinery.SourceFileLoader("cedar_gpu_apply", str(WRAPPER)))
wrap = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wrap)


class FakeSysfs(unittest.TestCase):
    """A tmp sysfs tree with the real layout: one policy dir, available lists,
    hardware ranges."""

    def setUp(self):
        import tempfile
        self.tmp = Path(tempfile.mkdtemp(prefix="cedar-gpu-apply-test-"))
        self.old_root = wrap.CPUFREQ
        wrap.CPUFREQ = self.tmp
        self.addCleanup(lambda: setattr(wrap, "CPUFREQ", self.old_root))
        self.policy = self.tmp / "cpu0" / "cpufreq"
        self.policy.mkdir(parents=True)
        self.policy.joinpath("scaling_available_governors").write_text("performance powersave schedutil\n")
        self.policy.joinpath("energy_performance_available_preferences").write_text("default performance balance_performance balance_power power\n")
        self.policy.joinpath("cpuinfo_min_freq").write_text("400000\n")
        self.policy.joinpath("cpuinfo_max_freq").write_text("5053377\n")
        self.policy.joinpath("scaling_min_freq").write_text("400000\n")
        self.policy.joinpath("scaling_max_freq").write_text("400000\n")  # the user already lowered it

    def read(self, name):
        return self.policy.joinpath(name).read_text().strip()


class Keys(FakeSysfs):
    def test_unknown_gpu_key_fails_the_request(self):
        with self.assertRaisesRegex(ValueError, "Unknown gpu keys: clocks"):
            wrap.apply_gpu({"uuid": "GPU-x", "powerLimit": 300, "clocks": 1})

    def test_unknown_cpu_key_fails_the_request(self):
        with self.assertRaisesRegex(ValueError, "Unknown cpu keys: bogus"):
            wrap.apply_cpu({"governor": "performance", "bogus": 1})

    def _main_reply(self, stdin_text):
        """Run main for real and read its stdout line. fail() sys.exits — a
        SystemExit from the protocol path is success-shaped, so it is caught."""
        import contextlib
        import io
        out = io.StringIO()
        with mock.patch.object(wrap.sys, "stdin", new=mock.Mock(readline=lambda: stdin_text)):
            with contextlib.redirect_stdout(out):
                try:
                    wrap.main()
                except SystemExit:
                    pass
        return json.loads(out.getvalue().splitlines()[-1])

    def test_unknown_top_level_key_fails_the_request(self):
        """The root side enforces its own contract: main refuses an unknown
        top-level key before any section runs."""
        reply = self._main_reply('{"gpu":{"uuid":"GPU-x"},"nuke":1}')
        self.assertFalse(reply["ok"])
        self.assertIn("Unknown request keys: nuke", reply["error"])

    def test_empty_request_refused(self):
        """main refuses an empty request; a no-knob gpu section is refused the
        same way at main level (the gpu branch reports 'carries no knob')."""
        reply = self._main_reply("{}")
        self.assertFalse(reply["ok"])
        self.assertIn("Nothing to apply", reply["error"])


class Booleans(FakeSysfs):
    def test_true_is_not_one_for_persistence(self):
        with mock.patch.object(wrap.shutil, "which", return_value="/usr/bin/nvidia-smi"), \
             mock.patch.object(wrap.subprocess, "run",
                               side_effect=AssertionError("a bool must never reach nvidia-smi")):
            with self.assertRaises(ValueError):
                wrap.apply_gpu({"uuid": "GPU-4dd10772-f4c4-da37-9022-c96d2f26f9aa", "persistence": True})

    def test_power_limit_refuses_bools(self):
        with mock.patch.object(wrap.shutil, "which", return_value="/usr/bin/nvidia-smi"), \
             mock.patch.object(wrap.subprocess, "run",
                               side_effect=AssertionError("a bool must never reach nvidia-smi")):
            with self.assertRaises(ValueError):
                wrap.apply_gpu({"uuid": "GPU-4dd10772-f4c4-da37-9022-c96d2f26f9aa", "powerLimit": True})


class PowerLimit(FakeSysfs):
    def test_limits_are_rechecked_as_root_for_that_uuid(self):
        row = "GPU-4dd10772-f4c4-da37-9022-c96d2f26f9aa, 150.00, 400.00, Disabled"
        seen = []
        def fake_run(args, **kwargs):
            seen.append(args)
            if any("--query-gpu" in a for a in args):
                return mock.Mock(returncode=0, stdout=row)
            return mock.Mock(returncode=0, stdout="")
        with mock.patch.object(wrap.shutil, "which", return_value="/usr/bin/nvidia-smi"), \
             mock.patch.object(wrap.subprocess, "run", side_effect=fake_run):
            with self.assertRaisesRegex(ValueError, "between 150 and 400"):
                wrap.apply_gpu({"uuid": "GPU-4dd10772-f4c4-da37-9022-c96d2f26f9aa", "powerLimit": 999})
        with mock.patch.object(wrap.shutil, "which", return_value="/usr/bin/nvidia-smi"), \
             mock.patch.object(wrap.subprocess, "run", side_effect=fake_run):
            applied = wrap.apply_gpu({"uuid": "GPU-4dd10772-f4c4-da37-9022-c96d2f26f9aa", "powerLimit": 300})
        self.assertEqual(applied["powerLimit"], 300)
        self.assertEqual(seen[-1], ["nvidia-smi", "-i", "GPU-4dd10772-f4c4-da37-9022-c96d2f26f9aa", "-pl", "300"])


class CpuFreq(FakeSysfs):
    def test_governor_must_come_from_the_kernel_list(self):
        with self.assertRaisesRegex(ValueError, "not offered"):
            wrap.apply_cpu({"governor": "turbo"})

    def test_epp_must_come_from_the_kernel_list(self):
        with self.assertRaisesRegex(ValueError, "not offered"):
            wrap.apply_cpu({"epp": "max-power"})

    def test_max_freq_validates_against_HARDWARE_range_not_the_user_ceiling(self):
        """securitybot B3: scaling_max_freq is a user-set ceiling (already
        lowered to 400000 here); validating a raise against it would make one
        lower permanent. The hardware max is 5053377, so 5053000 must pass and
        actually be written."""
        applied = wrap.apply_cpu({"maxFreqKHz": 5053000})
        self.assertEqual(applied["scaling_max_freq"], 5053000)
        self.assertEqual(self.read("scaling_max_freq"), "5053000")

    def test_max_freq_above_hardware_is_refused(self):
        with self.assertRaisesRegex(ValueError, "hardware range"):
            wrap.apply_cpu({"maxFreqKHz": 6000000})

    def test_writes_land_on_every_cpu_policy(self):
        second = self.tmp / "cpu1" / "cpufreq"
        second.mkdir(parents=True)
        for name in ("scaling_available_governors", "energy_performance_available_preferences",
                     "cpuinfo_min_freq", "cpuinfo_max_freq", "scaling_min_freq", "scaling_max_freq"):
            second.joinpath(name).write_text(self.policy.joinpath(name).read_text())
        applied = wrap.apply_cpu({"governor": "powersave"})
        self.assertEqual(applied["scaling_governor"], "powersave")
        self.assertEqual(self.read("scaling_governor"), "powersave")
        self.assertEqual((second / "scaling_governor").read_text().strip(), "powersave")


if __name__ == "__main__":
    unittest.main()
