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
    onRefreshed: {
        if (!inputDirty) loadInput(); else inputExternalChange = JSON.stringify(data.input)!==JSON.stringify(inputBase);
        if (!windowsDirty) loadWindows(); else windowsExternalChange = JSON.stringify(data.windows || ({}))!==JSON.stringify(windowsBase);
    }
    onApplied: action => {
        if (["input","reset-input"].includes(action)) inputEdits=({});
        if (["apply-windows","reset-windows"].includes(action)) windowsEdits=({});
    }
    // Window-manager draft (Settings › Windows), same ownership as input.
    property var windowsDraft: ({})
    property var windowsBase: ({})
    property var windowsEdits: ({})
    readonly property bool windowsDirty: Object.keys(windowsEdits).length > 0
    property bool windowsExternalChange: false
    function loadWindows() {
        windowsDraft = Object.assign({},data.windows || ({})); windowsBase = Object.assign({},data.windows || ({}));
        windowsEdits = ({}); windowsExternalChange = false;
    }
    function editWindow(key,value) {
        windowsDraft = Object.assign({},windowsDraft,{[key]:value});
        const next = Object.assign({},windowsEdits);
        if (value === windowsBase[key]) delete next[key]; else next[key]=value;
        windowsEdits=next;
    }
    property var pending: null
    property string error: ""
    property string message: ""
    readonly property bool busy: worker.busy
    // Stays true from an Apply until the follow-up snapshot has refreshed the
    // baseline; editing with a stale baseline would be silently overwritten.
    property bool windowsReconciling: false
    readonly property bool windowsLocked: busy || windowsReconciling
    // True while the in-flight worker request is an apply (not a read), so a
    // failed follow-up snapshot does NOT unlock editing against a stale baseline.
    property bool inFlightWasApply: false
    // Failed reads retry with a bound; on exhaustion the lock stays and the
    // sticky bar offers an explicit retry.
    property int readRetries: 0
    function retryRead() { if (readRetries < 4) { readRetries++; recheck.restart(); } }
    property string operation: "snapshot"
    signal refreshed()
    signal applied(string action)
    function refresh() { if (!busy && !Config.testMode) { inFlightWasApply = false; worker.send({action: "snapshot"}); } }
    function apply(request) {
        if (busy || Config.testMode) return;
        error = ""; message = "Applying…"; operation = request.action;
        if (["apply-windows","reset-windows"].includes(request.action)) windowsReconciling = true;
        inFlightWasApply = true;
        worker.send(request);
    }
    ServiceRequest {
        id: worker; script: "scripts/desktop.py"
        onResult: result => {
            root.error = "";
            if (result.monitors) { root.data = result; root.pending = result.pending; root.refreshed(); root.windowsReconciling = false; root.readRetries = 0; }
            else { root.pending = result.pending || null; root.message = result.message || "Applied."; root.applied(root.operation); recheck.restart(); }
        }
        onFailed: value => {
            root.error = value; root.message = "";
            if (root.inFlightWasApply) {
                // Only the windows write that owns the reconciliation may
                // release it by failing; an unrelated failed op keeps the lock.
                if (["apply-windows","reset-windows"].includes(root.operation)) root.windowsReconciling = false;
                else if (root.windowsReconciling) retryRead();
            } else retryRead();
        }
    }
    Timer { id: recheck; interval: 400; onTriggered: root.refresh() }
    // Expired display trials poll for clearance, bounded like retryRead() so a
    // permanently failing backend cannot spin reads forever.
    Timer { interval: 1000; repeat: true; running: root.pending !== null; onTriggered: if (Date.now() / 1000 > root.pending.deadline + 1 && root.readRetries < 4) { root.readRetries++; root.refresh() } }
}
