pragma Singleton
import QtQuick
import ".."
import "../components"

QtObject {
    id: root
    property var status: ({})
    property var detection: ({ matches: [], activeShells: [], dependencies: [], compositor: ({}) })
    property var plan: null
    property var options: ({ bindings: false, login: false, trailwatch: false })
    property string error: ""
    property string message: ""
    readonly property bool busy: worker.busy
    function refresh() { if (!Config.testMode) worker.send({ action: "snapshot" }); }
    function preview() { if (!Config.testMode) worker.send({ action: "preview", options: options }); }
    function setOption(name, value) {
        options = Object.assign({}, options, { [name]: value });
        plan = null;
        error = "";
    }
    function assign(text) {
        try {
            const value = JSON.parse(text);
            if (value === null || Array.isArray(value) || typeof value !== "object") throw new Error("Use a JSON object of action IDs and shortcuts.");
            setOption("assignments", value);
            setOption("bindings", true);
            preview();
        } catch (failure) { error = String(failure); }
    }
    function run(operation, migration) {
        if (Config.testMode || ShellState.locked) return;
        worker.send({ action: "terminal", operation: operation, migration: migration || "", digest: plan ? plan.digest : "", options: options });
    }
    property ServiceRequest request: ServiceRequest {
        id: worker
        script: "scripts/compatibility_service.py"
        timeoutMs: 120000
        onResult: value => {
            root.error = "";
            if (value.status !== undefined) root.status = value.status;
            if (value.detection !== undefined) root.detection = value.detection;
            if (value.plan !== undefined) root.plan = value.plan;
            if (value.message !== undefined) root.message = value.message;
        }
        onFailed: text => { root.error = text; }
    }
}
