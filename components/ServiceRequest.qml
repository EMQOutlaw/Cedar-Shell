import QtQuick
import Quickshell
import Quickshell.Io

// A single JSON request per process. Secrets never appear in command arguments.
//
// `busy` is set the moment send() is called and cleared when the process has
// exited (or timed out) with nothing queued. The Process's own `running`
// reads true at once but notifies later, so a binding on it is stale within
// the same turn; owners must read `busy`. A request sent while one is in
// flight is queued and sent after the exit, so a caller never has to guess
// whether the previous process has finished.
Process {
    id: root
    required property string script
    property var arguments: []
    property var request: ({})
    property var queued: null
    property bool busy: false
    property bool received: false
    property int timeoutMs: 45000
    property int maximumResponse: 4194304
    signal result(var data)
    signal failed(string message)
    // root.arguments: inside a binding, bare `arguments` is the function's own arguments object.
    command: ["python3", Quickshell.shellPath(script)].concat(root.arguments)
    stdinEnabled: true
    function send(value) {
        if (busy || running) { queued = value; busy = true; return true; }
        busy = true; request = value; received = false; stdinEnabled = true; running = true;
        return true;
    }
    function next() {
        const q = queued; queued = null;
        if (q === null) { busy = false; return; }
        request = q; received = false; stdinEnabled = true; running = true;
    }
    onStarted: { deadline.restart(); write(JSON.stringify(request) + "\n"); request = ({}); stdinEnabled = false; }
    property Timer deadlineTimer: Timer {
        id: deadline; interval: root.timeoutMs
        onTriggered: {
            root.received = true; root.request = ({}); root.queued = null; root.running = false; root.busy = false;
            root.failed("The service timed out. Refresh its status before retrying the action.");
        }
    }
    stdout: StdioCollector {
        waitForEnd: false
        onTextChanged: {
            if (!root.received && text.length > root.maximumResponse) {
                root.received = true; root.request = ({}); deadline.stop(); root.running = false;
                root.failed("The service exceeded its response limit.");
            }
        }
        onStreamFinished: {
            if (root.received) return;
            root.received = true;
            try {
                if (text.length > root.maximumResponse) throw new Error("Response limit");
                const response = JSON.parse(text);
                if (response.ok) root.result(response.data || ({}));
                else root.failed(response.error || "The service did not complete the request.");
            } catch (_) { root.failed("The service returned an invalid response."); }
        }
    }
    onExited: (code, status) => { deadline.stop(); request = ({}); if (code !== 0 && !received) { received = true; failed("The service exited with code " + code + "."); } Qt.callLater(root.next); }
}
