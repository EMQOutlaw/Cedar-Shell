#!/usr/bin/env python3
"""Exercise production service ownership with disposable helper processes.

The copied services use the real Quickshell Process and ServiceRequest. Their
system adapters are replaced by deterministic fixtures, so this never changes
the desktop, power profile, calendar, or installed shell. Controls' ten-second
poll is shortened to 200 ms only in the copy; CoreProbe's real retry interval
and CalendarFeeds' real debounce interval are retained.
"""
import argparse
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

HARNESS = '''
import QtQuick
import QtTest
import Quickshell
import "."
import "services"
ShellRoot {
    settings.watchFiles: false
    CoreProbe { id: probe }
    TestCase {
        name: "ServiceLifecycle"
        when: true
        property int failures: 0
        function check(ok, message) {
            if (!ok) { failures++; console.error("FAIL: " + message); }
        }
        function test_calendar_waits_for_completion() {
            CalendarFeeds.request({action: "snapshot", delay: 1.2});
            CalendarFeeds.viewMonth(new Date(2026, 0, 1));
            wait(650);
            const wakeups = CalendarFeeds.auditWakeups;
            console.log("METRIC calendar_busy_debounce_wakeups=" + wakeups);
            check(wakeups === 1, "Calendar waits for completion instead of spinning while busy");
            CalendarFeeds.viewMonth(new Date(2026, 1, 1));
            CalendarFeeds.viewMonth(new Date(2026, 2, 1));
            tryVerify(() => !CalendarFeeds.busy && CalendarFeeds.events.length > 0
                      && CalendarFeeds.events[0].begin === "2026-03-01", 4000);
            check(CalendarFeeds.events[0].request === 2, "Month changes coalesce into one latest-month refresh");
            const settled = CalendarFeeds.auditWakeups;
            wait(350);
            check(CalendarFeeds.auditWakeups === settled, "Calendar debounce stops after delivery");
            console.log("PASS: calendar completion and latest-month delivery");
        }
        function test_controls_only_visible_consumers() {
            const initial = Controls.generation;
            ShellState.panel = "canopy";
            Canopy.topic = "quick"; Canopy.shown = true;
            wait(750);
            check(Controls.generation >= 2, "Quick controls receives continuing updates");
            Canopy.topic = "calendar";
            wait(100);
            const unrelatedStart = Controls.generation;
            wait(650);
            const unrelatedPolls = Controls.generation - unrelatedStart;
            console.log("METRIC unrelated_canopy_polls=" + unrelatedPolls);
            check(unrelatedPolls === 0, "Unrelated Canopy topics do not poll power controls");
            Canopy.shown = false; ShellState.panel = "";
            SettingsService.page = "power"; SettingsService.open = true;
            const powerStart = Controls.generation;
            wait(750);
            check(Controls.generation >= powerStart + 2, "Floating Settings power page gets fresh continuing updates");
            SettingsService.page = "appearance";
            wait(100);
            const hiddenStart = Controls.generation;
            wait(450);
            check(Controls.generation === hiddenStart, "Unrelated Settings pages do not poll power controls");
            SettingsService.page = "power";
            wait(350);
            ShellState.locked = true;
            wait(100);
            const lockedStart = Controls.generation;
            wait(450);
            check(Controls.generation === lockedStart, "Locking stops visual power polling");
            SettingsService.open = false; ShellState.locked = false;
            Understory.shown = true;
            const railStart = Controls.generation;
            wait(750);
            check(Controls.generation >= railStart + 2, "Understory receives continuing power updates");
            Understory.shown = false;
            wait(100);
            const railClosed = Controls.generation;
            wait(450);
            check(Controls.generation === railClosed, "Closing Understory stops visual power polling");
            console.log("PASS: controls visibility, settings navigation and lock lifecycle");
        }
        function test_probe_retry_retains_ownership() {
            probe.enabled = true;
            tryVerify(() => probe.data.start === 2, 18000);
            const before = probe.data.tick;
            wait(150);
            check(probe.data.tick > before, "Retried probe is producing live data");
            probe.enabled = false;
            wait(200);
            const stopped = probe.data.tick;
            wait(350);
            const leaked = probe.data.tick - stopped;
            console.log("METRIC disabled_probe_heartbeats=" + leaked);
            check(leaked === 0, "Disabling a retried probe stops its helper process");
            probe.enabled = true;
            wait(500);
            check(probe.data.start === 3, "Re-enabling starts a fresh owned helper");
            probe.enabled = false;
            console.log("PASS: probe restart, disable and re-enable ownership");
        }
        function cleanupTestCase() {
            if (failures) { console.error("FAIL: service lifecycle assertions: " + failures); Qt.exit(1); }
            else console.log("PASS: service lifecycle assertions completed");
        }
    }
}
'''

