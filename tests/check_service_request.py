#!/usr/bin/env python3
"""ServiceRequest and Requests against real Quickshell processes.

Copies the production components/ServiceRequest.qml and services/Requests.qml
into a scratch tree with deterministic fixture helpers, then checks:

* latest-wins coalescing: a burst delivers the first and the last request only;
* a helper that dies without JSON is reported with its last stderr line;
* a request queued behind a crash still runs; a timeout recovers;
* stderr is bounded: a flood stops the helper before its completion marker
  (asserted in Python — FileView caches its initial load failure, so the
  QML side cannot see the marker appearing later);
* a page-owned ServiceRequest dies with its page (the documented limit);
* Requests finishes a write after its caller is destroyed, drops the dead
  caller's callback, answers a reopened caller with its own reply only, and
  binds the right callback when a send follows a timeout, and keeps callers
  apart when several send on one channel in the same event-loop turn.

Nothing here touches the desktop; helpers only write inside the scratch tree.
"""
from pathlib import Path
import os
import re
import shutil
import subprocess
import sys
import tempfile
import textwrap

ROOT = Path(__file__).resolve().parents[1]

HELPER = '''
import json, sys, time, pathlib
req = json.loads(sys.stdin.readline())
mode = req.get("mode", "plain")
time.sleep(req.get("s", 0))
if req.get("marker"):
    pathlib.Path(req["marker"]).write_text(str(req.get("tag", "")))
if mode == "big":
    print(json.dumps({"ok": True, "data": {"n": req.get("n"), "pad": "x" * 300000}}), flush=True)
elif mode == "flood":
    chunk = "e" * 65536
    for _ in range(64):            # 4 MiB of newline-free stderr, at a pace
        sys.stderr.write(chunk)
        sys.stderr.flush()
        time.sleep(0.005)
    # Proof point: reached only when the helper is NOT stopped mid-flood.
    pathlib.Path(req.get("marker", "/dev/null") + ".flood-done").write_text("done")
    print(json.dumps({"ok": True, "data": {"n": "flooded"}}))
elif mode == "crash":
    sys.stderr.write("Traceback (most recent call last):\\nFileNotFoundError: [Errno 2] No such file or directory: 'probe'\\n")
    sys.exit(1)
else:
    print(json.dumps({"ok": True, "data": {"n": req.get("n"), "tag": req.get("tag")}}))
'''

HARNESS = '''
import QtQuick
import Quickshell
import "components"
import "services"
ShellRoot {
    id: shell
    property var got: []
    property var after: []
    property var log: []
    property int failures: 0
    function check(ok, message) { if (!ok) { failures++; console.error("FAIL: " + message); } else console.log("ok: " + message); }


    ServiceRequest { id: burst; script: "scripts/helper.py"; onResult: d => shell.got.push(d.n) }
    ServiceRequest { id: crash; script: "scripts/helper.py"
        onFailed: m => shell.log.push("crash:" + m); onResult: d => shell.after.push(d.n) }
    ServiceRequest { id: slow; script: "scripts/helper.py"; timeoutMs: 500
        onFailed: m => shell.log.push("slow:" + m); onResult: d => shell.after.push("slow-" + d.n) }

    Loader { id: page; sourceComponent: Item {
        ServiceRequest { id: owned; script: "scripts/helper.py" }
        Component.onCompleted: owned.send({s: 1.2, marker: "MARK_OWNED", tag: "owned"})
    } }

    ServiceRequest { id: flood; script: "scripts/helper.py"; maximumDiagnostics: 262144
        onFailed: m => shell.log.push("flood:" + m); onResult: d => shell.log.push("flood-result") }

    Component { id: pageComp; Item { id: p; property string name
        function handle(d) { shell.log.push(p.name + "<-" + d.tag); } } }
    property var pageA: pageComp.createObject(shell, {name: "A"})
    property var pageB: null
    property var callerC: null
    property var callerD: null
    property var callerE: null

    Timer { interval: 100; running: true; onTriggered: {
        burst.send({mode: "big", n: 1});
        for (let i = 2; i <= 30; i++) burst.send({mode: "big", n: i});
        crash.send({mode: "crash"});
        crash.send({n: 7});
        slow.send({s: 3, n: 1});
        Requests.send("write", "scripts/helper.py", {s: 1.2, marker: "MARK_REQUESTS", tag: "apply"}, shell.pageA, shell.pageA.handle, null);
        // two live callers on one idle channel in the same turn: each gets its own reply or none
        shell.callerC = pageComp.createObject(shell, {name: "C"});
        shell.callerD = pageComp.createObject(shell, {name: "D"});
        shell.callerE = pageComp.createObject(shell, {name: "E"});
        Requests.send("same", "scripts/helper.py", {tag: "for-C", s: 0.3}, shell.callerC, shell.callerC.handle, null);
        Requests.send("same", "scripts/helper.py", {tag: "for-D"}, shell.callerD, shell.callerD.handle, null);
        Requests.send("same", "scripts/helper.py", {tag: "for-E"}, shell.callerE, shell.callerE.handle, null);
        flood.send({mode: "flood", marker: "MARK_FLOOD"});
    } }
    Timer { interval: 400; running: true; onTriggered: {
        page.active = false;
        shell.pageA.destroy();
        shell.pageB = pageComp.createObject(shell, {name: "B"});
        Requests.send("write", "scripts/helper.py", {tag: "status"}, shell.pageB, shell.pageB.handle, null);
    } }
    Timer { interval: 1500; running: true; onTriggered: slow.send({n: 2}) }
    Timer { interval: 2600; running: true; onTriggered:
        Requests.send("t", "scripts/helper.py", {s: 5, tag: "slow"}, shell, d => shell.log.push("T<-" + d.tag), m => shell.log.push("T!timeout"), 400) }
    Timer { interval: 3050; running: true; onTriggered:
        Requests.send("t", "scripts/helper.py", {tag: "after"}, shell, d => shell.log.push("T<-" + d.tag), m => shell.log.push("T!" + m), 400) }

    Timer { interval: 6500; running: true; onTriggered: {
        check(JSON.stringify(shell.got) === "[1,30]", "burst coalesces to first and latest: " + JSON.stringify(shell.got));
        check(shell.log.some(l => l === "crash:The service stopped unexpectedly (exit 1): FileNotFoundError: [Errno 2] No such file or directory: 'probe'"),
              "crash reports its last stderr line: " + JSON.stringify(shell.log.filter(l => l.startsWith("crash:"))));
        check(shell.after.indexOf(7) !== -1, "a request queued behind a crash still runs");
        check(shell.log.some(l => l.startsWith("slow:The service timed out")), "timeout is reported");
        check(shell.after.indexOf("slow-2") !== -1, "a request after a timeout recovers");
        check(shell.log.indexOf("B<-status") !== -1, "reopened caller receives its own reply");
        check(!shell.log.some(l => l.startsWith("A<-")), "destroyed caller's callback is dropped");
        check(shell.log.indexOf("T!timeout") !== -1 && shell.log.indexOf("T<-after") !== -1, "send after timeout binds its own callback");
        const same = shell.log.filter(l => /^[CDE]<-/.test(l));
        check(JSON.stringify(same) === JSON.stringify(["C<-for-C", "E<-for-E"]),
              "same-turn callers: in-flight answers its sender, latest queued answers its sender, replaced is unanswered: " + JSON.stringify(same));
        check(shell.log.indexOf("flood:The service wrote more diagnostic output than allowed and was stopped.") !== -1
              && shell.log.indexOf("flood-result") === -1, "stderr flood is bounded and reported");
        check(!burst.busy && !crash.busy && !slow.busy && !flood.busy && !Requests.isBusy("write") && !Requests.isBusy("t") && !Requests.isBusy("same"), "every channel settles idle");
        console.log("RESULT failures=" + shell.failures);
        Qt.quit();
    } }
}
'''


