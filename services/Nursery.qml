pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import ".."

// The plugin registry: companion services (CEDAR Ai first) that planted a
// descriptor in ~/.config/cedar/plugins.d/. Reads through scripts/nursery.py;
// every action (enable/disable/open) is a one-shot verb through the same
// helper, then a re-read — the page never trusts its own optimism.
Singleton {
    id: root
    property var plugins: []
    property string pluginsDir: ""
    property string error: ""
    property string message: ""
    property bool busy: false

    // Polled only while the Nursery page is actually looking.
    readonly property bool observed: !Config.testMode && !ShellState.locked
        && SettingsService.open && SettingsService.page === "nursery"
    onObservedChanged: if (observed) refresh()
    Timer { interval: 30000; running: root.observed; repeat: true; onTriggered: root.refresh() }

    function refresh() {
        if (Config.testMode || lister.running)
            return;
        root.busy = true;
        lister.running = true;
    }

    function act(verb, pluginId) {
        if (Config.testMode || ShellState.locked || actioner.running)
            return;
        actioner.verb = verb;
        actioner.pluginId = pluginId;
        root.message = "";
        actioner.running = true;
    }

    Process {
        id: lister
        command: ["python3", Quickshell.shellPath("scripts/nursery.py"), "list"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    root.plugins = data.plugins || [];
                    root.pluginsDir = data.plugins_dir || "";
                    root.error = "";
                } catch (_) {
                    root.error = "The Nursery registry returned an unreadable response.";
                }
            }
        }
        onExited: (code, status) => {
            root.busy = false;
            if (code !== 0)
                root.error = "The Nursery registry is unavailable (exit " + code + ").";
        }
    }

    Process {
        id: actioner
        property string verb: ""
        property string pluginId: ""
        command: ["python3", Quickshell.shellPath("scripts/nursery.py"), verb, pluginId]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    root.message = data.ok ? "" : (data.error || data.output || "The action failed.");
                } catch (_) {
                    root.message = "";
                }
            }
        }
        onExited: (code, status) => root.refresh()
    }

    // Test seam: harnesses feed fixture registries without a subprocess.
    function feed(registry) {
        root.plugins = (registry && registry.plugins) || [];
        root.pluginsDir = (registry && registry.plugins_dir) || "";
        root.error = "";
    }
}
