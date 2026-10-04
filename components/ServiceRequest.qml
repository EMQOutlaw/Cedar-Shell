import QtQuick
import Quickshell
import Quickshell.Io

// A single JSON request per process. Secrets never appear in command arguments.
Process {
    id: root
    required property string script
    property var request: ({})
    property bool received: false
    signal result(var data)
    signal failed(string message)
    command: ["python3", Quickshell.shellPath(script)]
    stdinEnabled: true
    function send(value) {
        if (running) return false;
        request = value; received = false; stdinEnabled = true; running = true;
        return true;
    }
    onStarted: { write(JSON.stringify(request) + "\n"); request = ({}); stdinEnabled = false; }
    stdout: StdioCollector {
        onStreamFinished: {
            try {
                const response = JSON.parse(text);
                root.received = true;
                if (response.ok) root.result(response.data || ({}));
                else root.failed(response.error || "The service did not complete the request.");
            } catch (_) { root.failed("The service returned an invalid response."); }
        }
    }
    onExited: (code, status) => { request = ({}); if (code !== 0 && !received) failed("The service exited with code " + code + "."); }
}
