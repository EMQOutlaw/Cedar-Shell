#!/usr/bin/env python3
"""Offscreen: Kinetic Type labels transition on meaning changes and are static otherwise.

Covers: a vertical resolution and a character relay run and finish; an
unsafe relay (emoji) falls back and still finishes; Reduced Motion and a
rate-limited number update statically; semantic compression picks the
variant that fits; nothing stays allocated after a transition.
"""
from pathlib import Path
import os, re, shutil, subprocess, sys, tempfile
ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='cedar-kinetic-') as tmp:
    p = Path(tmp); source = p / 'shell'; shutil.copytree(ROOT, source, ignore=shutil.ignore_patterns('__pycache__', '.git'))
    runtime = p / 'runtime'; runtime.mkdir(mode=0o700)
    (source / 'preview.qml').write_text('''
import QtQuick
import Quickshell
import "."
import "components"
import "services"
ShellRoot {
    id: window
    property int step: 0
    function check(ok, msg) { if (!ok) { console.error("FAIL: " + msg); Qt.exit(1); } }
    FloatingWindow {
        id: win; visible: true; implicitWidth: 600; implicitHeight: 300; color: Theme.background
        Column {
            spacing: 12; x: 20; y: 20
            KineticLabel { id: resolveLabel; width: 200; height: 24; text: "BALANCED"; transitionStyle: "resolve" }
            KineticStatus { id: relayLabel; width: 200; height: 24; text: "CONNECTING" }
            KineticLabel { id: emojiLabel; width: 200; height: 24; text: "🙂 on"; transitionStyle: "relay" }
            KineticNumber { id: number; width: 200; height: 24; text: "41%" }
            KineticLabel { id: fitLabel; width: 200; height: 24; variants: ["Performance Profile", "Performance", "P"]; availableWidth: 400 }
        }
    }
    Timer {
        interval: 400; running: true; repeat: true
        onTriggered: {
            switch (window.step++) {
            case 0:
                window.check(!resolveLabel.transitioning && resolveLabel.shown === "BALANCED", "Static at rest (" + resolveLabel.shown + ")");
                window.check(fitLabel.shown === "Performance Profile", "The longest variant fits a wide label (" + fitLabel.shown + ")");
                resolveLabel.text = "GAMING";
                relayLabel.text = "CONNECTED";
                emojiLabel.text = "🙁 off";
                window.check(resolveLabel.transitioning && relayLabel.transitioning && emojiLabel.transitioning, "Changes start transitions (" + resolveLabel.transitioning + "," + relayLabel.transitioning + "," + emojiLabel.transitioning + ")");
                window.check(resolveLabel.shown === "GAMING" && relayLabel.shown === "CONNECTED", "Layout takes the new text at once");
                break;
            case 1:
                window.check(!resolveLabel.transitioning && !relayLabel.transitioning && !emojiLabel.transitioning, "Transitions finished and released (" + resolveLabel.transitioning + "," + relayLabel.transitioning + "," + emojiLabel.transitioning + ")");
                number.text = "42%";
                window.check(number.transitioning, "A first number change resolves");
                number.text = "43%";
                window.check(number.shown === "43%" && !number.transitioning, "A change within the interval is static (" + number.transitioning + ")");
                fitLabel.availableWidth = 90;
                window.check(fitLabel.shown === "Performance" || fitLabel.shown === "P", "A narrower label compresses to a shorter variant (" + fitLabel.shown + ")");
                break;
            case 2:
                Theme.reducedMotion = true;
                resolveLabel.text = "BATTERY";
                window.check(!resolveLabel.transitioning && resolveLabel.shown === "BATTERY", "Reduced Motion updates statically");
                Theme.reducedMotion = false;
                resolveLabel.text = "";
                window.check(!resolveLabel.transitioning && resolveLabel.shown === "", "Emptying a label is static");
                break;
            case 3:
                console.log("PASS: Kinetic Type resolves, relays, falls back, compresses, rate-limits and rests");
                Qt.quit();
            }
        }
    }
}
''')
    env = {**os.environ, 'CEDAR_TEST': '1', 'QT_QPA_PLATFORM': 'offscreen', 'QT_QPA_PLATFORMTHEME': 'basic', 'QT_QUICK_CONTROLS_STYLE': 'Basic', 'QSG_RHI_BACKEND': 'software', 'XDG_RUNTIME_DIR': str(runtime), 'XDG_CONFIG_HOME': str(p / 'config'), 'XDG_STATE_HOME': str(p / 'state')}
    result = subprocess.run(['qs', '-p', str(source / 'preview.qml')], env=env, capture_output=True, text=True, timeout=60)
    output = result.stdout + result.stderr
    if result.returncode or 'PASS: Kinetic' not in output or re.search(r'Failed to load configuration|ReferenceError|TypeError|Binding loop|Cannot assign|is not defined|Unable to assign|FAIL:', output):
        print(output[-6000:]); raise SystemExit(1)
    print('PASS: Kinetic Type resolves, relays, falls back, compresses, rate-limits and rests')
