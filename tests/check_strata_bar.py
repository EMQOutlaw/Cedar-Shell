#!/usr/bin/env python3
"""Check Strata layout and per-output anchors using real offscreen Qt windows.

Requires a compatible Quickshell installation. These checks do not certify
native Wayland placement, compositor workspaces, tray menus or hardware state.
Screenshots use the production contents, frame and Core with isolated settings.
"""
from pathlib import Path
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[1]
WIDTHS = (640, 960, 1280)
PASS = "PASS: Strata layout, enlarged text and per-output anchors"
ERRORS = re.compile(
    r"Failed to load configuration|ReferenceError|TypeError|Binding loop|"
    r"Cannot assign|is not defined|Unable to assign|FAIL:|has crashed"
)


def main():
    quickshell = shutil.which("qs")
    if not quickshell:
        print("NOT RUN: Strata offscreen checks require Quickshell (qs).", file=sys.stderr)
        return 2
    with tempfile.TemporaryDirectory(prefix="cedar-strata-check-") as tmp:
        base = Path(tmp)
        source = base / "shell"
        shutil.copytree(ROOT, source, ignore=shutil.ignore_patterns("__pycache__", ".git"))
        harness = (ROOT / "tests/core/StrataBarHarness.qml").read_text()
        (source / "preview.qml").write_text(harness.replace('"../.."', '"."').replace('"../../', '"'))
        shots = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else base / "shots"
        shots.mkdir(parents=True, exist_ok=True)
        for width in WIDTHS:
            run = base / str(width)
            runtime = run / "runtime"
            runtime.mkdir(parents=True, mode=0o700)
            config = run / "config/cedar"
            config.mkdir(parents=True)
            (config / "settings.json").write_text(json.dumps({
                "barStyle": "cedar", "barHeight": 44, "coreMonitor": "STRATA-1",
                "mainDisplay": "STRATA-1", "coreEnabled": True, "coreWarnings": False,
                "reducedMotion": True, "barShowDate": True, "showWeekday": True,
                "clock24": True, "fontScale": 1, "localOnly": True,
            }))
            screens = run / "screens.json"
            screens.write_text(json.dumps({"screens": [
                {"name": "STRATA-1", "width": width, "height": 720},
                {"name": "STRATA-2", "x": width, "width": width, "height": 720},
            ]}))
            env = {
                **os.environ, "CEDAR_TEST": "1", "CEDAR_LOCAL_ONLY": "1",
                "CEDAR_STRATA_WIDTH": str(width), "CEDAR_SCREENSHOT_DIR": str(shots),
                "QT_QPA_PLATFORM": "offscreen:configfile=" + str(screens),
                "QT_QPA_PLATFORMTHEME": "basic", "QT_QUICK_CONTROLS_STYLE": "Basic",
                "QT_QUICK_BACKEND": "software", "XDG_RUNTIME_DIR": str(runtime),
                "XDG_CONFIG_HOME": str(run / "config"), "XDG_STATE_HOME": str(run / "state"),
                "XDG_CACHE_HOME": str(run / "cache"),
            }
            result = subprocess.run(
                [quickshell, "-p", str(source / "preview.qml")], env=env,
                capture_output=True, text=True, timeout=30,
            )
            output = result.stdout + result.stderr
            if result.returncode or PASS not in output or ERRORS.search(output):
                print(output)
                return 1
            for output_name in ("STRATA-1", "STRATA-2"):
                for enabled in ("core", "plain"):
                    for scale in ("1", "1p3"):
                        filename = f"strata-{width}-{output_name}-{enabled}-{scale}.png"
                        if not (shots / filename).is_file():
                            print("FAIL: Missing screenshot " + filename, file=sys.stderr)
                            return 1
        print("PASS: Strata at 640/960/1280px, Core on/off, font scales 1/1.3, two output anchors; 24 screenshots")
        print("Native Wayland, live workspaces, tray menus and hardware interaction remain separate checks.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
