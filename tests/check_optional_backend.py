#!/usr/bin/env python3
"""Actual QML Loader failure isolation, with a deliberately missing import.

Uses an isolated copy, test mode and offscreen Qt; no Bluetooth or auth action.
"""
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='cedar optional backend ') as temporary:
    base = Path(temporary)
    source = base/'source'
    shutil.copytree(ROOT, source, ignore=shutil.ignore_patterns('.git', '__pycache__'))
    runtime = base/'runtime'; runtime.mkdir(mode=0o700)
    backend = source/'services/optional/BluetoothBackend.qml'
    backend.write_text('import QtQml\nimport Cedar.DeliberatelyUnavailable\nQtObject {}\n')
    service = source/'services/BluetoothService.qml'
    service.write_text(service.read_text().replace('active:!Config.testMode', 'active:true'))
    (source/'optional-check.qml').write_text('''
import QtQuick
import Quickshell
import "services"
ShellRoot {
    property var bluetooth: BluetoothService
    Timer { interval: 500; running: true; onTriggered: {
        if (BluetoothService.available || BluetoothService.adapter !== null || BluetoothService.devices.length || !BluetoothService.error.includes("unavailable"))
            throw new Error("FAIL: missing backend did not degrade safely");
        console.log("PASS: missing optional import leaves shell alive and Bluetooth unavailable");
        Qt.quit();
    } }
}
''')
    env = {**os.environ, 'CEDAR_TEST':'1', 'CEDAR_LOCAL_ONLY':'1', 'QT_QPA_PLATFORM':'offscreen',
           'QT_QPA_PLATFORMTHEME':'basic', 'QT_QUICK_CONTROLS_STYLE':'Basic',
           'XDG_RUNTIME_DIR':str(runtime), 'XDG_CONFIG_HOME':str(base/'config'), 'XDG_STATE_HOME':str(base/'state')}
    result = subprocess.run(['qs','-p',str(source/'optional-check.qml')], env=env, capture_output=True, text=True, timeout=10)
    output = result.stdout+result.stderr
    if result.returncode or 'PASS: missing optional import' not in output or re.search(r'FAIL:|ReferenceError|TypeError|Failed to load configuration',output):
        print(output); raise SystemExit(1)
    print('PASS: actual offscreen QML optional-import failure isolation; native Bluetooth not tested')
