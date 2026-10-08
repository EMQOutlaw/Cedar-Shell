#!/usr/bin/env python3
"""Offscreen: CEDAR Focus sessions over the shared engine and the ownership stack.

A session applies its registry through the stack, counts only observed
notifications (held when CEDAR's own popup path hides them, interruptions
when they reach the screen), pauses and resumes, ends with a verified
restore and a history entry, coexists with a Desktop Profile, and the
window renders.
"""
from pathlib import Path
import json, os, re, shutil, subprocess, sys, tempfile
ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='cedar-focus-') as tmp:
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
    function state(id) { const s = Focus.steps.find(s => s.id === id); return s ? s.state : "missing"; }
    // A notification as NoticeStore sees it: only the fields Focus reads.
    function notice(app, urgency) { return { id: ++noticeId, appName: app, summary: "x", body: "", urgency: urgency, actions: [], dismiss: function() {} }; }
    property int noticeId: 100
    FloatingWindow {
        id: win; visible: true; implicitWidth: 1000; implicitHeight: 800; color: Theme.background
        FocusPages { id: pages; anchors.fill: parent }
    }
    function shot(name) { pages.grabToImage(r => r.saveToFile(Quickshell.env("CEDAR_SCREENSHOT_DIR") + "/" + name + ".png")); }
    Timer {
        interval: 500; running: true; repeat: true
        onTriggered: {
            switch (window.step++) {
            case 0:
                window.check(!Focus.active && Focus.remaining === 0 && Focus.summary === "Off" && Focus.history.length === 0, "Idle at first (" + Focus.summary + ")");
                window.check(Focus.registry.length === 5 && Focus.registry.filter(r => r.enabled).length === 4, "Registry from settings: trails left alone by default");
                Config.set("focusAllowedApps", "Signal, thunderbird");
                window.check(!Focus.start(0.5) && !Focus.start(1000), "Out-of-range lengths are refused");
                window.check(Focus.start(25), "A 25 minute session starts");
                break;
            case 1:
                window.check(Focus.active && !Focus.busy && !Focus.paused && Focus.planned === 1500 && Focus.remaining > 1490 && Focus.remaining <= 1500, "Session running with the deadline set (" + Focus.remaining + ")");
                window.check(window.state("dnd") === "active" && Config.saved.doNotDisturb === true && window.state("whispers") === "active" && window.state("ambient") === "active" && window.state("performance") === "active", "Four changes applied and verified (" + Focus.steps.map(s => s.id + ":" + s.state).join(",") + ")");
                window.check(window.state("trails") === "off" && Config.saved.forestTrails === false, "Trails left alone when turned off in Settings");
                window.check(Overrides.holder("doNotDisturb") === "focus" && Overrides.keysHeldBy("focus").length === 4, "Four keys held by focus");
                window.check(VisualQuality.efficient && Config.saved.ambientIntensity === 0, "The desktop is quiet");
                const row = CoreService.rows.find(r => r.id === "focus");
                window.check(!!row && row.persistent && row.actions.map(a => a.id).join() === "focus-pause,focus-end", "Core pill carries the Focus row with pause and end");
                // Observed statistics: an ordinary notice is held, a critical one and an excepted app interrupt.
                NoticeStore.noticeRecorded(window.notice("Firefox", 1));
                NoticeStore.noticeRecorded(window.notice("Firefox", 2));
                NoticeStore.noticeRecorded(window.notice("Signal", 1));
                window.check(Focus.held === 1 && Focus.interruptions === 2, "Held 1, interruptions 2 (" + Focus.held + "/" + Focus.interruptions + ")");
                window.check(Focus.allows("signal") && !Focus.allows("Firefox"), "Exceptions match by announced name, case-insensitively");
                Focus.pause();
                break;
            case 2:
                window.check(Focus.paused && Focus.remaining > 1490 && Focus.summary.indexOf("Paused") === 0, "Paused keeps the remaining time (" + Focus.summary + ")");
                Focus.resume();
                window.check(!Focus.paused && Focus.deadline > Date.now(), "Resumed with a fresh deadline");
                window.shot("focus-running");
                // Coexist: a profile on top of Focus holds DND above it.
                Profiles.activate("night");
                break;
            case 3:
                window.check(Profiles.active === "night" && Overrides.holder("doNotDisturb") === "profile", "Night holds DND above Focus");
                Focus.end();
                break;
            case 4:
                window.check(!Focus.active && !Focus.busy && Focus.history.length === 1 && !Focus.history[0].completed && Focus.history[0].held === 1 && Focus.history[0].interruptions === 2, "Ended early: one history entry with the observed counts (" + JSON.stringify(Focus.history[0]) + ")");
                window.check(Config.saved.doNotDisturb === true && window.state("dnd") === "restored", "DND left to Night (nested release restores nothing now) (" + Config.saved.doNotDisturb + ")");
                window.check(Config.saved.performanceMode === "auto" && window.state("performance") === "restored", "Performance mode restored by Focus, which was its top holder");
                window.check(Overrides.keysHeldBy("focus").length === 0 && !CoreService.rows.some(r => r.id === "focus"), "Nothing held and the pill row removed");
                Profiles.deactivate();
                break;
            case 5:
                window.check(Config.saved.doNotDisturb === false && Config.saved.ambientIntensity === .45, "Night's release restores the originals Focus found (" + Config.saved.doNotDisturb + ", " + Config.saved.ambientIntensity + ")");
                // Completion: a short session that runs out.
                Config.set("focusMinutes", 25);
                window.check(Focus.start(1), "A one minute session starts");
                Focus.deadline = Date.now() + 300; Focus.deadlineChanged();
                break;
            case 6:
                window.check(!Focus.active && Focus.history.length === 2 && Focus.history[0].completed === true, "The session completed itself at the deadline (" + JSON.stringify(Focus.history[0]) + ")");
                const done = CoreService.rows.find(r => r.id === "focus-complete");
                window.check(!!done && done.sticky && done.priority === 2, "Completion announced on the pill as a sticky high row");
                CoreService.invoke(done, "dismiss");
                window.check(!CoreService.rows.some(r => r.id === "focus-complete"), "Dismiss removes it");
                window.shot("focus-idle");
                break;
            case 7:
                console.log("PASS: Focus sessions apply, count observed notices, pause, nest with a profile, restore, complete and render");
                Qt.quit();
            }
        }
    }
}
''')
    env = {**os.environ, 'CEDAR_TEST': '1', 'QT_QPA_PLATFORM': 'offscreen', 'QT_QPA_PLATFORMTHEME': 'basic', 'QT_QUICK_CONTROLS_STYLE': 'Basic', 'QSG_RHI_BACKEND': 'software', 'XDG_RUNTIME_DIR': str(runtime), 'XDG_CONFIG_HOME': str(p / 'config'), 'XDG_STATE_HOME': str(p / 'state'), 'CEDAR_SCREENSHOT_DIR': str(shots)}
    result = subprocess.run(['qs', '-p', str(source / 'preview.qml')], env=env, capture_output=True, text=True, timeout=90)
    output = result.stdout + result.stderr
    if result.returncode or 'PASS: Focus' not in output or re.search(r'Failed to load configuration|ReferenceError|TypeError|Binding loop|Cannot assign|is not defined|Unable to assign|FAIL:', output):
        print(output[-8000:]); raise SystemExit(1)
    saved = json.loads((p / 'state' / 'cedar' / 'focus.json').read_text())
    assert len(saved['history']) == 2 and saved.get('active') is not True, saved
    print('PASS: Focus sessions apply, count observed notices, pause, nest with a profile, restore, complete and render')
