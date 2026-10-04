#!/usr/bin/env python3
"""Run the real coordinator against controlled QML handover fixtures, offline."""
import os,re,shutil,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='cedar omacale guard ') as temp:
    base=Path(temp);runtime=base/'runtime';runtime.mkdir(mode=0o700)
    guard=base/'cedar.omacale-guard';guard.mkdir()
    shutil.copy2(ROOT/'integrations/omarchy/omacale-guard/Service.qml',guard/'Service.qml')
    plugin=base/'omacale.bar';plugin.mkdir()
    (plugin/'qmldir').write_text('singleton NotifHandover 1.0 NotifHandover.qml\nsingleton OsdHandover 1.0 OsdHandover.qml\n')
    for name in ('NotifHandover','OsdHandover'):
        (plugin/(name+'.qml')).write_text('''pragma Singleton
import QtQuick
QtObject {
    id: handover
    property bool ready: true
    property bool busy: false
    property string lastAction: ""
    property Timer startCheck: Timer { interval: 20000; running: true }
    property Timer lockedRetry: Timer { interval: 60000; running: handover.lastAction === "skipped-locked" && !handover.busy }
    property Timer settle: Timer { interval: 5000; running: true }
    property QtObject watchers: QtObject { property bool active: true }
    property QtObject updates: QtObject { property bool enabled: true }
}
''')
    (base/'check.qml').write_text('''import QtQuick
import Quickshell
import "omacale.bar" as Omacale
ShellRoot {
    function check(ok, message) { if (!ok) { console.error("FAIL: " + message); Qt.exit(1); } }
    Loader { id: guard; source: "cedar.omacale-guard/Service.qml" }
    Timer {
        interval: 100; running: true; repeat: true
        property int step: 0
        onTriggered: {
            const n = Omacale.NotifHandover; const o = Omacale.OsdHandover;
            if (step === 0) {
                check(guard.status === Loader.Ready, "coordinator loads");
                check(guard.item.ready(), "idle handovers ready");
                for (const h of [n,o]) {
                    check(!h.startCheck.running && !h.lockedRetry.running && !h.settle.running, "repair timers paused");
                    check(!h.watchers.active && !h.updates.enabled, "update triggers paused");
                }
                n.busy = true; check(!guard.item.ready(), "in-flight operation blocks swap");
                n.busy = false; check(guard.item.ready(), "finished operation allows swap");
                guard.active = false;
            } else {
                for (const h of [n,o]) {
                    check(h.watchers.active && h.updates.enabled, "watchers restored");
                    check(h.startCheck.running, "delayed provider recheck restored");
                    check(!h.lockedRetry.running, "retry condition restored");
                    h.lastAction = "skipped-locked";
                    check(h.lockedRetry.running, "retry binding remains reactive");
                }
                console.log("PASS: Omacale watcher pause, busy gate and restoration"); Qt.quit();
            }
            step++;
        }
    }
}
''')
    env={**os.environ,'QT_QPA_PLATFORM':'offscreen','QT_QPA_PLATFORMTHEME':'basic','XDG_RUNTIME_DIR':str(runtime)}
    result=subprocess.run(['qs','-p',str(base/'check.qml')],env=env,text=True,capture_output=True,timeout=10)
    output=result.stdout+result.stderr
    if result.returncode or 'PASS: Omacale watcher pause' not in output or re.search(r'FAIL:|ReferenceError|TypeError|Failed to load configuration|Binding loop',output):
        print(output);raise SystemExit(1)
    print('PASS: actual coordinator with offscreen handover fixtures; no native lock or desktop changes')
