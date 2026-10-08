#!/usr/bin/env python3
"""Offscreen: Desktop Profiles over the shared Transaction engine and the ownership stack.

Test mode has no power, night-light or audio provider, so those steps must
report "unavailable"; the in-process steps (do-not-disturb, idle lock,
ambient intensity, performance mode, whispers) must apply, verify, count
and restore. Also: a manual change while held is respected, Gaming Mode and
a profile nest through the stack, profiles are exclusive, and the Profiles
window renders.
"""
from pathlib import Path
import json, os, re, shutil, subprocess, sys, tempfile
ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='cedar-profiles-') as tmp:
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
    function state(id) { const s = Profiles.steps.find(s => s.id === id); return s ? s.state : "missing"; }
    FloatingWindow {
        id: win; visible: true; implicitWidth: 1100; implicitHeight: 820; color: Theme.background
        ProfilesPages { id: pages; anchors.fill: parent }
    }
    function shot(name) { pages.grabToImage(r => r.saveToFile(Quickshell.env("CEDAR_SCREENSHOT_DIR") + "/" + name + ".png")); }
    Timer {
        interval: 500; running: true; repeat: true
        onTriggered: {
            switch (window.step++) {
            case 0:
                window.check(Profiles.definitions.length === 6 && Profiles.definitions.map(d => d.id).join() === "balanced,work,battery,night,gaming,custom", "Six profiles in order");
                window.check(Profiles.current === "" && !Profiles.busy && Profiles.summary === "No profile", "Nothing active at first (" + Profiles.summary + ")");
                window.check(Config.saved.doNotDisturb === false && Config.saved.forestWhispers === true && Config.saved.performanceMode === "auto", "Defaults before any profile");
                Profiles.activate("work");
                break;
            case 1:
                window.check(Profiles.active === "work" && !Profiles.busy && Profiles.current === "work", "Work applied and settled (" + Profiles.phase + ")");
                window.check(window.state("dnd") === "active" && Config.saved.doNotDisturb === true, "DND applied through the stack (" + window.state("dnd") + ")");
                window.check(window.state("performance") === "active" && Config.saved.performanceMode === "on" && VisualQuality.efficient, "Performance mode on and the visual-quality policy follows");
                window.check(window.state("whispers") === "active" && Config.saved.forestWhispers === false, "Whispers off");
                window.check(window.state("power") === "unavailable", "No power provider in test mode reads as unavailable (" + window.state("power") + ")");
                window.check(Overrides.holder("doNotDisturb") === "profile" && Overrides.keysHeldBy("profile").length === 3, "Three keys held by the profile (" + Overrides.keysHeldBy("profile").join() + ")");
                window.check(Profiles.activeCount === 3 && Profiles.totalCount === 3, "Counts only what could be attempted (" + Profiles.activeCount + "/" + Profiles.totalCount + ")");
                const row = CoreService.rows.find(r => r.id === "profile");
                window.check(!!row && row.persistent && row.actions[0].id === "leave", "Core pill carries a persistent profile row with a Leave action");
                // The user changes a held setting by hand.
                Config.set("forestWhispers", true);
                window.check(Overrides.entry("forestWhispers", "profile").overridden === true, "A manual change while held is recorded as the user's");
                window.shot("profiles-work");
                Profiles.deactivate();
                break;
            case 2:
                window.check(Profiles.active === "" && !Profiles.busy && Profiles.current === "", "Work restored and settled");
                window.check(Config.saved.doNotDisturb === false && Config.saved.performanceMode === "auto", "DND and performance back to what was captured");
                window.check(Config.saved.forestWhispers === true && window.state("whispers") === "restored", "The manual change was kept, not overwritten (" + Config.saved.forestWhispers + ")");
                window.check(Overrides.keysHeldBy("profile").length === 0 && !CoreService.rows.some(r => r.id === "profile"), "Nothing held and the pill row removed");
                // Nesting with Gaming Mode: Gaming holds DND on top of Night.
                Profiles.activate("night");
                break;
            case 3:
                window.check(Profiles.active === "night" && Config.saved.doNotDisturb === true && window.state("nightlight") === "unavailable" && window.state("ambient") === "active", "Night applied: DND on, ambient low, night light unavailable here");
                Gaming.activate("manual");
                break;
            case 4:
                window.check(Gaming.active && !Gaming.busy && Overrides.holder("doNotDisturb") === "gaming", "Gaming holds DND above the profile");
                window.check(Profiles.current === "gaming" && Profiles.active === "night", "Current reads gaming while Night's values are still held underneath");
                Profiles.deactivate();
                break;
            case 5:
                window.check(Profiles.active === "" && !Profiles.busy && Config.saved.doNotDisturb === true, "Night restored underneath Gaming without touching DND (" + Config.saved.doNotDisturb + ")");
                window.check(Config.saved.ambientIntensity === .45, "Ambient intensity returned to its original");
                Gaming.deactivate();
                break;
            case 6:
                window.check(!Gaming.active && Config.saved.doNotDisturb === false, "Gaming's release restores the original DND, not Night's (" + Config.saved.doNotDisturb + ")");
                // Exclusive: activating Battery while Work is on restores Work first, then applies Battery.
                Profiles.activate("work");
                break;
            case 7:
                window.check(Profiles.active === "work", "Work on");
                Profiles.activate("battery");
                break;
            case 8:
                window.check(Profiles.active === "battery" && Config.saved.idleLockSeconds === 300 && Config.saved.ambientIntensity === 0 && Config.saved.doNotDisturb === false, "Battery replaced Work: Work's DND released, Battery's idle lock and ambience applied (" + Profiles.active + ", " + Config.saved.doNotDisturb + ")");
                window.check(Profiles.queued === "", "Nothing left queued");
                // Custom: editable and persisted.
                Profiles.setCustomOp("dnd", true); Profiles.setCustomAccent("violet");
                window.check(Profiles.definition("custom").ops.dnd === true && Profiles.definition("custom").accent === "violet", "Custom definition updated");
                Profiles.deactivate();
                break;
            case 9:
                window.check(Profiles.active === "" && Config.saved.idleLockSeconds === 600 && Config.saved.ambientIntensity === .45, "Battery restored idle lock and ambience");
                window.shot("profiles-idle");
                break;
            case 10:
                console.log("PASS: Desktop Profiles apply, verify, nest with Gaming Mode, respect manual changes, stay exclusive and restore");
                Qt.quit();
            }
        }
    }
}
''')
    env = {**os.environ, 'CEDAR_TEST': '1', 'QT_QPA_PLATFORM': 'offscreen', 'QT_QPA_PLATFORMTHEME': 'basic', 'QT_QUICK_CONTROLS_STYLE': 'Basic', 'QSG_RHI_BACKEND': 'software', 'XDG_RUNTIME_DIR': str(runtime), 'XDG_CONFIG_HOME': str(p / 'config'), 'XDG_STATE_HOME': str(p / 'state'), 'CEDAR_SCREENSHOT_DIR': str(shots)}
    result = subprocess.run(['qs', '-p', str(source / 'preview.qml')], env=env, capture_output=True, text=True, timeout=90)
    output = result.stdout + result.stderr
    if result.returncode or 'PASS: Desktop Profiles' not in output or re.search(r'Failed to load configuration|ReferenceError|TypeError|Binding loop|Cannot assign|is not defined|Unable to assign|FAIL:', output):
        print(output[-8000:]); raise SystemExit(1)
    saved = json.loads((p / 'config' / 'cedar' / 'profiles.json').read_text())
    assert saved['custom']['ops']['dnd'] is True and saved['custom']['accent'] == 'violet', saved
    print('PASS: Desktop Profiles apply, verify, nest with Gaming Mode, respect manual changes, stay exclusive and restore')
