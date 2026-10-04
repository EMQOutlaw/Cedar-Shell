#!/usr/bin/env python3
"""Offscreen external-lock state mirror; no PAM, layer shell or real locking."""
import os,re,shutil,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='cedar-session-ui-') as temporary:
    base=Path(temporary);source=base/'source';shutil.copytree(ROOT,source,ignore=shutil.ignore_patterns('.git','__pycache__'))
    runtime=base/'runtime';runtime.mkdir(mode=0o700)
    status=base/'status.json'
    (source/'session-check.qml').write_text('''import QtQuick
import Quickshell
import Quickshell.Io
import "."
import "services"
import "integrations/omarchy"
ShellRoot {
    Bridge { forwarding: true }
    SessionIntegration {}
    FileView { id: writer; path: Quickshell.env("CEDAR_SESSION_STATUS"); atomicWrites: true }
    Timer {
        interval: 250; running: true; repeat: true
        property int phase: 0
        onTriggered: {
            if (!Config.externalSession) throw new Error("FAIL: external mode missing");
            if (phase === 0) {
                if (!ShellState.locked) throw new Error("FAIL: missing status must block controls");
                writer.setText(JSON.stringify({locked:false,updated:Date.now()}));
            } else if (phase === 1) {
                if (ShellState.locked) throw new Error("FAIL: fresh unlocked status not applied");
                writer.setText(JSON.stringify({locked:true,updated:Date.now()}));
            } else if (phase === 2) {
                if (!ShellState.locked) throw new Error("FAIL: locked status not applied");
                writer.setText(JSON.stringify({locked:false,updated:1}));
            } else if (phase === 3) {
                if (!ShellState.locked) throw new Error("FAIL: stale status must block controls");
                writer.setText("invalid");
            } else {
                if (!ShellState.locked) throw new Error("FAIL: invalid status must block controls");
                console.log("PASS: external lock mirror, missing/stale/invalid status fail closed");Qt.quit();
            }
            phase++;
        }
    }
}
''')
    env={**os.environ,'CEDAR_TEST':'1','CEDAR_OMARCHY_SESSION':'1','CEDAR_SESSION_STATUS':str(status),'QT_QPA_PLATFORM':'offscreen','QT_QPA_PLATFORMTHEME':'basic','QT_QUICK_CONTROLS_STYLE':'Basic','XDG_RUNTIME_DIR':str(runtime),'XDG_CONFIG_HOME':str(base/'config'),'XDG_STATE_HOME':str(base/'state')}
    result=subprocess.run(['qs','-p',str(source/'session-check.qml')],env=env,text=True,capture_output=True,timeout=12)
    output=result.stdout+result.stderr
    if result.returncode or 'PASS: external lock mirror' not in output or re.search(r'FAIL:|ReferenceError|TypeError|Failed to load configuration|Binding loop',output):
        print(output);raise SystemExit(1)
    print('PASS: external lock mirror, missing/stale/invalid status fail closed (offscreen fixtures)')
