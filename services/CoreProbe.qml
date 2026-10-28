import QtQuick
import Quickshell
import Quickshell.Io
import ".."

Scope {
    id: root
    property bool enabled: false
    property bool retryReady: true
    onEnabledChanged: {
        retry.stop();
        retryReady = true;
    }
    property var data: ({
            recordings: [],
            keyboard: {}
        })
    property string error: ""
    Process {
        id: probe
        // Keep this binding intact across retries so disabling the owner always
        // stops its process (including Trailwatch's temporary fallback probe).
        running: root.enabled && root.retryReady && !Config.testMode
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
                root.retryReady = false;
                retry.restart();
            }
        }
    }
    Timer {
        id: retry
        interval: 15000
        onTriggered: if (root.enabled && !Config.testMode)
            root.retryReady = true
    }
}
