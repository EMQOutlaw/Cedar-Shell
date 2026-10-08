#!/usr/bin/env python3
"""Offscreen: CEDAR Station's diagnostics over fixture collectors, and its pages at two widths.

Test mode never runs station.py or settings_info.py; fixtures stand in for
the snapshot and the service list. The engine itself is covered by
tests/core/diagnostics_test.js.
"""
from pathlib import Path
import json, os, re, shutil, subprocess, sys, tempfile
ROOT = Path(__file__).resolve().parents[1]
SNAPSHOT = {"failedUnits": [{"unit": "backup.service", "user": True, "load": "loaded", "active": "failed", "sub": "failed", "description": "Nightly backup", "result": "failed"}],
            "logIssues": [{"line": "@modules/X.qml[12:-1]: ReferenceError: foo is not defined", "count": 2, "kind": "binding"}],
            "config": [], "gpu": {"available": True, "source": "sysfs", "utilization": 12, "temperature": 41}, "shellMemoryMb": 420, "logPath": "/tmp/shell.log"}
SERVICES = [{"name": "PipeWire", "unit": "pipewire.service", "user": True, "status": "Healthy", "detail": "active · running · success"},
            {"name": "NetworkManager", "unit": "NetworkManager.service", "user": False, "status": "Failed", "detail": "failed · failed · exit-code"},
            {"name": "Bluetooth", "unit": "bluetooth.service", "user": False, "status": "Unavailable", "detail": "not loaded"}]
with tempfile.TemporaryDirectory(prefix='cedar-station-') as tmp:
    p = Path(tmp); source = p / 'shell'; shutil.copytree(ROOT, source, ignore=shutil.ignore_patterns('__pycache__', '.git'))
    runtime = p / 'runtime'; runtime.mkdir(mode=0o700)
    shots = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else p / 'shots'; shots.mkdir(parents=True, exist_ok=True)
    (source / 'preview.qml').write_text('''
import QtQuick
import Quickshell
import "."
import "modules"
import "services"
ShellRoot {
    id: window
    property int step: 0
    function check(ok, msg) { if (!ok) { console.error("FAIL: " + msg); Qt.exit(1); } }
    FloatingWindow {
        id: win; visible: true; implicitWidth: 1180; implicitHeight: 820; color: Theme.background
        property int pagesWidth: 1180
        StationPages { id: pages; width: win.pagesWidth; height: win.height }
    }
    function shot(name) { pages.grabToImage(r => r.saveToFile(Quickshell.env("CEDAR_SCREENSHOT_DIR") + "/" + name + ".png")); }
    Timer {
        interval: 500; running: true; repeat: true
        onTriggered: {
            switch (window.step++) {
            case 0:
                window.check(!Station.ready && Station.status === "reading" && Station.issues.length === 0, "Before data nothing is claimed (" + Station.status + ")");
                SettingsInfo.data = Object.assign({}, SettingsInfo.data, { services: %s, hostname: "test-host" });
                Station.data = %s; Station.ready = true; Station.readAt = Date.now();
                break;
            case 1:
                window.check(Station.status === "risk" && Station.headline === "Needs fixing", "A failed system service makes the status risk (" + Station.status + ")");
                const ids = Station.issues.map(i => i.id);
                window.check(ids[0] === "service/NetworkManager.service" && Station.issues[0].privileged === true, "The failed system service is first and needs privileges (" + ids.join() + ")");
                window.check(ids.includes("unit/user/backup.service") && ids.some(i => i.indexOf("log/binding/") === 0), "Failed user unit and the binding error are issues");
                window.check(Station.criticalCount === 1 && Station.warningCount === 2 && Station.updates === -1, "Counts and no update claim before a check (" + Station.criticalCount + "/" + Station.warningCount + "/" + Station.updates + ")");
                window.check(Station.healthyServices === 1, "One healthy service");
                window.shot("station-health");
                pages.navigate("issues");
                break;
            case 2:
                window.shot("station-issues");
                Station.openPage("services");
                window.check(pages.page === "services" && Station.requestedPage === "", "A page request navigates and is consumed");
                break;
            case 3:
                window.shot("station-services");
                pages.navigate("log"); win.pagesWidth = 640;
                break;
            case 4:
                window.check(!pages.sidebar, "Narrow windows use the tab strip");
                window.shot("station-narrow-log");
                // Clearing the failures clears the status.
                SettingsInfo.data = Object.assign({}, SettingsInfo.data, { services: SettingsInfo.data.services.map(s => Object.assign({}, s, { status: s.status === "Failed" ? "Healthy" : s.status })) });
                Station.data = Object.assign({}, Station.data, { failedUnits: [], logIssues: [] });
                window.check(Station.status === "healthy" && Station.issues.length === 0, "Healthy once the readings are clean (" + Station.status + ")");
                break;
            case 5:
                console.log("PASS: Station diagnostics from fixture readings and the pages at two widths");
                Qt.quit();
            }
        }
    }
}
''' % (json.dumps(SERVICES), json.dumps(SNAPSHOT)))
    env = {**os.environ, 'CEDAR_TEST': '1', 'QT_QPA_PLATFORM': 'offscreen', 'QT_QPA_PLATFORMTHEME': 'basic', 'QT_QUICK_CONTROLS_STYLE': 'Basic', 'QSG_RHI_BACKEND': 'software', 'XDG_RUNTIME_DIR': str(runtime), 'XDG_CONFIG_HOME': str(p / 'config'), 'XDG_STATE_HOME': str(p / 'state'), 'CEDAR_SCREENSHOT_DIR': str(shots)}
    result = subprocess.run(['qs', '-p', str(source / 'preview.qml')], env=env, capture_output=True, text=True, timeout=90)
    output = result.stdout + result.stderr
    if result.returncode or 'PASS: Station' not in output or re.search(r'Failed to load configuration|ReferenceError|TypeError|Binding loop|Cannot assign|is not defined|Unable to assign|FAIL:', output):
        print(output[-8000:]); raise SystemExit(1)
    print('PASS: Station diagnostics from fixture readings and the pages at two widths')
