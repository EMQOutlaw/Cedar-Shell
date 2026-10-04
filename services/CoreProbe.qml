import QtQuick
import Quickshell
import Quickshell.Io
import ".."

Scope {
    id: root
    property bool enabled: false
    property var data: ({
            recordings: [],
            keyboard: {}
        })
    property string error: ""
    Process {
        id: probe
        running: root.enabled && !Config.testMode
        command: ["python3", Quickshell.shellPath("scripts/core_probe.py")]
        stdout: SplitParser {
            onRead: line => {
                try {
                    root.data = JSON.parse(line);
                    root.error = "";
                } catch (_) {
                    root.error = "Core activity monitor returned invalid data.";
                }
            }
        }
        onExited: (code, status) => {
            if (root.enabled && !Config.testMode) {
                root.error = "Recording and keyboard monitoring is unavailable (exit " + code + ").";
                retry.restart();
            }
        }
    }
    Timer {
        id: retry
        interval: 15000
        onTriggered: if (root.enabled && !Config.testMode)
            probe.running = true
    }
}
