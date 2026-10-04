import QtQuick
import Quickshell
import Quickshell.Io
import ".."

Scope {
    id: root
    readonly property bool active: saved.active
    readonly property bool paused: saved.paused
    readonly property bool completed: saved.completed
    property double now: Date.now()
    readonly property int remaining: active ? Math.max(0, Math.ceil(paused ? saved.remaining : (saved.deadline - now) / 1000)) : 0
    readonly property string label: saved.label || "Timer"
    signal changed
    function start(seconds, label = "Timer") {
        const n = Number(seconds);
        if (!isFinite(n) || n < 1 || n > 86400)
            return false;
        now = Date.now();
        saved.label = String(label).slice(0, 80);
        saved.deadline = now + n * 1000;
        saved.remaining = n;
        saved.paused = false;
        saved.completed = false;
        saved.active = true;
        changed();
        return true;
    }
    function toggle() {
        if (!active)
            return;
        now = Date.now();
        if (paused) {
            saved.deadline = now + saved.remaining * 1000;
            saved.paused = false;
        } else {
            saved.remaining = Math.max(0, (saved.deadline - now) / 1000);
            saved.paused = true;
        }
        changed();
    }
    function cancel() {
        saved.active = false;
        saved.completed = false;
        saved.paused = false;
        changed();
    }
    Timer {
        interval: 250
        repeat: true
        running: root.active && !root.paused
        onTriggered: {
            root.now = Date.now();
            if (root.remaining <= 0) {
                saved.active = false;
                saved.completed = true;
                root.changed();
            }
        }
    }
    Timer {
        id: save
        interval: 80
        onTriggered: store.writeAdapter()
    }
    FileView {
        id: store
        path: Config.stateDir + "/core-timer.json"
        printErrors: false
        atomicWrites: true
        onLoaded: {
            root.now = Date.now();
            root.changed();
        }
        onAdapterUpdated: save.restart()
        JsonAdapter {
            id: saved
            property bool active: false
            property bool paused: false
            property bool completed: false
            property real deadline: 0
            property real remaining: 0
            property string label: "Timer"
        }
    }
}
