#!/usr/bin/env python3
"""Offscreen: the Gaming Mode preparation card renders from Gaming's state.

The card binds to Gaming.steps, hudMode and hudSettled; test mode has no
providers, so the states are set directly here: preparing, ready with one
optional failure, preparing for a detected game, and the restore. Each is
captured to CEDAR_SCREENSHOT_DIR when a directory is given.
"""
from pathlib import Path
import os, re, shutil, subprocess, sys, tempfile
ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='cedar-gaming-hud-') as tmp:
    p = Path(tmp); source = p / 'shell'; shutil.copytree(ROOT, source, ignore=shutil.ignore_patterns('__pycache__', '.git'))
    runtime = p / 'runtime'; runtime.mkdir(mode=0o700)
    shots = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else p / 'shots'; shots.mkdir(parents=True, exist_ok=True)
    (source / 'preview.qml').write_text('''
import QtQuick
import Quickshell
import "."
import "services"
import "modules"
ShellRoot {
    FloatingWindow {
        id: window
        visible: true; implicitWidth: 520; implicitHeight: 420; color: Theme.background
        function check(ok, msg) { if (!ok) { console.error("FAIL: " + msg); Qt.exit(1); } }
        function shot(name) { card.grabToImage(r => r.saveToFile(Quickshell.env("CEDAR_SCREENSHOT_DIR") + "/" + name + ".png")); }
        function row(id, hud, state, detail) { return { id: id, label: id, hud: hud, restored: id === "idle" ? "Idle policy restored" : hud + " restored", state: state, detail: detail || "" }; }
        property int step: 0
        GamingHudCard { id: card; anchors.centerIn: parent; width: 400 }
        Timer {
            interval: 450; running: true; repeat: true
            onTriggered: {
                switch (window.step++) {
                case 0:
                    Gaming.hudForTests = true; Gaming.trigger = "manual"; Gaming.hudMode = "enter"; Gaming.hudShown = true; Gaming.busy = true;
                    Gaming.steps = [window.row("quiet", "CEDAR effects", "active"), window.row("dnd", "Notifications", "active"), window.row("idle", "Sleep inhibited", "applying"),
                                    window.row("power", "Performance profile", "pending"), window.row("compositor", "Compositor effects", "pending"), window.row("gamemode", "GameMode", "unavailable", "GameMode is not installed")];
                    break;
                case 1:
                    window.check(card.heading === "Preparing system…" && card.footer === "2 / 5 ready", "Preparing heading and count (" + card.heading + " / " + card.footer + ")");
                    window.check(card.rows.length === 6 && card.aside(card.rows[5]) === "Not installed" && card.glyph("applying") === "◌", "Unavailable GameMode shown quietly as Not installed");
                    window.shot("gaming-hud-preparing");
                    break;
                case 2:
                    Gaming.steps = [window.row("quiet", "CEDAR effects", "active"), window.row("dnd", "Notifications", "active"), window.row("idle", "Sleep inhibited", "active"),
                                    window.row("power", "Performance profile", "failed", "Profile did not change"), window.row("compositor", "Compositor effects", "active"), window.row("gamemode", "GameMode", "off", "Turned off in Settings")];
                    Gaming.busy = false;
                    break;
                case 3:
                    window.check(Gaming.hudSettled && card.heading === "Gaming Mode Ready" && card.footer === "4 / 5 optimizations", "Partial success: ready heading, amber count (" + card.heading + " / " + card.footer + ")");
                    window.check(card.rows.length === 5 && card.aside(card.rows[3]) === "Could not apply" && card.accent === Theme.warning, "A row turned off is omitted; the failed row says Could not apply in amber");
                    window.shot("gaming-hud-ready");
                    break;
                case 4:
                    Gaming.steps = [window.row("quiet", "CEDAR effects", "active"), window.row("dnd", "Notifications", "active"), window.row("idle", "Sleep inhibited", "active"),
                                    window.row("power", "Performance profile", "active"), window.row("compositor", "Compositor effects", "active"), window.row("gamemode", "GameMode", "active", "1 game registered")];
                    Gaming.busy = true; Gaming.trigger = "gamemode"; Gaming.gameNames = ["Celeste"];
                    break;
                case 5:
                    window.check(card.heading === "Preparing for" && card.forGame && Gaming.gameName === "Celeste", "A detected game is named from the watcher (" + card.heading + ")");
                    window.shot("gaming-hud-game");
                    break;
                case 6:
                    Gaming.gameNames = [];
                    window.check(Gaming.gameName === "", "No name falls back to the generic line");
                    Gaming.busy = false;
                    break;
                case 7:
                    window.check(card.heading === "Gaming Mode Ready" && card.footer === "Gaming Mode Active" && card.accent === Theme.success, "Full success is green and reads Gaming Mode Active (" + card.footer + ")");
                    Gaming.trigger = "manual"; Gaming.hudMode = "leave"; Gaming.busy = true;
                    Gaming.steps = [window.row("quiet", "CEDAR effects", "restored"), window.row("dnd", "Notifications", "restored"), window.row("idle", "Sleep inhibited", "applying"), window.row("power", "Performance profile", "pending"), window.row("compositor", "Compositor effects", "pending")];
                    break;
                case 8:
                    window.check(card.heading === "Restoring system…" && card.footer === "2 / 5 restored" && card.label(card.rows[0]) === "CEDAR effects restored", "Restore rows read as restored (" + card.footer + ")");
                    window.shot("gaming-hud-restoring");
                    Gaming.steps = Gaming.steps.map(s => Object.assign({}, s, { state: "restored" })); Gaming.busy = false;
                    break;
                case 9:
                    window.check(card.heading === "Gaming Mode Ended" && card.footer === "System restored", "Ended heading and System restored (" + card.footer + ")");
                    window.shot("gaming-hud-ended");
                    break;
                case 10:
                    Gaming.hudClosing = true;
                    break;
                case 11:
                    window.check(card.opacity < 0.01 && Math.abs(card.scale - 0.98) < 0.001, "Closing fades out and settles at .98 scale (" + card.opacity + "," + card.scale + ")");
                    console.log("PASS: Gaming Mode preparation card");
                    Qt.quit();
                }
            }
        }
    }
}
''')
    env = {**os.environ, 'CEDAR_TEST': '1', 'QT_QPA_PLATFORM': 'offscreen', 'QT_QPA_PLATFORMTHEME': 'basic', 'QT_QUICK_CONTROLS_STYLE': 'Basic', 'QSG_RHI_BACKEND': 'software', 'XDG_RUNTIME_DIR': str(runtime), 'XDG_CONFIG_HOME': str(p / 'config'), 'XDG_STATE_HOME': str(p / 'state'), 'CEDAR_SCREENSHOT_DIR': str(shots)}
    result = subprocess.run(['qs', '-p', str(source / 'preview.qml')], env=env, capture_output=True, text=True, timeout=40)
    output = result.stdout + result.stderr
    if result.returncode or 'PASS: Gaming Mode preparation card' not in output or re.search(r'Failed to load configuration|ReferenceError|TypeError|Binding loop|Cannot assign|is not defined|Unable to assign|FAIL:', output):
        print(output[-6000:]); raise SystemExit(1)
    print('PASS: Gaming Mode preparation card (' + ', '.join(sorted(f.name for f in shots.glob('gaming-hud-*.png'))) + ')')