def main():
    with tempfile.TemporaryDirectory(prefix='cedar-service-request-') as tmp:
        base = Path(tmp)
        tree = base / 'shell'
        (tree / 'components').mkdir(parents=True)
        (tree / 'services').mkdir()
        (tree / 'scripts').mkdir()
        shutil.copy(ROOT / 'components/ServiceRequest.qml', tree / 'components/ServiceRequest.qml')
        shutil.copy(ROOT / 'services/Requests.qml', tree / 'services/Requests.qml')
        (tree / 'components/qmldir').write_text('ServiceRequest 1.0 ServiceRequest.qml\n')
        (tree / 'services/qmldir').write_text('singleton Requests 1.0 Requests.qml\n')
        (tree / 'scripts/helper.py').write_text(textwrap.dedent(HELPER))
        owned, requests = base / 'owned.txt', base / 'requests.txt'
        flood_marker = base / 'flood'
        (tree / 'shell.qml').write_text(HARNESS.replace('MARK_OWNED', str(owned)).replace('MARK_REQUESTS', str(requests)).replace('MARK_FLOOD', str(flood_marker)))
        runtime = base / 'runtime'
        runtime.mkdir(mode=0o700)
        env = {**os.environ, 'QT_QPA_PLATFORM': 'offscreen', 'XDG_RUNTIME_DIR': str(runtime),
               'XDG_CONFIG_HOME': str(base / 'config'), 'XDG_STATE_HOME': str(base / 'state')}
        result = subprocess.run(['qs', '-p', str(tree / 'shell.qml')], env=env,
                                capture_output=True, text=True, timeout=60)
        output = re.sub(r'\x1b\[[0-9;]*m', '', result.stdout + result.stderr)
        failures = []
        if 'RESULT failures=0' not in output:
            failures.append('harness assertions failed')
        if re.search(r'Failed to load configuration|ReferenceError|TypeError|is not defined|Cannot assign', output):
            failures.append('QML errors in output')
        if owned.exists():
            failures.append('a page-owned ServiceRequest outlived its page (documented limit changed?)')
        if (base / 'flood.flood-done').exists():
            failures.append('the flooding helper completed; the diagnostic bound did not stop it')
        if not requests.exists() or requests.read_text() != 'apply':
            failures.append('Requests did not finish the write after its caller was destroyed')
        if failures:
            print(output)
            print('FAIL: ' + '; '.join(failures))
            return 1
        print('PASS: ServiceRequest coalescing, crash diagnostics, timeout recovery, bounded stderr; '
              'Requests survives its caller and answers each caller (same-turn included) with its own reply')
        return 0


if __name__ == '__main__':
    sys.exit(main())
