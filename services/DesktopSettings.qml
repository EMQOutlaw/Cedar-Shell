pragma Singleton
import QtQuick
import Quickshell
import ".."
import "../components"
Singleton {
    id: root
    property var data: ({monitors: [], bindings: [], input: {}, unsupported: {}, owned: {bindings: []}, pending: null})
    // Draft ownership is independent of a lazy Settings page's lifetime.
    property var inputDraft: ({})
    property var inputBase: ({})
    property var inputEdits: ({})
    readonly property bool inputDirty: Object.keys(inputEdits).length > 0
    property bool inputExternalChange: false
    function loadInput() {
        inputDraft = Object.assign({},data.input); inputBase = Object.assign({},data.input);
        inputEdits = ({}); inputExternalChange = false;
    }
    function editInput(key,value) {
        inputDraft = Object.assign({},inputDraft,{[key]:value});
        const next = Object.assign({},inputEdits);
        if (value === inputBase[key]) delete next[key]; else next[key]=value;
        inputEdits=next;
    }
    onRefreshed: { if (!inputDirty) loadInput(); else inputExternalChange = JSON.stringify(data.input)!==JSON.stringify(inputBase); }
    onApplied: action => { if (["input","reset-input"].includes(action)) inputEdits=({}); }
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
