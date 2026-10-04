pragma Singleton
import QtQuick
import Quickshell
import ".."
import "../components"

Singleton {
    id: root
    property var data: ({
            roles: [],
            apps: []
        })
    property string error: ""
    property string message: ""
    readonly property bool busy: worker.running
    function refresh() {
        if (!busy && !Config.testMode)
            worker.send({
                action: "snapshot"
            });
    }
    function apply(role, id) {
        if (busy || Config.testMode || !id)
            return;
        error = "";
        message = "Applying…";
        worker.send({
            action: "apply",
            role: role,
            app: id
        });
    }
    function selected(role) {
        if (role.id === "terminal") {
            const command = Config.saved.terminal;
            return command.startsWith("gtk-launch ") ? command.slice(11).trim() : !command ? "kitty.desktop" : "";
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
            root.data = result;
            root.error = "";
            root.message = result.message || "";
            if (result.launchKey)
                Config.set(result.launchKey, result.launchCommand);
        }
        onFailed: value => {
            root.error = value;
            root.message = "";
        }
    }
}
