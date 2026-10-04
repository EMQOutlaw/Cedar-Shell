pragma Singleton
import QtQuick
import Quickshell
import ".."
import "../components"
import "../components/core/Activities.js" as Policy

Singleton {
    id: root
    readonly property bool enabled: Config.stage >= 3 && Config.saved.coreEnabled
    property string fallbackOutput: Quickshell.screens[0]?.name || ""
    readonly property var hostScreen: Quickshell.screens.find(s => s.name === (Config.saved.coreMonitor || Config.saved.mainDisplay)) || Quickshell.screens.find(s => s.name === fallbackOutput) || Quickshell.screens[0] || null
    readonly property string hostName: hostScreen?.name || ""
    readonly property int reserveWidth: Math.min(360, Math.max(240, (hostScreen?.width || 1000) * .30))
    readonly property bool available: enabled && !!hostScreen && !ShellState.locked && ["", "core", "canopy"].includes(ShellState.panel)
    readonly property bool expanded: ShellState.panel === "core"
    readonly property bool ownsOsd: available && Config.saved.coreVolume && ["VOLUME", "BRIGHTNESS"].includes(ShellState.osdKind)
    readonly property alias model: activities
    readonly property alias timer: timer
    readonly property alias probe: probe
    readonly property var foreground: activities.foreground
    readonly property var rows: activities.ranked
    property var routedNoticeIds: []
    property string error: ""
    property string message: ""
    property var packages: []
    property bool actionBusy: actions.running
    property string confirmTrash: ""
    property bool dropHover: false
    property string activeFileAction: ""
    property double now: Date.now()
    readonly property var recordings: probe.error ? [] : probe.data.recordings
    readonly property bool recording: recordings.length > 0
    readonly property var privacy: rows.filter(r => ["microphone", "camera"].includes(r.type))
    function allowed(type) {
        const key = ({
                volume: "coreVolume",
                brightness: "coreVolume",
                media: "coreMedia",
                notification: "coreNotifications",
                bluetooth: "coreConnections",
                network: "coreConnections",
                vpn: "coreConnections",
                workspace: "coreWorkspaces",
                keyboard: "coreKeyboard",
                clipboard: "coreClipboard",
                power: "corePower",
                warning: "coreWarnings",
                microphone: "corePrivacy",
                camera: "corePrivacy"
            })[type];
        return enabled && (!key || Config.saved[key]);
    }
    function publish(event) {
        if (!allowed(event.type))
            return false;
        try {
            activities.publish(event);
            return true;
        } catch (e) {
            error = String(e);
            return false;
        }
    }
    function remove(id, remember = true) {
        activities.remove(id, remember);
    }
    function external(payload) {
        try {
            const value = typeof payload === "string" ? JSON.parse(payload) : payload;
            const event = Policy.external(value, Date.now());
            if (!activities.rows.some(r => r.id === event.id) && activities.rows.filter(r => r.source === event.source && r.id.startsWith("external/")).length >= 8)
                return "This provider already has eight active activities.";
            return publish(event) ? "ok" : "Core is disabled or the activity could not be published.";
        } catch (e) {
            return String(e);
        }
    }
    function withdraw(source, id) {
        if (!/^[a-z0-9][a-z0-9._-]{0,39}$/.test(source) || !/^[a-z0-9][a-z0-9._-]{0,59}$/.test(id))
            return "Invalid activity identity.";
        remove("external/" + source + "/" + id);
        return "ok";
    }
    function expand(id = "") {
        if (!enabled || ShellState.locked)
            return;
        activities.selectedId = id;
        ShellState.panel = "core";
        ShellState.output = hostName;
    }
    function toggle() {
        if (expanded)
            collapse();
        else
            expand(foreground?.id || "");
    }
    function collapse() {
        if (expanded)
            ShellState.close();
        activities.selectedId = "";
        confirmTrash = "";
    }
    function hold(id) {
        activities.hold(id);
    }
    function dismiss(id) {
        const row = activities.rows.find(r => r.id === id);
        if (row?.type === "timer")
            timer.cancel();
        else if (row?.type === "notification") {
            const n = NoticeStore.live.find(n => n.id === row.data.noticeId);
            if (n)
                n.dismiss();
        } else if (row && ["recording", "microphone", "camera"].includes(row.type))
            return;
        remove(id);
    }
    function run(request) {
        if (actions.running || Config.testMode)
            return;
        error = "";
        message = "Working…";
        activeFileAction = request.action;
        actions.send(request);
    }
    function invoke(row, action) {
        if (!row)
            return;
        if (action.startsWith("notice:")) {
            const n = NoticeStore.live.find(n => n.id === row.data.noticeId), a = n?.actions.find(a => a.identifier === action.slice(7));
            if (a) {
                a.invoke();
                collapse();
            }
            return;
        }
        if (action === "timer-pause")
            timer.toggle();
        else if (action === "timer-cancel")
            timer.cancel();
        else if (action === "power-saver")
            Controls.run({
                action: "profile",
                value: "power-saver"
            });
        else if (action === "stop-recording")
            run({
                action: action,
                pid: row.data.pid,
                startTicks: row.data.startTicks
            });
        else if (action === "connections") {
            collapse();
            if(Config.saved.canopyEnabled)Canopy.open("network");else ShellState.open("control");
        } else if (action === "system") {
            collapse();
            ShellState.settingsPage = "system";
            ShellState.open("settings");
        } else if (action === "updates") {
            collapse();
            Go.toggle("update");
        } else if (action === "history") {
            collapse();
            if(Config.saved.canopyEnabled)Canopy.open("notifications");else ShellState.open("history");
        } else if (["open-file", "reveal-file", "copy-path", "copy-image", "share-file", "trash-file"].includes(action)) {
            if (action === "trash-file" && confirmTrash !== row.id) {
                confirmTrash = row.id;
                return;
            }
            confirmTrash = "";
            run({
                action: action,
                path: row.data.path
            });
        }
    }
    function syncTimer() {
        if (timer.active)
            publish({
                id: "timer",
                type: "timer",
                priority: "normal",
                title: timer.label,
                subtitle: timer.paused ? "Paused" : "Counting down",
                persistent: true,
                announce: false,
                actions: [
                    {
                        id: "timer-pause",
                        label: timer.paused ? "Resume" : "Pause"
                    },
                    {
                        id: "timer-cancel",
                        label: "Cancel"
                    }
                ]
            });
        else if (timer.completed)
            publish({
                id: "timer",
                type: "timer",
                priority: "high",
                title: "Timer complete",
                subtitle: timer.label,
                persistent: true,
                sticky: true,
                remember: true,
                actions: [
                    {
                        id: "timer-cancel",
                        label: "Dismiss"
                    }
                ]
            });
        else
            remove("timer", false);
    }
    onEnabledChanged: {
        if (!enabled) {
            activities.state = Policy.create();
            routedNoticeIds = [];
            collapse();
            ShellState.osdCoreInteracting = false;
        } else
            syncTimer();
    }
    onAvailableChanged: if (!available) {
        activities.hold("");
        ShellState.osdCoreInteracting = false;
    }
    onExpandedChanged: if (!expanded) {
        activities.selectedId = "";
        confirmTrash = "";
    }
    CoreActivityModel {
        id: activities
    }
    CoreTimer {
        id: timer
        onChanged: root.syncTimer()
    }
    CoreProbe {
        id: probe
        enabled: root.enabled
    }
    CoreSources {
        service: root
    }
    ServiceRequest {
        id: actions
        script: "scripts/core_actions.py"
        onFailed: value => {
            root.error = value;
            root.message = "";
        }
        onResult: value => {
            root.message = value.message || "";
            if (value.action === "inspect-file") {
                const id = "file/selected";
                root.publish({
                    id: id,
                    type: "file",
                    title: value.name,
                    subtitle: "Choose an action for this file",
                    persistent: true,
                    timeout: 6000,
                    data: {
                        path: value.path
                    },
                    actions: [
                        {
                            id: "open-file",
                            label: "Open"
                        },
                        {
                            id: "copy-path",
                            label: "Copy path"
                        },
                        {
                            id: "share-file",
                            label: "Share"
                        },
                        {
                            id: "reveal-file",
                            label: "Reveal"
                        },
                        {
                            id: "trash-file",
                            label: "Move to Trash"
                        }
                    ]
                });
                root.expand(id);
            } else if (value.action === "check-updates") {
                root.packages = value.packages || [];
                root.publish({
                    id: "updates",
                    type: "update",
                    title: value.count ? value.count + " repository updates" : "Repository packages are current",
                    subtitle: value.message,
                    persistent: value.count > 0,
                    timeout: 5000,
                    actions: [
                        {
                            id: "updates",
                            label: "Open update menu"
                        }
                    ]
                });
            } else if (["copy-path", "copy-image"].includes(value.action))
                root.publish({
                    id: "clipboard",
                    type: "clipboard",
                    title: value.action === "copy-image" ? "Image copied" : "Path copied",
                    timeout: 1800
                });
            else if (value.action === "trash-file") {
                const row = root.model.rows.find(r => r.id === "file/selected" && r.data.path === value.path);
                if (row)
                    root.remove(row.id, false);
            }
        }
    }
    Timer {
        interval: 1000
        repeat: true
        running: root.available && (root.recording || root.expanded)
        onTriggered: root.now = Date.now()
    }
}
