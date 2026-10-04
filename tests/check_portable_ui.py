#!/usr/bin/env python3
"""Load the real standalone menu/theme with isolated XDG data and no helpers.

Offscreen only: this is not a secure-lock or native provider-handoff test.
"""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='cedar portable UI 雨 ') as name:
    base = Path(name)
    source = base / 'source'
    shutil.copytree(ROOT, source, ignore=shutil.ignore_patterns('.git', '__pycache__', '*.log'))
    runtime = base / 'runtime'; runtime.mkdir(mode=0o700)
    config = base / 'config/cedar'; config.mkdir(parents=True)
    (config / 'settings.json').write_text(json.dumps({'reducedMotion': True, 'clock24': False, 'customUnknown': {'keep': True}}))
    (source / 'portable-check.qml').write_text('''
import QtQuick
import Quickshell
import "services"
ShellRoot {
    property var go: Go
    Timer {
        interval: 700; running: true
        onTriggered: {
            const fail = message => { throw new Error("FAIL: " + message); };
            if (Config.omarchyIntegration) fail("standalone selected Omarchy");
            if (Config.pamService !== "login") fail("nonportable PAM service");
            if (!Go.defaultMenuPath.endsWith("/menus/default.jsonc")) fail("external default menu");
            if (!Go.userMenuPath.endsWith("/cedar/menu.jsonc")) fail("wrong customization directory");
            if (!Go.items["apps"] || !Go.items["cedar.settings"]) fail("missing real menu destinations");
            for (const key in Go.items) {
                if (String(Go.items[key].action).includes("omarchy")) fail("distribution helper leaked into Go");
            }
            if (Config.saved.clock24 || !Config.saved.reducedMotion) fail("saved preferences lost");
            if (Config.editor[0] !== "python3" || Config.editor[2] !== "launch") fail("editor not portable");
            console.log("PASS: standalone Go, local preferences, reduced motion and PAM selection");
            Qt.quit();
        }
    }
}
''')
    env = {**os.environ, 'CEDAR_TEST': '1', 'CEDAR_ADAPTER': 'hyprland', 'CEDAR_OMARCHY_SESSION': '',
           'CEDAR_PAM_SERVICE': 'login', 'CEDAR_LOCAL_ONLY': '1', 'OMARCHY_PATH': str(base/'absent'),
           'QT_QPA_PLATFORM': 'offscreen', 'QT_QUICK_CONTROLS_STYLE': 'Basic', 'QT_QPA_PLATFORMTHEME': 'basic',
           'XDG_RUNTIME_DIR': str(runtime), 'XDG_CONFIG_HOME': str(base/'config'),
           'XDG_STATE_HOME': str(base/'state'), 'XDG_DATA_HOME': str(base/'data'), 'HOME': str(base/'home')}
    result = subprocess.run(['qs', '-p', str(source/'portable-check.qml')], env=env, capture_output=True, text=True, timeout=12)
    output = result.stdout + result.stderr
    if result.returncode or 'PASS: standalone Go' not in output or re.search(r'FAIL:|ReferenceError|TypeError|Failed to load', output):
        print(output)
        raise SystemExit(1)
    preferences = json.loads((config/'settings.json').read_text())
    assert preferences['customUnknown'] == {'keep': True}
    assert not (base/'config/omarchy').exists()
    assert not (base/'state/omarchy').exists()
    print('PASS: standalone QML Go, preferences, Reduced Motion, default apps and PAM selection; no Omarchy files created')
