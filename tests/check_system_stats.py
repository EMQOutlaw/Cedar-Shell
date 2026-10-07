#!/usr/bin/env python3
"""Offscreen: SystemStats reads /proc and hwmon in-process, and Forest recomputes on events.

Test mode keeps `demanded` off, so the harness forces samples itself. `df` is
the only process the sampler may start; nothing here spawns the telemetry
helper. Pass a hwmon temp*_input path in CEDAR_CHECK_SENSOR to read a real
sensor; without one the temperature path is checked against a fixture file.
"""
from pathlib import Path
import json, os, re, shutil, subprocess, sys, tempfile
ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='cedar-stats-') as tmp:
    p = Path(tmp); source = p / 'shell'; shutil.copytree(ROOT, source, ignore=shutil.ignore_patterns('__pycache__', '.git'))
    runtime = p / 'runtime'; runtime.mkdir(mode=0o700)
    sensor = os.environ.get('CEDAR_CHECK_SENSOR', '')
    if not sensor:
        fixture = p / 'temp1_input'; fixture.write_text('47500\n'); sensor = str(fixture)
    (source / 'preview.qml').write_text('''
import QtQuick
import Quickshell
import "."
import "services"
ShellRoot {
    id: window
    property int step: 0
    property string sensor: "%s"
    function check(ok, msg) { if (!ok) { console.error("FAIL: " + msg); Qt.exit(1); } }
    Timer {
        interval: 700; running: true; repeat: true
        onTriggered: {
            switch (window.step++) {
            case 0:
                window.check(!SystemStats.demanded, "Test mode does not schedule sampling");
                window.check(SystemStats.cpu === -1 && SystemStats.available === false, "Nothing is read before demand");
                SystemStats.sensorPaths = [window.sensor]; SystemStats.discovered = true; SystemStats.discoveredAt = Date.now();
                SystemStats.sample(true);
                break;
            case 1:
                window.check(SystemStats.available, "A forced sample reads /proc/stat");
                window.check(SystemStats.ram > 0 && SystemStats.ram < 1, "Memory fraction from /proc/meminfo (" + SystemStats.ram + ")");
                window.check(/^\\d+\\.\\d \\/ \\d+\\.\\d GiB$/.test(SystemStats.memoryLabel), "Memory label (" + SystemStats.memoryLabel + ")");
                window.check(/^\\d+d \\d+h \\d+m$/.test(SystemStats.uptime), "Uptime from /proc/uptime (" + SystemStats.uptime + ")");
                window.check(SystemStats.temperature > 0 && SystemStats.temperature < 150, "Temperature from the hwmon input (" + SystemStats.temperature + ")");
                SystemStats.sample(true);
                break;
            case 2:
                window.check(SystemStats.cpu >= 0 && SystemStats.cpu <= 1, "CPU fraction after two /proc/stat reads (" + SystemStats.cpu + ")");
                window.check(SystemStats.networkRate >= 0, "Network rate from /proc/net/dev (" + SystemStats.networkRate + ")");
                window.check(SystemStats.disk > 0 && SystemStats.disk < 1, "Disk fraction from df (" + SystemStats.disk + ")");
                // Forest: an event recomputes the state without a running clock.
                window.check(["QUIET","AWAKE","FLOW","HUNT","WATCH","EMBER","REST"].includes(Forest.state), "Forest state is valid (" + Forest.state + ")");
                CoreService.publish({ id: "check-warning", type: "warning", priority: "critical", title: "Check", subtitle: "harness", persistent: true, sticky: true });
                break;
            case 3:
                window.check(Forest.state === "EMBER", "A published warning turns the forest to EMBER on the event (" + Forest.state + ")");
                CoreService.remove("check-warning", false);
                break;
            case 4: case 5: case 6: case 7:
                if (Forest.state !== "EMBER") { window.step = 8; }
                break;
            case 8:
                window.check(Forest.state !== "EMBER", "Removing the warning settles the forest again (" + Forest.state + ")");
                // Performance mode: the basics only, on demand or by rule.
                window.check(Config.performanceMode === "auto" && !Config.performanceActive, "Automatic performance mode is off without a power-saver profile or fullscreen focus");
                Config.set("performanceMode", "on");
                window.check(Config.performanceActive && Theme.reducedMotion && !SystemStats.ambient && Config.performanceReason === "always on", "Always-on performance mode reduces motion and stops ambient telemetry (" + Config.performanceReason + ")");
                Config.set("reducedMotion", false);
                Config.set("performanceMode", "off");
                window.check(!Config.performanceActive && !Theme.reducedMotion, "Off restores motion");
                Config.set("performanceMode", "bogus");
                window.check(Config.performanceMode === "auto", "Unknown values fall back to automatic");
                console.log("PASS: SystemStats in-process reads and event-driven Forest");
                Qt.quit();
            }
        }
    }
}
''' % sensor)
    env = {**os.environ, 'CEDAR_TEST': '1', 'QT_QPA_PLATFORM': 'offscreen', 'QT_QPA_PLATFORMTHEME': 'basic', 'QT_QUICK_CONTROLS_STYLE': 'Basic', 'QSG_RHI_BACKEND': 'software', 'XDG_RUNTIME_DIR': str(runtime), 'XDG_CONFIG_HOME': str(p / 'config'), 'XDG_STATE_HOME': str(p / 'state')}
    result = subprocess.run(['qs', '-p', str(source / 'preview.qml')], env=env, capture_output=True, text=True, timeout=40)
    output = result.stdout + result.stderr
    if result.returncode or 'PASS: SystemStats' not in output or re.search(r'Failed to load configuration|ReferenceError|TypeError|Binding loop|Cannot assign|is not defined|Unable to assign|FAIL:', output):
        print(output[-5000:]); raise SystemExit(1)
    print('PASS: SystemStats in-process reads and event-driven Forest')
