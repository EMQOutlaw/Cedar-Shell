#!/usr/bin/env python3
"""Measure CedarAtmosphere's isolated backing allocation without locking.

Compare --baseline-ref <commit> with the current checkout using the same width,
height and QT_SCALE_FACTOR. This software-renderer fixture measures one
Quickshell process, not the CEDAR group or native GPU/Wayland allocations.
Allocation measurements do not establish visual equivalence. The attempted
backing crop at b042e7a was reverted after native fractional-scale regressions;
production retains the full backing until a visually equivalent fix is proven.
"""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import threading

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from measure_resources import memory_fields

HARNESS = '''
import QtQuick
import Quickshell
import "."
import "components"
ShellRoot {
    settings.watchFiles: false
    FloatingWindow {
        visible: true
        implicitWidth: Number(Quickshell.env("CEDAR_FIXTURE_WIDTH"))
        implicitHeight: Number(Quickshell.env("CEDAR_FIXTURE_HEIGHT"))
        CedarAtmosphere { anchors.fill: parent; active: false }
    }
    Timer { interval: 1800; running: true; onTriggered: { console.log("MEASURE atmosphere"); finish.start(); } }
    Timer { id: finish; interval: 100; onTriggered: Qt.quit() }
}
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline-ref")
    parser.add_argument("--width", type=int, default=2880)
    parser.add_argument("--height", type=int, default=1800)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if not (128 <= args.width <= 7680 and 128 <= args.height <= 4320):
        parser.error("Fixture size must be between 128x128 and 7680x4320")
    with tempfile.TemporaryDirectory(prefix="cedar-atm-") as temporary:
        base = Path(temporary)
        source = base / "shell"
        shutil.copytree(ROOT, source, ignore=shutil.ignore_patterns(".git", "__pycache__"))
        for name in ("runtime", "config", "cache", "state"):
            (base / name).mkdir(mode=0o700)
        if args.baseline_ref:
            revision = subprocess.check_output(["git", "rev-parse", "--verify", "--end-of-options",
                                                args.baseline_ref + "^{commit}"], cwd=ROOT, text=True).strip()
            original = subprocess.check_output(["git", "show", revision + ":components/CedarAtmosphere.qml"],
                                               cwd=ROOT, text=True)
            (source / "components/CedarAtmosphere.qml").write_text(original)
        (source / "audit.qml").write_text(HARNESS)
        env = {**os.environ, "CEDAR_TEST": "1", "CEDAR_LOCAL_ONLY": "1",
               "CEDAR_FIXTURE_WIDTH": str(args.width), "CEDAR_FIXTURE_HEIGHT": str(args.height),
               "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software", "QSG_RENDER_LOOP": "basic",
               "QT_QPA_PLATFORMTHEME": "basic", "QT_QUICK_CONTROLS_STYLE": "Basic",
               "XDG_RUNTIME_DIR": str(base / "runtime"), "XDG_CONFIG_HOME": str(base / "config"),
               "XDG_CACHE_HOME": str(base / "cache"), "XDG_STATE_HOME": str(base / "state")}
        process = subprocess.Popen(["qs", "-p", str(source / "audit.qml")], env=env,
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                                   start_new_session=True)
        def stop_fixture():
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        deadline = threading.Timer(15, stop_fixture)
        deadline.start()
        output, measured = [], None
        try:
            for line in process.stdout:
                output.append(line)
                if "MEASURE atmosphere" in line:
                    measured = memory_fields(Path(f"/proc/{process.pid}/smaps_rollup").read_text())
            process.wait()
        finally:
            deadline.cancel()
            stop_fixture()
            process.wait()
        log = "".join(output)
        report = {"scope": "isolated CedarAtmosphere Quickshell process", "baseline_ref": args.baseline_ref,
                  "logical_size": [args.width, args.height], "backend": "offscreen software",
                  "scale_factor": env.get("QT_SCALE_FACTOR", "1"), "memory_bytes": measured}
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2) + "\n")
        args.output.with_suffix(".log").write_text(log)
        print(json.dumps(report, indent=2))
        if process.returncode or not measured or measured["pss"] is None or re.search(
                r"FATAL:|Failed to load configuration|ReferenceError|TypeError|Binding loop|Cannot assign|Unable to assign", log):
            print(log)
            raise SystemExit(1)


if __name__ == "__main__":
    main()