HELPER = '''
import json
from pathlib import Path
import sys
import time

counter = Path(__file__).with_suffix(".count")
count = int(counter.read_text()) + 1 if counter.exists() else 1
counter.write_text(str(count))
if Path(__file__).stem == "core_probe":
    if count == 1:
        raise SystemExit(1)
    tick = 0
    while True:
        print(json.dumps({"start": count, "tick": tick}), flush=True)
        tick += 1
        time.sleep(.05)
else:
    request = json.loads(sys.stdin.readline())
    time.sleep(request.get("delay", 0))
    data = {"profiles": ["balanced"], "profile": "balanced", "nightlight": False}
    if Path(__file__).stem == "calendar_service":
        data = {"sources": [], "events": [{"begin": request.get("begin"), "request": count}]}
    print(json.dumps({"ok": True, "data": data}))
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="cedar-svc-") as temporary:
        base = Path(temporary)
        for name in ("services", "components", "scripts", "runtime", "config", "state", "cache"):
            (base / name).mkdir(mode=0o700)
        (base / "qmldir").write_text("singleton Config 1.0 Config.qml\nsingleton ShellState 1.0 ShellState.qml\n")
        (base / "Config.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { property bool testMode: false; property bool localOnly: false }\n')
        (base / "ShellState.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { property bool locked: false; property string panel: "" }\n')
        (base / "services/qmldir").write_text("\n".join([
            "singleton Controls 1.0 Controls.qml", "singleton CalendarFeeds 1.0 CalendarFeeds.qml",
            "singleton Canopy 1.0 Canopy.qml", "singleton SettingsService 1.0 SettingsService.qml",
            "singleton Understory 1.0 Understory.qml",
            "CoreProbe 1.0 CoreProbe.qml", "",
        ]))
        (base / "services/Canopy.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { property bool shown: false; property string topic: "" }\n')
        (base / "services/SettingsService.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { property bool open: false; property string page: "overview" }\n')
        (base / 'services/Understory.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property bool shown: false }\n')
        for name in ("Controls", "CalendarFeeds", "CoreProbe"):
            source = (ROOT / "services" / f"{name}.qml").read_text()
            if name == "Controls":
                assert source.count("interval: 10000") == 1
                source = source.replace("interval: 10000", "interval: 200")
            if name == "CalendarFeeds":
                # Observe the actual debounce timer without changing its behavior.
                close = source.rfind("}")
                source = source[:close] + '''
    property int auditWakeups: 0
    Connections { target: load; function onTriggered() { root.auditWakeups++; } }
''' + source[close:]
            (base / "services" / f"{name}.qml").write_text(source)
        shutil.copy2(ROOT / "components/ServiceRequest.qml", base / "components/ServiceRequest.qml")
        for name in ("control", "calendar_service", "core_probe"):
            (base / "scripts" / f"{name}.py").write_text(HELPER)
        (base / "audit.qml").write_text(HARNESS)
        env = {**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software",
               "QSG_RENDER_LOOP": "basic", "QT_QPA_PLATFORMTHEME": "basic", "QT_QUICK_CONTROLS_STYLE": "Basic",
               "XDG_RUNTIME_DIR": str(base / "runtime"), "XDG_CONFIG_HOME": str(base / "config"),
               "XDG_STATE_HOME": str(base / "state"), "XDG_CACHE_HOME": str(base / "cache")}
        process = subprocess.Popen(["qs", "-p", str(base / "audit.qml")], env=env,
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                                   start_new_session=True)
        try:
            output, _ = process.communicate(timeout=40)
        finally:
            # Only this disposable fixture and its helper descendants belong
            # to the session, including on timeout or a Quickshell crash.
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait()
        print(output)
        if args.output:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(output)
        if process.returncode or "PASS: service lifecycle assertions completed" not in output or re.search(
                r"FAIL[:!]|Failed to load configuration|ReferenceError|TypeError|Binding loop|Cannot assign|Unable to assign", output):
            raise SystemExit(1)


if __name__ == "__main__":
    main()
