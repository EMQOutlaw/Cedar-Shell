pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import ".."
import "../components"

// Dictation: Voxtype's push-to-talk voice typing (voxtype.io) as a CEDAR
// instrument. Voxtype's own daemon owns the microphone, the model and the
// typing; CEDAR only tells it to start, stop or cancel, reads the state it
// writes to $XDG_RUNTIME_DIR/voxtype/state, and shows that state on the bar and
// in the Core pill. Settings › Dictation changes Voxtype's everyday settings
// through `voxtype config set` (scripts/dictation.py), never by editing its
// file. Nothing here reads audio or transcripts.
//
// Reads are event-driven: the state file is watched; `voxtype status` runs once
// at start, after each command and when Settings asks. While Voxtype is
// listening or transcribing a slow one-shot chain re-reads the file in case the
// daemon replaced it under the watcher; it stops the moment the state is idle.
// Locking cancels a recording and refuses new ones, so nothing is ever typed
// into the lock screen.
Singleton {
    id: root
    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || ""
    readonly property string statePath: runtimeDir ? runtimeDir + "/voxtype/state" : ""
    // voxtype is on PATH (checked once at start; refresh() checks again).
    property bool installed: false
    property bool checked: false
    // What the daemon last reported: idle | recording | transcribing; "" until read.
    property string state: ""
    property bool daemon: false
    property string model: ""
    property string device: ""
    property string backend: ""
    property string error: ""
    property bool wasActive: false
    onDaemonChanged: if (!daemon) state = ""
    readonly property bool recording: state === "recording"
    readonly property bool transcribing: state === "transcribing"
    readonly property bool active: recording || transcribing
    readonly property bool available: installed && daemon && !ShellState.locked
    readonly property string label: !installed ? "Not installed" : !daemon ? "Stopped" : recording ? "Listening" : transcribing ? "Transcribing" : "Ready"
    readonly property string refusal: ShellState.locked ? "error: the session is locked" : !installed ? "error: voxtype is not installed" : !daemon ? "error: the voxtype daemon is not running" : ""

    // ------------------------------------------------------ Voxtype's settings
    // Flat dotted keys → values, as `voxtype config get --json` reports them for
    // the keys scripts/dictation.py exposes; empty until Settings asks.
    property var config: ({})
    property var models: []
    property var devices: []
    property string version: ""
    property bool configRead: false
    property string message: ""
    property string configError: ""
    property int generation: 0
    readonly property bool applying: worker.busy
    readonly property bool downloading: downloader.busy
    property string downloadingModel: ""
    readonly property var installedModels: models.filter(m => m.installed)
    readonly property var downloadableModels: models.filter(m => !m.installed && m.downloadable)
    function setting(key, fallback) {
        const value = config ? config[key] : undefined;
        return value === undefined || value === null ? fallback : value;
    }
    function readConfig() {
        if (!installed) return;
        configError = "";
        worker.send({ action: "read" });
    }
    function set(key, value) {
        if (ShellState.locked || !installed) return;
        message = "Applying…"; configError = "";
        worker.send({ action: "set", key: key, value: value });
    }
    function unset(key) {
        if (ShellState.locked || !installed) return;
        message = "Applying…"; configError = "";
        worker.send({ action: "unset", key: key });
    }
    function download(model) {
        if (ShellState.locked || !installed || downloader.busy) return;
        downloadingModel = model; message = "Downloading " + model + "…"; configError = "";
        downloader.send({ action: "download", model: model });
    }
    function restartDaemon() {
        if (ShellState.locked || !installed) return;
        message = "Restarting Voxtype…"; configError = "";
        worker.send({ action: "restart" });
    }
    function applySnapshot(data) {
        if (data.config !== undefined) { config = data.config; models = data.models || []; devices = data.devices || []; configRead = true; }
        if (data.version !== undefined) version = String(data.version || "");
        if (data.daemon !== undefined) daemon = !!data.daemon;
        if (data.installed !== undefined) installed = !!data.installed;
        message = String(data.message || "");
        generation += 1;
        refresh();
    }
    ServiceRequest {
        id: worker
        script: "scripts/dictation.py"
        timeoutMs: 60000
        onResult: data => root.applySnapshot(data)
        onFailed: text => { root.configError = text; root.message = ""; }
    }
    // Model downloads take minutes; their own request keeps the settings responsive.
    ServiceRequest {
        id: downloader
        script: "scripts/dictation.py"
        timeoutMs: 1800000
        onResult: data => { root.downloadingModel = ""; root.applySnapshot(data); }
        onFailed: text => { root.downloadingModel = ""; root.configError = text; root.message = ""; }
    }

    // ------------------------------------------------------------- the daemon
    function refresh() {
        if (!statePath) { error = "XDG_RUNTIME_DIR is not set"; return; }
        probe.running = true;
    }
    function readState() {
        // Re-pointing the view re-arms the watcher after the daemon replaced the file.
        stateFile.path = "";
        stateFile.path = statePath;
        stateFile.reload();
    }
    function record(verb) {
        if (refusal) return false;
        if (recorder.running) return false;
        recorder.command = ["voxtype", "record", verb];
        recorder.running = true;
        return true;
    }
    function start() { return record("start"); }
    function stop() { return record("stop"); }
    function toggle() { return record("toggle"); }
    function cancel() { return record("cancel"); }
    function openSettings() {
        if (ShellState.locked || Config.stage < 3) return;
        ShellState.settingsPage = "dictation";
        if (ShellState.panel === "settings") ShellState.close();
        ShellState.open("settings");
    }
    // Voxtype's own configuration TUI, in the user's terminal.
    function configure() {
        if (ShellState.locked || !installed) return;
        Quickshell.execDetached(["python3", Quickshell.shellPath("scripts/desktop_runtime.py"), "launch", "terminal", "voxtype", "configure"]);
    }
    function status() {
        return { installed: installed, daemon: daemon, state: state || "unknown", label: label, model: model, device: device, backend: backend, locked: ShellState.locked };
    }
    function applyState(text) {
        const next = String(text || "").trim();
        if (["idle", "recording", "transcribing"].includes(next)) { state = next; daemon = true; }
        else { daemon = false; state = ""; }
    }
    function cancelForLock() {
        // A start may still be in flight when the lock arrives. Use a separate
        // process, then cancel again after that command exits if still locked.
        if (ShellState.locked && installed && (active || recorder.running) && !lockCancel.running)
            lockCancel.running = true;
    }
    function publishRow() {
        if (!Config.saved.coreDictation || Config.stage < 3) { if (wasActive) CoreService.remove("dictation", false); wasActive = false; return; }
        if (active) {
            CoreService.publish({
                id: "dictation",
                type: "recording",
                priority: "high",
                title: "Dictation",
                subtitle: recording ? "Listening · speak, then stop to type it" : "Transcribing…",
                persistent: true,
                announce: !wasActive,
                data: { source: "voxtype" },
                actions: recording ? [{ id: "dictation-stop", label: "Stop and type" }, { id: "dictation-cancel", label: "Cancel" }] : [{ id: "dictation-cancel", label: "Cancel" }]
            });
            wasActive = true;
        } else if (wasActive) {
            CoreService.remove("dictation", false);
            wasActive = false;
        }
    }
    onActiveChanged: { publishRow(); cancelForLock(); }
    onRecordingChanged: if (active) publishRow()
    Connections { target: Config.saved; function onCoreDictationChanged() { root.publishRow(); } }
    Connections {
        target: ShellState
        function onLockedChanged() { root.cancelForLock(); }
    }

    // Is voxtype on PATH? exit 0 means yes; nothing else is read from it.
    Process {
        id: probe
        command: ["sh", "-c", "command -v voxtype >/dev/null 2>&1"]
        onExited: function(code) {
            root.installed = code === 0;
            root.checked = true;
            if (root.installed) { root.readState(); info.running = true; }
            else { root.daemon = false; root.state = ""; root.configRead = false; root.config = ({}); root.models = []; root.devices = []; }
        }
    }
    // The daemon's own summary: state plus model, device and backend.
    Process {
        id: info
        command: ["voxtype", "status", "--format", "json", "--extended"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    root.model = String(data.model || "");
                    root.device = String(data.device || "");
                    root.backend = String(data.backend || "");
                    const reported = String(data.alt || data.class || "");
                    if (["idle", "recording", "transcribing"].includes(reported)) { root.state = reported; root.daemon = true; }
                    else { root.daemon = false; root.state = ""; }
                    root.error = "";
                } catch (e) {
                    root.daemon = false; root.state = "";
                }
            }
        }
        onExited: function(code) { if (code !== 0) { root.daemon = false; root.state = ""; } }
    }
    Process {
        id: recorder
        onExited: function(code) {
            if (code !== 0) root.error = "voxtype record failed (" + code + ")";
            else root.error = "";
            root.cancelForLock();
            settle.restart();
        }
    }
    Process {
        id: lockCancel
        command: ["voxtype", "record", "cancel"]
        onExited: function(code) {
            if (code !== 0) root.error = "voxtype cancel on lock failed (" + code + ")";
            settle.restart();
        }
    }
    // One-shot: the daemon writes its state a moment after a command.
    Timer { id: settle; interval: 250; onTriggered: { root.readState(); info.running = true; } }
    // While Voxtype works, re-read every second in case the watcher lost the
    // file; stops by itself when the state returns to idle.
    Timer { interval: 1000; repeat: true; running: root.active && !ShellState.locked; onTriggered: root.readState() }
    FileView {
        id: stateFile
        path: ""
        watchChanges: true
        printErrors: false
        onLoaded: root.applyState(text())
        onFileChanged: reload()
        onLoadFailed: function(err) { if (root.installed) { root.daemon = false; root.state = ""; } }
    }
    Component.onCompleted: refresh()
}
