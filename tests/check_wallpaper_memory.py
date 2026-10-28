#!/usr/bin/env python3
"""Measure the production wallpaper grid with six deterministic 4K images.

Only the Overlay window host is replaced by a Rectangle for offscreen use;
the production loader, grid, image delegates and asynchronous decoding run
unchanged. Reports isolated Quickshell PSS/RSS/private memory, not the entire
CEDAR process budget. --baseline-ref reads the old picker from Git without
changing the checkout. No installed shell or personal wallpapers are used.
"""
import argparse
import binascii
import json
import os
from pathlib import Path
import re
import shutil
import signal
import struct
import subprocess
import tempfile
import threading
import zlib

ROOT = Path(__file__).resolve().parents[1]

HARNESS = '''
import QtQuick
import QtTest
import Quickshell
import "."
import "modules"
ShellRoot {
    settings.watchFiles: false
    FloatingWindow {
        id: window
        visible: true
        implicitWidth: 1200; implicitHeight: 850
        WallpaperPicker { id: picker; anchors.fill: parent; output: null }
        TestCase {
            name: "WallpaperMemory"
            when: window.visible
            function images(item) {
                let found = item.sourceSize !== undefined && item.status !== undefined ? [item] : [];
                for (const child of item.children || []) found = found.concat(images(child));
                return found;
            }
            function measure(phase) { console.log("MEASURE " + JSON.stringify({phase: phase})); }
            function test_grid_lifecycle() {
                wait(500); measure("idle");
                for (let cycle = 0; cycle < 5; cycle++) {
                    ShellState.panel = "wallpapers";
                    tryVerify(() => picker.wallpapers.length === 6, 5000);
                    tryVerify(() => images(picker).length >= 4 && images(picker).every(i => i.status === Image.Ready), 10000);
                    wait(500);
                    const decoded = images(picker).map(i => ({width: i.sourceSize.width, height: i.sourceSize.height, cache: i.cache}));
                    console.log("DECODE " + JSON.stringify({cycle: cycle, images: decoded}));
                    if (Quickshell.env("CEDAR_WALLPAPER_BASELINE") !== "1") {
                        verify(decoded.every(i => i.width < 2048 && i.height < 2048), "Thumbnails decode below full 4K resolution");
                        verify(decoded.every(i => !i.cache), "Transient wallpaper thumbnails do not enter Qt's image cache");
                    }
                    measure("open-" + cycle);
                    ShellState.panel = "";
                    wait(600);
                    compare(images(picker).length, 0, "Closing destroys every wallpaper image delegate");
                    compare(picker.wallpapers.length, 0, "Closing clears wallpaper metadata");
                    measure("closed-" + cycle);
                }
                console.log("PASS: wallpaper image sizing and five open-close cycles");
            }
        }
    }
}
'''


def png(path, color):
    def chunk(kind, value):
        return struct.pack(">I", len(value)) + kind + value + struct.pack(">I", binascii.crc32(kind + value))
    width, height = 4096, 2304
    compressor = zlib.compressobj()
    row = b"\0" + bytes(color) * width
    content = b"".join(compressor.compress(row) for _ in range(height)) + compressor.flush()
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
                     + chunk(b"IDAT", content) + chunk(b"IEND", b""))


def memory(pid):
    try:
        fields = {}
        for line in Path(f"/proc/{pid}/smaps_rollup").read_text().splitlines():
            match = re.match(r"(\w+):\s+(\d+) kB", line)
            if match:
                fields[match[1]] = int(match[2])
        return {"rss_kib": fields["Rss"], "pss_kib": fields["Pss"],
                "private_kib": fields.get("Private_Clean", 0) + fields.get("Private_Dirty", 0)}
    except (OSError, KeyError):
        return None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline-ref")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="cedar-img-") as temporary:
        base = Path(temporary)
        source = base / "shell"
        shutil.copytree(ROOT, source, ignore=shutil.ignore_patterns(".git", "__pycache__"))
        for name in ("runtime", "config", "state", "cache", "images"):
            (base / name).mkdir(mode=0o700)
        if args.baseline_ref:
            original = subprocess.run(["git", "show", f"{args.baseline_ref}:modules/WallpaperPicker.qml"],
                                      cwd=ROOT, check=True, capture_output=True, text=True).stdout
            (source / "modules/WallpaperPicker.qml").write_text(original)
        (source / "components/Overlay.qml").write_text('''
import QtQuick
import ".."
Rectangle {
    required property var output
    required property string panelName
    visible: ShellState.panel === panelName
}
''')
        items = []
        for index in range(6):
            path = base / "images" / f"wallpaper-{index}.png"
            png(path, (30 + index * 20, 80, 110))
            items.append({"path": str(path), "name": f"Wallpaper {index}"})
        payload = {"items": items, "selected": "", "folder": str(base / "images")}
        (source / "scripts/wallpapers.py").write_text(f"print({json.dumps(payload)!r})\n")
        (source / "audit.qml").write_text(HARNESS)
        env = {**os.environ, "CEDAR_TEST": "1", "CEDAR_LOCAL_ONLY": "1",
               "CEDAR_WALLPAPER_BASELINE": "1" if args.baseline_ref else "0",
               "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software", "QSG_RENDER_LOOP": "basic",
               "QT_QPA_PLATFORMTHEME": "basic", "QT_QUICK_CONTROLS_STYLE": "Basic",
               "XDG_RUNTIME_DIR": str(base / "runtime"), "XDG_CONFIG_HOME": str(base / "config"),
               "XDG_STATE_HOME": str(base / "state"), "XDG_CACHE_HOME": str(base / "cache")}
        process = subprocess.Popen(["qs", "-p", str(source / "audit.qml")], env=env,
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, start_new_session=True)
        samples, phases, output = [], [], []
        stop = threading.Event()
        def sample():
            while not stop.wait(.05):
                value = memory(process.pid)
                if value:
                    samples.append(value)
        sampler = threading.Thread(target=sample, daemon=True)
        sampler.start()
        def stop_fixture():
            # A Quickshell crash reporter can outlive its original process and
            # keep stdout open. The private process group owns only this test.
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        deadline = threading.Timer(60, stop_fixture)
        deadline.start()
        try:
            for line in process.stdout:
                output.append(line)
                if "MEASURE " in line:
                    value = memory(process.pid) or {}
                    phases.append({**json.loads(line.split("MEASURE ", 1)[1]), **value})
                    if value:
                        samples.append(value)
            process.wait()
        finally:
            deadline.cancel()
            stop_fixture()
            process.wait()
            stop.set()
            sampler.join()
        log = "".join(output)
        print(log)
        report = {"baseline_ref": args.baseline_ref, "scope": "isolated wallpaper fixture Quickshell process",
                  "backend": "offscreen software", "sample_interval_seconds": .05,
                  "sampled_peak": {key: max(row[key] for row in samples) for key in samples[0]} if samples else {},
                  "phases": phases}
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2) + "\n")
        args.output.with_suffix(".log").write_text(log)
        print(json.dumps(report, indent=2))
        if process.returncode or "PASS: wallpaper image sizing and five open-close cycles" not in log or re.search(
                r"FAIL[:!]|FATAL:|Failed to load configuration|ReferenceError|TypeError|Binding loop|Cannot assign|Unable to assign", log):
            raise SystemExit(1)


if __name__ == "__main__":
    main()
