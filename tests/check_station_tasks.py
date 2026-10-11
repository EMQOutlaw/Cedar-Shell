#!/usr/bin/env python3
"""Field Station tasks: real QML sorting/filtering/routes and narrow render; no hardware actions."""
from pathlib import Path
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='cedar-tasks-') as tmp:
    base = Path(tmp)
    source = base / 'shell'
    shutil.copytree(ROOT, source, ignore=shutil.ignore_patterns('.git', '__pycache__'))
    runtime = base / 'runtime'
    runtime.mkdir(mode=0o700)
    shots = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else base / 'shots'
    shots.mkdir(parents=True, exist_ok=True)
    (source / 'preview.qml').write_text('''
import QtQuick
import Quickshell
import "."
import "modules"
import "services"
ShellRoot {
    FloatingWindow {
        id: window
        visible: true
        implicitWidth: 960; implicitHeight: 1000
        color: Theme.strataFoundation
        StationTasks { id: tasks; x: 20; y: 20; width: window.width - 40; active: true }
        FieldStation { id: station; x: 20; y: 20; width: 480; bare: true; visible: false; active: visible }
        function find(item, name) {
            if (item.objectName === name) return item;
            for (const child of item.children || []) { const result = find(child, name); if (result) return result; }
            return null;
        }
        function check(ok, message) { if (!ok) { console.error("FAIL: " + message); Qt.exit(1); } }
        Component.onCompleted: {
            Config.set("reducedMotion", true);
            SystemStats.cpu = .42; SystemStats.ram = .58; SystemStats.disk = .31;
            SystemStats.memoryLabel = "9.3 / 16 GiB"; SystemStats.temperature = 53;
            tasks.snapshot = {total:3, omitted:0,
                cores:Array.from({length:8}, (_,i)=>({name:"cpu"+i,cpu:i*12})),
                gpus:[{name:"Fixture GPU",load:24,temperature:48,used:512,total:8192}],
                processes:[{pid:12,start:"10",name:"browser",user:"fixture",cpu:135.4,rss:805306368,state:"S",threads:34},
                    {pid:5,start:"20",name:"editor",user:"fixture",cpu:4.2,rss:1073741824,state:"S",threads:10},
                    {pid:42,start:"30",name:"quickshell",user:"fixture",cpu:null,rss:83886080,state:"S",threads:8}]};
        }
        property int step: 0
        Timer {
            interval: 350; running: true; repeat: true
            onTriggered: {
                if (window.step === 0) {
                    window.check(tasks.rows[0].pid === 12, "CPU sort uses measured values");
                    tasks.sortBy = "rss";
                    window.check(tasks.rows[0].pid === 5, "Memory sort");
                    tasks.query = "42";
                    window.check(tasks.rows.length === 1 && tasks.rows[0].name === "quickshell", "PID filter");
                    tasks.query = "EDITOR";
                    window.check(tasks.rows.length === 1 && tasks.rows[0].pid === 5, "Case-insensitive name filter");
                    tasks.query = "missing";
                    window.check(tasks.rows.length === 0, "Empty filter result");
                    tasks.query = ""; tasks.sortBy = "cpu";
                    window.check(tasks.percent(null) === "—", "First sample stays unknown");
                    window.check(!tasks.sampling, "Test mode never starts real process sampling");
                    tasks.grabToImage(r=>r.saveToFile(Quickshell.env("CEDAR_SCREENSHOT_DIR")+"/tasks-wide.png"));
                } else if (window.step === 1) {
                    tasks.width = 440; Config.set("fontScale", 1.3);
                } else if (window.step === 2) {
                    tasks.grabToImage(r=>r.saveToFile(Quickshell.env("CEDAR_SCREENSHOT_DIR")+"/tasks-narrow.png"));
                } else if (window.step === 3) {
                    window.check(tasks.width === 440, "Narrow task view width");
                    tasks.paused = true;
                    window.check(!tasks.sampling, "Pause stops demand");
                    tasks.applications = true;
                    window.check(tasks.rows.length === tasks.windows.length, "Application view uses compositor windows");
                    Canopy.open("system");
                    window.check(Canopy.topic === "station" && Canopy.stationPage === "tasks", "Legacy System route opens Field Station tasks");
                    Canopy.close();
                    ShellState.locked = true; Canopy.openStation("tasks");
                    window.check(!Canopy.shown && !tasks.sampling, "Lock guard");
                    ShellState.locked = false;
                } else if (window.step === 4) {
                    tasks.visible = false; station.visible = true;
                    Canopy.stationPage = "tasks";
                    const embedded = window.find(station, "stationTasks");
                    window.check(embedded && embedded.active, "Field Station activates its task page");
                    embedded.snapshot = tasks.snapshot;
                } else if (window.step === 5) {
                    station.grabToImage(r=>r.saveToFile(Quickshell.env("CEDAR_SCREENSHOT_DIR")+"/tasks-embedded.png"));
                } else {
                    Canopy.stationPage = "overview";
                    window.check(!window.find(station, "stationTasks").active, "Overview stops task-page demand");
                    console.log("PASS: Field Station task sorting, filters, aliases and narrow layout"); Qt.quit();
                }
                window.step++;
            }
        }
    }
}
''')
    env = {**os.environ, 'CEDAR_TEST':'1', 'QT_QPA_PLATFORM':'offscreen', 'QT_QPA_PLATFORMTHEME':'basic',
           'QT_QUICK_CONTROLS_STYLE':'Basic', 'QT_QUICK_BACKEND':'software', 'QSG_RENDER_LOOP':'basic',
           'XDG_RUNTIME_DIR':str(runtime), 'XDG_CONFIG_HOME':str(base/'config'),
           'XDG_STATE_HOME':str(base/'state'), 'CEDAR_SCREENSHOT_DIR':str(shots)}
    result = subprocess.run(['qs','-p',str(source/'preview.qml')],env=env,capture_output=True,text=True,timeout=20)
    output = result.stdout + result.stderr
    if result.returncode or 'PASS: Field Station task sorting' not in output or re.search(r'FAIL:|ReferenceError|TypeError|Binding loop|Cannot assign|is not defined|Unable to assign|has crashed',output):
        print(output)
        raise SystemExit(1)
    if len(list(shots.glob('tasks-*.png'))) != 3:
        print(output)
        raise SystemExit('Missing task renders')
    print('PASS: Field Station task sorting, filters, aliases and narrow layout')
