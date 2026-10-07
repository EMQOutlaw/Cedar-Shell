#!/usr/bin/env python3
"""Offscreen: the Gaming Mode transaction, its registry and rollback, and the visual-quality policy.

Test mode has no compositor, inhibitor or power provider, so those steps must
report "unavailable" rather than fail or pretend; the in-process steps (visual
quality, do-not-disturb) must apply, verify, count, and restore.
"""
from pathlib import Path
import json, os, re, shutil, subprocess, tempfile
ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='cedar-gaming-') as tmp:
    p = Path(tmp); source = p / 'shell'; shutil.copytree(ROOT, source, ignore=shutil.ignore_patterns('__pycache__', '.git'))
    runtime = p / 'runtime'; runtime.mkdir(mode=0o700)
    (source / 'preview.qml').write_text('''
import QtQuick
import Quickshell
import "."
import "services"
ShellRoot {
    id: window
    property int step: 0
    function check(ok, msg) { if (!ok) { console.error("FAIL: " + msg); Qt.exit(1); } }
    function state(id) { const s = Gaming.steps.find(s => s.id === id); return s ? s.state : "missing"; }
    Timer {
        interval: 600; running: true; repeat: true
        onTriggered: {
            switch (window.step++) {
            case 0:
                window.check(!Gaming.active && !Gaming.busy && VisualQuality.normal && !Theme.reducedMotion, "Starts off and normal");
                Config.set("doNotDisturb", false);
                Gaming.activate("manual");
                break;
            case 1:
                window.check(Gaming.active && !Gaming.busy, "Transaction settled (" + Gaming.phase + ", busy " + Gaming.busy + ")");
                window.check(VisualQuality.gaming && Theme.reducedMotion && !SystemStats.ambient, "Visual quality is gaming: motion reduced, ambient telemetry off");
                window.check(window.state("quiet") === "active" && window.state("dnd") === "active" && Config.saved.doNotDisturb, "Quiet and DND applied and verified (" + JSON.stringify(Gaming.steps) + ")");
                window.check(window.state("idle") === "unavailable" && window.state("power") === "unavailable" && window.state("compositor") === "unavailable" && window.state("gamemode") === "unavailable", "Steps without a provider report unavailable, not failed");
                window.check(Gaming.activeCount === 2 && Gaming.totalCount === 2 && Gaming.summary === "2 / 2 optimizations active", "Summary counts only what could be attempted (" + Gaming.summary + ")");
                window.check(Gaming.captured.dnd === false, "Previous DND captured for restore");
                const row = CoreService.rows.find(r => r.id === "gaming");
                window.check(!!row && row.persistent && row.actions.length === 1 && row.actions[0].id === "leave", "Core pill carries a persistent Gaming row with a Leave action (" + JSON.stringify(row && row.actions) + ")");
                CoreService.invoke(row, "leave");
                break;
            case 2:
                window.check(!Gaming.active && !Gaming.busy && VisualQuality.normal && !Theme.reducedMotion, "Leave restores normal quality");
                window.check(Config.saved.doNotDisturb === false, "DND restored to its captured value");
                window.check(!CoreService.rows.some(r => r.id === "gaming"), "Gaming row removed from the pill");
                Config.set("gamingDnd", false);
                Config.set("doNotDisturb", true);
                Gaming.activate("manual");
                break;
            case 3:
                window.check(Gaming.active && window.state("dnd") === "off" && Config.saved.doNotDisturb === true, "A registry entry turned off is skipped and the user's DND is untouched");
                window.check(Gaming.summary === "1 / 1 optimization active", "Singular summary (" + Gaming.summary + ")");
                ShellState.locked = true;
                break;
            case 4:
                window.check(!Gaming.active, "Locking the session leaves Gaming Mode");
                ShellState.locked = false;
                Config.set("gamingDnd", true); Config.set("doNotDisturb", false);
                console.log("PASS: Gaming Mode transaction, registry, rollback and visual quality");
                Qt.quit();
            }
        }
    }
}
''')
    env = {**os.environ, 'CEDAR_TEST': '1', 'QT_QPA_PLATFORM': 'offscreen', 'QT_QPA_PLATFORMTHEME': 'basic', 'QT_QUICK_CONTROLS_STYLE': 'Basic', 'QSG_RHI_BACKEND': 'software', 'XDG_RUNTIME_DIR': str(runtime), 'XDG_CONFIG_HOME': str(p / 'config'), 'XDG_STATE_HOME': str(p / 'state')}
    result = subprocess.run(['qs', '-p', str(source / 'preview.qml')], env=env, capture_output=True, text=True, timeout=40)
    output = result.stdout + result.stderr
    if result.returncode or 'PASS: Gaming' not in output or re.search(r'Failed to load configuration|ReferenceError|TypeError|Binding loop|Cannot assign|is not defined|Unable to assign|FAIL:', output):
        print(output[-6000:]); raise SystemExit(1)
    print('PASS: Gaming Mode transaction, registry, rollback and visual quality')
