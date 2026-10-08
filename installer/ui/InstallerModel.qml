import QtQuick
import Quickshell
import Quickshell.Io

// The installer's state model. It owns one engine process
// (cedar-install --serve), sends it commands as JSON lines and renders the
// records it sends back; it never parses terminal output to guess at
// progress. In fixture mode (CEDAR_INSTALLER_FIXTURE=1) there is no process
// and the harness sets these properties directly.
Item {
    id: model
    property string stage: "welcome"      // welcome | update | update-error | update-current | scan | environment | plan | attention | interrupted | install | error | finish | restored
    property var facts: ({})
    property var plan: ({})
    property var operations: []
    property var error: ({})
    property var result: ({})
    property var previous: null
    property var restoreReport: ({})
    property var guidance: ({})           // an update stop: title, message, steps, fix, fixLabel, retry, notes
    property var update: ({})             // the update result: kind, source, version, previousVersion, current, notes
    property string password: ""
    property var log: []
    property bool busy: false
    property bool ready: false
    property bool showDetails: false
    property bool showTechnical: false
    property string version: ""
    property var options: ({ session: true, launcher: false, trailwatch: false, fonts: false, wallpapers: true, migrate: true, keybinds: false })
    readonly property bool fixture: Quickshell.env("CEDAR_INSTALLER_FIXTURE") === "1"
    readonly property bool motion: Quickshell.env("CEDAR_INSTALLER_REDUCED_MOTION") !== "1"
    readonly property string source: Quickshell.env("CEDAR_INSTALLER_SOURCE") || Quickshell.shellPath("../..")
    readonly property string python: Quickshell.env("CEDAR_INSTALLER_PYTHON") || "python3"
    readonly property string startWith: Quickshell.env("CEDAR_INSTALLER_START") || ""
    readonly property bool updating: Quickshell.env("CEDAR_INSTALLER_UPDATE") === "1"
    readonly property var environment: facts.environment || ({})
    readonly property int doneCount: operations.filter(o => ["complete", "warning", "skipped"].includes(o.state)).length
    readonly property real progress: operations.length ? doneCount / operations.length : 0
    readonly property var current: operations.find(o => o.state === "running") || null
    readonly property string sessionState: result.sessionState || ""
    readonly property bool cedarRunning: sessionState === "kept" || sessionState === "trial"
    signal stageEntered(string name)
    onStageChanged: stageEntered(stage)

    Process {
        id: engine
        running: !model.fixture
        command: [model.python, model.source + "/installer/cedar_install.py", "--serve"]
        stdinEnabled: true
        stdout: SplitParser { onRead: line => model.receive(line) }
        stderr: SplitParser { onRead: line => model.append("engine", line) }
        onExited: (code, status) => {
            if (model.stage === "update") { model.guidance = { title: "The update engine stopped", message: "The installer engine stopped unexpectedly (exit " + code + "). Nothing on your desktop was changed.", steps: ["Press Try again.", "If it keeps stopping, run the update from a terminal and keep its output: \"$HOME/.local/bin/cedar\" installer --update --no-gui"], fix: "", retry: true, notes: [] }; model.stage = "update-error"; model.busy = false; return; }
            if (model.stage === "install" || model.stage === "scan") { model.error = { title: "Installer", message: "The installer engine stopped unexpectedly (exit " + code + ").", changedBefore: [], rolledBack: false, resumable: true, log: "", preserved: "" }; model.stage = "error"; }
        }
    }
    // Commands sent before the engine says ready are queued, not lost.
    property var queued: []
    function send(request) {
        if (fixture) return;
        if (!ready) { queued = queued.concat([request]); return; }
        engine.write(JSON.stringify(request) + "\n");
    }
    function receive(line) {
        let message;
        try { message = JSON.parse(line); } catch (_) { append("engine", line); return; }
        const data = message.data || {};
        switch (message.event) {
        case "ready":
            ready = true; version = data.version || "";
            for (const request of queued) engine.write(JSON.stringify(request) + "\n");
            queued = [];
            break;
        case "facts":
            facts = data; previous = data.previousInstall || null;
            send({ cmd: "plan", options: options });
            break;
        case "plan":
            plan = data; options = data.options || options; busy = false;
            // After an update the environment is the one CEDAR already runs in: go straight to the plan.
            if (stage === "scan") stage = previous ? "interrupted" : data.blocked ? "attention" : updating ? "plan" : "environment";
            else if (stage === "attention" && !data.blocked) stage = "plan";
            break;
        case "operations": operations = data; break;
        case "operation": {
            const next = operations.slice(); const at = next.findIndex(o => o.id === data.id);
            if (at >= 0) next[at] = data; else next.push(data);
            operations = next; break; }
        case "log": append(data.operation, data.line); break;
        case "password": password = data.text; break;
        case "backup": break;
        case "error": error = data; busy = false; stage = "error"; break;
        case "done": result = data; busy = false; stage = "finish"; break;
        case "restored": restoreReport = data; busy = false; stage = "restored"; break;
        case "uninstalled": restoreReport = data; busy = false; stage = "restored"; break;
        case "update-error": guidance = data; busy = false; stage = "update-error"; break;
        case "updated":
            update = data; busy = false;
            if (data.current) stage = "update-current"; else proceedUpdate();
            break;
        case "handoff": Qt.quit(); break;
        }
    }
    function append(operation, line) {
        const next = log.length >= 400 ? log.slice(log.length - 399) : log.slice();
        next.push({ operation: operation || "", line: String(line) });
        log = next;
    }

    // ---------------------------------------------------------------- actions
    function begin() { stage = "scan"; busy = true; send({ cmd: "scan" }); }
    function rescan() { busy = true; stage = "scan"; send({ cmd: "scan" }); }
    function toPlan() { stage = "plan"; }
    function toEnvironment() { stage = "environment"; }
    function setOption(key, value) {
        const next = Object.assign({}, options); next[key] = value; options = next;
        busy = true; send({ cmd: "plan", options: next });
    }
    function install() {
        if (plan.blocked) { stage = "attention"; return; }
        stage = "install"; busy = true; password = ""; log = [];
        send({ cmd: "install", options: options, digest: plan.digest });
    }
    function resume() { stage = "install"; busy = true; password = ""; send({ cmd: "resume" }); }
    function startOver() { stage = "install"; busy = true; password = ""; send({ cmd: "start-over" }); }
    function retry() { stage = "install"; busy = true; password = ""; send({ cmd: "retry" }); }
    function restore() { busy = true; send({ cmd: "restore" }); }
    function startCedar() { stage = "install"; busy = true; send({ cmd: "session" }); }
    function quit() { send({ cmd: "quit" }); Qt.quit(); }
    // The update stage: the engine fetches the newest CEDAR and reports each step; a stop
    // arrives as guidance. On success the window closes and the process that owns it starts
    // the updated installer, which continues here as "updated".
    function startUpdate() { stage = "update"; busy = true; operations = []; log = []; guidance = ({}); send({ cmd: "update" }); }
    function fixUpdate(name) { stage = "update"; busy = true; operations = []; send({ cmd: "update-fix", fix: name }); }
    function proceedUpdate() { busy = true; send({ cmd: "update-proceed" }); }
    function cancelUpdate() { send({ cmd: "update-cancel" }); quit(); }

    Component.onCompleted: {
        if (startWith === "update") startUpdate();
        else if (startWith === "resume" || startWith === "start-over" || startWith === "updated") begin();
    }
}
