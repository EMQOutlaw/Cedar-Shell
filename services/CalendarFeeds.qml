pragma Singleton
import QtQuick
import Quickshell
import ".."
import "../components"

Singleton {
    id: root
    property var sources: []
    property var events: []
    property string error: ""
    property string message: ""
    property string begin: Qt.formatDateTime(new Date(), "yyyy-MM-01")
    property string end: Qt.formatDateTime(new Date(new Date().getFullYear(), new Date().getMonth() + 1, 1), "yyyy-MM-dd")
    property bool truncated: false
    readonly property bool busy: worker.busy
    property bool refreshPending: false
    // Month navigation coalesces while an adapter is busy. Resume on completion
    // instead of waking every 100 ms for the entire request timeout.
    onBusyChanged: if (!busy && refreshPending) { refreshPending = false; load.restart(); }
    readonly property bool configured: sources.length > 0
    signal completed(string action)
    property string action: "snapshot"
    function request(value) {
        if (Config.testMode || ShellState.locked || busy) return false;
        error = ""; message = ""; action = value.action;
        return worker.send(Object.assign({}, value, { begin: begin, end: end, offline: Config.localOnly }));
    }
    function viewMonth(month) {
        begin = Qt.formatDateTime(month, "yyyy-MM-01");
        end = Qt.formatDateTime(new Date(month.getFullYear(), month.getMonth() + 1, 1), "yyyy-MM-dd");
        load.restart();
    }
    function refresh(force = false) { request({ action: "refresh", force: force }); }
    function eventsOn(day) {
        const key = Qt.formatDateTime(day, "yyyy-MM-dd");
        const start = new Date(day.getFullYear(), day.getMonth(), day.getDate()).getTime();
        const stop = new Date(day.getFullYear(), day.getMonth(), day.getDate() + 1).getTime();
        return events.filter(e => e.allDay ? e.startDate <= key && e.endDate > key
            : new Date(e.start).getTime() < stop && (new Date(e.end).getTime() > start || new Date(e.end).getTime() === new Date(e.start).getTime() && new Date(e.start).getTime() >= start));
    }
    ServiceRequest {
        id: worker
        script: "scripts/calendar_service.py"
        maximumResponse: 16777216
        onResult: data => {
            if (ShellState.locked) return;
            root.sources = data.sources || []; root.events = data.events || []; root.truncated = !!data.truncated;
            if (root.action === "connect") root.message = Config.localOnly ? "Calendar saved. Turn off Local-only mode to sync." : "Calendar saved.";
            else if (root.action === "import") root.message = "Calendar imported. File imports do not sync automatically.";
            else if (root.action === "disconnect") root.message = "Calendar removed from CEDAR.";
            root.completed(root.action);
        }
        onFailed: message => { if (!ShellState.locked) root.error = message; }
    }
    Timer { id: load; interval: 100; onTriggered: { if (root.busy) root.refreshPending = true; else root.refresh(); } }
    Timer {
        interval: 900000
        running: root.configured && !Config.localOnly && !Config.testMode && !ShellState.locked
        repeat: true
        onTriggered: root.refresh()
    }
    Connections {
        target: ShellState
        function onLockedChanged() {
            if (ShellState.locked) { root.events = []; worker.queued = null; worker.running = false; }
            else if (root.configured) load.restart();
        }
    }
    Connections {
        target: Config
        function onLocalOnlyChanged() {
            if (Config.localOnly) { worker.queued = null; worker.running = false; }
            load.restart();
        }
    }
}
