import QtQuick
import Quickshell
import Quickshell.Io

// A single JSON request per process. Secrets never appear in command arguments.
//
// `busy` is set the moment send() is called and cleared when the process has
// exited (or timed out) with nothing queued. The Process's own `running`
// reads true at once but notifies later, so a binding on it is stale within
// the same turn; owners must read `busy`. A request sent while one is in
// flight is queued (latest wins) and sent after the exit, so a caller never
// has to guess whether the previous process has finished.
//
// A reply is judged only once the process has exited AND both output streams
// have closed (the order of those three events is not guaranteed). A helper
// that dies without a JSON reply is reported with the last line it wrote to
// stderr, so a traceback becomes an honest message instead of "invalid
// response". stderr is shown to the owner only; it is never logged here.
//
// send(value, tag) may carry an opaque tag. It travels with its payload
// through start, queueing (latest wins) and a timeout drop, and `tag` reads
// as the in-flight request's tag while result/failed are emitted, so an owner
// multiplexing callers can tell exactly whose reply it is.
//
// stderr is bounded like stdout: past maximumDiagnostics the helper is
// stopped and reported, never buffered without limit.
//
// The process is a child of whatever declares it: a ServiceRequest inside a
// page dies with the page. Work that must outlive the page (anything that
// writes) goes through the Requests singleton instead.
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
    property int maximumDiagnostics: 1048576
    property var tag: null
    property var queuedTag: null
    signal result(var data)
    signal failed(string message)

    property bool exitSeen: false
    property bool outSeen: false
    property bool errSeen: false
    property int exitCode: 0

    // root.arguments: inside a binding, bare `arguments` is the function's own arguments object.
    command: ["python3", Quickshell.shellPath(script)].concat(root.arguments)
    stdinEnabled: true

    function send(value, requestTag) {
        const t = requestTag === undefined ? null : requestTag;
        if (busy || running) { queued = value; queuedTag = t; busy = true; return true; }
        busy = true; begin(value, t);
        return true;
    }
    function begin(value, requestTag) {
        request = value; tag = requestTag; received = false;
        exitSeen = false; outSeen = false; errSeen = false; exitCode = 0;
        stdinEnabled = true; running = true;
    }
    function next() {
        const q = queued, qt = queuedTag; queued = null; queuedTag = null;
        if (q === null) { busy = false; return; }
        begin(q, qt);
    }
    // Last non-empty line, read from the end without splitting the whole text.
    function lastLine(text) {
        const body = String(text || "").replace(/\s+$/, "");
        const line = body.slice(body.lastIndexOf("\n") + 1).trim();
        return line.length > 200 ? line.slice(0, 200) + "\u2026" : line;
    }
    // Called after each of exit, stdout EOF and stderr EOF; acts once all three are in.
    function settle() {
        if (!exitSeen || !outSeen || !errSeen) return;
        grace.stop();
        finish();
    }
    function finish() {
        if (!received) {
            received = true;
            const out = stdoutCollector.text;
            let response = null;
            if (out.length <= maximumResponse) {
                try { response = JSON.parse(out); } catch (_) { response = null; }
            }
            if (response !== null && typeof response === "object" && !Array.isArray(response) && "ok" in response) {
                if (response.ok) root.result(response.data || ({}));
                else root.failed(response.error || "The service did not complete the request.");
            } else if (exitCode !== 0) {
                const why = lastLine(stderrCollector.text);
                root.failed("The service stopped unexpectedly (exit " + exitCode + ")" + (why ? ": " + why : "."));
            } else if (out.length > maximumResponse) {
                root.failed("The service exceeded its response limit.");
            } else {
                root.failed("The service returned an invalid response.");
            }
        }
        Qt.callLater(root.next);
    }

    onStarted: { deadline.restart(); write(JSON.stringify(request) + "\n"); request = ({}); stdinEnabled = false; }
    onExited: (code, status) => {
        deadline.stop(); request = ({});
        exitSeen = true; exitCode = code;
        // Streams normally close with the process; never wait on them forever.
        if (!outSeen || !errSeen) grace.restart();
        settle();
    }

    property Timer deadlineTimer: Timer {
        id: deadline; interval: root.timeoutMs
        onTriggered: {
            root.received = true; root.request = ({}); root.queued = null; root.queuedTag = null; root.running = false; root.busy = false;
            root.failed("The service timed out. Refresh its status before retrying the action.");
        }
    }
    property Timer graceTimer: Timer {
        id: grace; interval: 2000
        onTriggered: { root.outSeen = true; root.errSeen = true; root.settle(); }
    }
    stdout: StdioCollector {
        id: stdoutCollector
        waitForEnd: false
        onTextChanged: {
            if (!root.received && text.length > root.maximumResponse) {
                root.received = true; root.request = ({}); deadline.stop(); root.running = false;
                root.failed("The service exceeded its response limit.");
            }
        }
        onStreamFinished: { root.outSeen = true; root.settle(); }
    }
    stderr: StdioCollector {
        id: stderrCollector
        waitForEnd: false
        onTextChanged: {
            if (!root.received && text.length > root.maximumDiagnostics) {
                root.received = true; root.request = ({}); deadline.stop(); root.running = false;
                root.failed("The service wrote more diagnostic output than allowed and was stopped.");
            }
        }
        onStreamFinished: { root.errSeen = true; root.settle(); }
    }
}
