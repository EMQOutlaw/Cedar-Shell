#!/usr/bin/env python3
"""Offscreen: the Permission service stays unregistered in test mode, and the prompt renders from its state.

A real polkit request cannot be driven offscreen; this covers the surface
and the state the prompt binds to, with no secret anywhere.
"""
from pathlib import Path
import os, re, shutil, subprocess, sys, tempfile
ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='cedar-permission-') as tmp:
    p = Path(tmp); source = p / 'shell'; shutil.copytree(ROOT, source, ignore=shutil.ignore_patterns('__pycache__', '.git'))
    runtime = p / 'runtime'; runtime.mkdir(mode=0o700)
    shots = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else p / 'shots'; shots.mkdir(parents=True, exist_ok=True)
    (source / 'preview.qml').write_text('''
import QtQuick
import Quickshell
import "."
import "services"
ShellRoot {
    FloatingWindow {
        id: window
        visible: true; implicitWidth: 720; implicitHeight: 420; color: Theme.background
        function check(ok, msg) { if (!ok) { console.error("FAIL: " + msg); Qt.exit(1); } }
        property int step: 0
        Loader { id: card; anchors.fill: parent; active: false; source: Qt.resolvedUrl("tests/qml/PermissionCardHarness.qml") }
        Timer {
            interval: 500; running: true; repeat: true
            onTriggered: {
                switch (window.step++) {
                case 0:
                    window.check(!Permission.enabled && !Permission.registered && !Permission.active, "Test mode registers no agent (" + Permission.enabled + "," + Permission.registered + ")");
                    Permission.message = "Authentication is required to stop the Avahi daemon"; Permission.prompt = "Password:"; Permission.responseRequired = true; Permission.identity = "station"; Permission.failed = false;
                    card.active = true;
                    break;
                case 1:
                    card.item.grabToImage(r => r.saveToFile(Quickshell.env("CEDAR_SCREENSHOT_DIR") + "/permission-prompt.png"));
                    break;
                case 2:
                    console.log("PASS: Permission agent state and prompt card");
                    Qt.quit();
                }
            }
        }
    }
}
''')
    (source / 'tests/qml/PermissionCardHarness.qml').write_text('''
import QtQuick
import QtQuick.Layouts
import "../.."
import "../../components"
import "../../services"
Item {
    ChamferFrame {
        anchors.centerIn: parent; width: 460; height: column.implicitHeight + 48; cut: 12
        fill: Qt.alpha(Theme.surface, .98); stroke: Qt.alpha(Theme.teal, .5); line: true; lineColor: Theme.green; lineFraction: .6
        ColumnLayout {
            id: column
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 24 }
            spacing: 10
            RowLayout { Layout.fillWidth: true; SectionMark { text: "PERMISSION NEEDED" } Item { Layout.fillWidth: true } StatusPill { text: Permission.identity; tone: Theme.teal } }
            GlowText { text: Permission.message; font.family: Theme.labelFont; font.pixelSize: 18; font.weight: Font.DemiBold; color: Theme.text; Layout.fillWidth: true; wrapMode: Text.WordWrap }
            GlowText { text: "A program is asking to act as the administrator. Your password goes to the system's authentication helper and is not kept."; font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
            StationField { Layout.fillWidth: true; placeholderText: Permission.prompt; echoMode: TextInput.Password }
            RowLayout { Layout.fillWidth: true; Item { Layout.fillWidth: true } StationButton { text: "Cancel" } StationButton { text: "Authorize"; accent: Theme.green } }
        }
    }
}
''')
    env = {**os.environ, 'CEDAR_TEST': '1', 'QT_QPA_PLATFORM': 'offscreen', 'QT_QPA_PLATFORMTHEME': 'basic', 'QT_QUICK_CONTROLS_STYLE': 'Basic', 'QSG_RHI_BACKEND': 'software', 'XDG_RUNTIME_DIR': str(runtime), 'XDG_CONFIG_HOME': str(p / 'config'), 'XDG_STATE_HOME': str(p / 'state'), 'CEDAR_SCREENSHOT_DIR': str(shots)}
    result = subprocess.run(['qs', '-p', str(source / 'preview.qml')], env=env, capture_output=True, text=True, timeout=40)
    output = result.stdout + result.stderr
    if result.returncode or 'PASS: Permission' not in output or re.search(r'Failed to load configuration|ReferenceError|TypeError|Binding loop|Cannot assign|is not defined|Unable to assign|FAIL:', output):
        print(output[-5000:]); raise SystemExit(1)
    print('PASS: Permission agent state and prompt card')
