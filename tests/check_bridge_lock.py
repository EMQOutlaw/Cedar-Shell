#!/usr/bin/env python3
"""Run the real Omarchy bridge offscreen against a CEDAR lock-state file."""
import json,os,re,shutil,subprocess,tempfile,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='cedar bridge lock ') as temp:
    base=Path(temp);runtime=base/'runtime';runtime.mkdir(mode=0o700)
    shutil.copy2(ROOT/'integrations/omarchy/Bridge.qml',base/'Bridge.qml')
    state=base/'lock-state.json'
    def write(**values):
        state.write_text(json.dumps({**dict(ready=True,locked=False,secure=False,event='ready',updated=int(time.time()*1000)),**values})+'\n')
    write()
    (base/'check.qml').write_text('''import QtQuick
import Quickshell
ShellRoot {
    function check(ok, message) { if (!ok) { console.error("FAIL: " + message); Qt.exit(1); } }
    Loader { id: bridge; source: "Bridge.qml"; onLoaded: item.barConfig = ({cedarLock: "trailwatch", cedarLockState: STATE, cedarShellPath: "/nonexistent/cedar/shell.qml"}) }
    Loader { id: plain; source: "Bridge.qml"; onLoaded: item.barConfig = ({cedarShellPath: "/nonexistent/cedar/shell.qml"}) }
    Timer {
        interval: 600; running: true; repeat: true
        property int step: 0
        onTriggered: {
            const b = bridge.item, s = JSON.parse(b.lockStatus());
            if (step === 0) {
                check(bridge.status === Loader.Ready && plain.status === Loader.Ready, "bridge loads");
                check(b.trailwatch && !plain.item.trailwatch, "lock handling is opt-in per bar configuration");
                check(s.provider === "cedar" && s.passwordPam === true && s.locked === false && s.secure === false, "fresh unlocked state: " + b.lockStatus());
                check(b.lockedText() === "false", "isLocked false");
                console.log("STEP_LOCKED");
            } else if (step === 1) {
                check(s.locked === true && s.secure === true && s.requested === true && s.sessionLocked === true, "locked state: " + b.lockStatus());
                check(b.lockedText() === "true" && b.lockRequest() === "ok", "locked answers ok without a second request");
                console.log("STEP_STALE");
            } else if (step === 2) {
                check(s.passwordPam === false && s.locked === false && s.lastEvent === "stale", "stale state is not ready: " + b.lockStatus());
                check(b.lockRequest() === "missing-pam", "stale state refuses to claim a lock");
                console.log("PASS: bridge lock status, locked and stale answers"); Qt.quit();
            }
            step++;
        }
    }
}
'''.replace('STATE', json.dumps(str(state))))
    env={**os.environ,'QT_QPA_PLATFORM':'offscreen','QT_QPA_PLATFORMTHEME':'basic','XDG_RUNTIME_DIR':str(runtime)}
    proc=subprocess.Popen(['qs','-p',str(base/'check.qml')],env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    output='';deadline=time.monotonic()+20
    while time.monotonic()<deadline and proc.poll() is None:
        line=proc.stdout.readline();output+=line
        if 'STEP_LOCKED' in line: write(locked=True,secure=True,event='secure=true')
        elif 'STEP_STALE' in line: write(locked=False,updated=int(time.time()*1000)-60000)
    if proc.poll() is None: proc.kill()
    output+=proc.stdout.read()
    if proc.returncode or 'PASS: bridge lock status' not in output or re.search(r'FAIL:|ReferenceError|TypeError|Failed to load configuration|Binding loop',output):
        print(output);raise SystemExit(1)
    print('PASS: actual Omarchy bridge answers lock IPC from CEDAR state offscreen; no native lock or desktop changes')
