pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import ".."
import "../components"

Singleton {
    id: root
    property var data: ({
            roles: [],
            apps: []
        })
    property string error: ""
    property string launchError: ""
    property bool launching: false
    property string message: ""
    readonly property bool busy: worker.running
    readonly property bool catalogVisible: !ShellState.locked && (ShellState.panel === "menu" || (ShellState.panel === "settings" && ["apps","setup"].includes(ShellState.settingsSection)))
    property string generation: ""
    property int sequence: 0
    property int retryDelay: 1000
    function requestCatalog(action) {
        if (catalog.running) catalog.write(JSON.stringify(action) + "\n");
    }
    function refresh() {
        requestCatalog({action: "refresh"});
    }
    onCatalogVisibleChanged: requestCatalog({action: "visible", value: catalogVisible})
    Process {
        id: catalog
        command: ["python3", Quickshell.shellPath("scripts/default_apps.py"), "--watch"]
        stdinEnabled: true
        running: !Config.testMode
        onStarted: { root.generation = ""; root.sequence = 0; root.requestCatalog({action:"visible", value:root.catalogVisible}); }
        stdout: SplitParser {
            onRead: line => {
                if (line.length > 4*1024*1024) { catalog.running = false; root.error = "Application catalog exceeds the response limit."; return; }
                try {
                    const event = JSON.parse(line);
                    if (event.schema !== 1 || event.kind !== "snapshot" || !Array.isArray(event.data?.apps)) return;
                    if (root.generation && event.generation !== root.generation) return;
                    if (event.sequence <= root.sequence) return;
                    root.generation = event.generation; root.sequence = event.sequence;
                    root.data = event.data; root.error = ""; root.retryDelay = 1000;
                } catch (_) { root.error = "Application catalog returned an invalid response."; }
            }
        }
        onExited: { if (!Config.testMode) { root.error = "Application catalog unavailable; retrying locally."; retry.restart(); } }
    }
    Timer { id: retry; interval: root.retryDelay; onTriggered: { root.retryDelay = Math.min(60000, root.retryDelay*2); catalog.running = true; } }
    function apply(role, id) {
        if (busy || Config.testMode || ShellState.locked || !id)
            return;
        const current = data.roles.find(value => value.id === role);
        if (current && !current.mixed && selected(current) === id) {
            message = current.label + " is already selected.";
            return;
        }
        error = "";
        message = "Applying…";
        worker.send({
            action: "apply",
            role: role,
            app: id
        });
    }
    function launch(id) {
        if (busy || Config.testMode || ShellState.locked) return;
        error=""; launchError=""; launching=true;
        worker.send({action:"launch",id:id});
    }
    function selected(role) {
        if (role.id === "terminal") {
            const target = Config.saved.applicationTargets.terminal;
            if (target?.kind === "desktop-entry") return target.id;
            const command = Config.saved.terminal;
            return command.startsWith("gtk-launch ") ? command.slice(11).trim() : "";
        }
        return role.current;
    }
    function choices(role, all, filter) {
        const current = selected(role), query = filter.toLowerCase();
        return [
            {
                id: "",
                label: current ? "Select an application…" : "Not selected"
            }
        ].concat(data.apps.filter(a => a.id === current || ((all || role.recommended.includes(a.id)) && (!query || (a.label + " " + a.id).toLowerCase().includes(query)))));
    }
    ServiceRequest {
        id: worker
        script: "scripts/default_apps.py"
        onResult: result => {
            if (result.launched) { root.launching=false; return; }
            if (!root.generation) root.data = result;
            root.error = "";
            root.message = result.message || "";
            if (result.launchKey && result.status !== "unchanged")
                Config.set("applicationTargets", Object.assign({}, Config.saved.applicationTargets, {[result.launchKey]:result.launchTarget}));
            root.refresh();
        }
        onFailed: value => {
            root.error = value;
            if(root.launching) {root.launching=false;root.launchError=value;}
            root.message = "";
        }
    }
}
