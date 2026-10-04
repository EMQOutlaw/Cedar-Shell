pragma Singleton
import QtQuick
import Quickshell
import ".."
import "../components"
Singleton {
    id: root
    property var data: ({monitors: [], bindings: [], input: {}, unsupported: {}, owned: {bindings: []}, pending: null})
    property var pending: null
    property string error: ""
    property string message: ""
    readonly property bool busy: worker.running
    property string operation: "snapshot"
    signal refreshed()
    signal applied(string action)
    function refresh() { if (!busy && !Config.testMode) worker.send({action: "snapshot"}); }
    function apply(request) { if (busy || Config.testMode) return; error = ""; message = "Applying…"; operation = request.action; worker.send(request); }
    ServiceRequest {
        id: worker; script: "scripts/desktop.py"
        onResult: result => {
            root.error = "";
            if (result.monitors) { root.data = result; root.pending = result.pending; root.refreshed(); }
            else { root.pending = result.pending || null; root.message = result.message || "Applied."; root.applied(root.operation); recheck.restart(); }
        }
        onFailed: value => { root.error = value; root.message = ""; }
    }
    Timer { id: recheck; interval: 400; onTriggered: root.refresh() }
    Timer { interval: 1000; repeat: true; running: root.pending !== null; onTriggered: if (Date.now() / 1000 > root.pending.deadline + 1) root.refresh() }
}
