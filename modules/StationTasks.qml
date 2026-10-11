import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import ".."
import "../components"
import "../services"

// Read-only task instrument. The sampler exists only while this page is visible.
ColumnLayout {
    id: root
    property bool active: false
    property bool paused: false
    property string query: ""
    property string sortBy: "cpu"
    property bool applications: false
    property var snapshot: ({ processes: [], cores: [], gpus: [], total: 0, omitted: 0 })
    property string error: ""
    readonly property bool sampling: active && !paused && !ShellState.locked && !Config.testMode
    readonly property var windows: {
        const result = [];
        for (const w of Hyprland.workspaces.values) {
            for (const t of w.toplevels.values) {
                result.push({ window: t, workspace: w, title: t.title || t.lastIpcObject?.title || "Untitled window",
                    app: t.lastIpcObject?.["class"] || t.lastIpcObject?.initialClass || "Application",
                    pid: t.lastIpcObject?.pid || 0 });
            }
        }
        return result;
    }
    readonly property var rows: {
        const q = query.toLowerCase().trim();
        const list = (applications ? windows : snapshot.processes || []).filter(p =>
            [p.name || p.title, p.user || p.app, String(p.pid)].join(" ").toLowerCase().includes(q));
        if (applications) return list;
        return list.slice().sort((a, b) => sortBy === "name" ? a.name.localeCompare(b.name) || a.pid - b.pid
            : sortBy === "pid" ? a.pid - b.pid : (b[sortBy] ?? -1) - (a[sortBy] ?? -1) || a.pid - b.pid);
    }
    function memory(bytes) { return bytes >= 1073741824 ? (bytes / 1073741824).toFixed(1) + " GiB" : (bytes / 1048576).toFixed(0) + " MiB"; }
    function percent(value) { return value === null || value === undefined ? "—" : value.toFixed(1) + "%"; }
    function sync() { if (!worker || !retry) return; retry.stop(); worker.running = sampling; }
    onSamplingChanged: sync()
    Component.onCompleted: sync()
    Process {
        id: worker
        command: ["python3", Quickshell.shellPath("scripts/task_monitor.py"), "--watch"]
        stdout: SplitParser {
            onRead: line => {
                try {
                    const result = JSON.parse(line);
                    if (result.ok) { root.snapshot = result.data; root.error = ""; }
                    else root.error = result.error || "Process readings are unavailable.";
                } catch (_) { root.error = "The task sampler returned an invalid reading."; }
            }
        }
        onExited: (code, status) => {
            if (root.sampling) { root.error = "Task sampler stopped. Reconnecting…"; retry.restart(); }
        }
    }
    Timer { id: retry; interval: 5000; onTriggered: root.sync() }
    spacing: 12
    RowLayout {
        Layout.fillWidth: true
        SectionMark { text: "TASKS & PERFORMANCE"; tone: Theme.strataAccent; Layout.fillWidth: true }
        StrataButton { text: root.paused ? "Resume" : "Pause"; checked: root.paused; onClicked: root.paused = !root.paused }
    }
    Flow {
        Layout.fillWidth: true; spacing: 10
        StatusPill { text: "CPU " + (SystemStats.cpu < 0 ? "—" : Math.round(SystemStats.cpu * 100) + "%"); tone: Theme.strataAccent }
        StatusPill { text: "RAM " + SystemStats.memoryLabel; tone: Theme.strataAccent }
        StatusPill { text: "Disk " + (SystemStats.disk < 0 ? "—" : Math.round(SystemStats.disk * 100) + "% used"); tone: Theme.strataAccent }
        StatusPill { text: SystemStats.temperature < 0 ? "Temperature —" : SystemStats.temperature + "°C"; tone: SystemStats.temperature >= Config.saved.coreTemperatureLimit ? Theme.amber : Theme.strataAccent }
    }
    ActivityTrace { Layout.fillWidth: true; implicitHeight: 44; active: root.active && !root.paused; value: SystemStats.cpu; accent: Theme.strataAccent }
    GridLayout {
        Layout.fillWidth: true; columns: Math.max(2, Math.floor(root.width / 115)); columnSpacing: 12; rowSpacing: 7
        Repeater {
            model: root.snapshot.cores || []
            ColumnLayout {
                required property var modelData
                Layout.fillWidth: true; spacing: 3
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: modelData.name.toUpperCase(); font.family: Theme.dataFont; font.pixelSize: 9; color: Theme.strataMuted }
                    Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignRight; text: modelData.cpu === null ? "—" : Math.round(modelData.cpu) + "%"; font.family: Theme.dataFont; font.pixelSize: 9; color: Theme.strataText }
                }
                Rectangle {
                    Layout.fillWidth: true; implicitHeight: 3; color: Theme.strataGrain
                    Rectangle { width: parent.width * Math.max(0, modelData.cpu || 0) / 100; height: parent.height; color: modelData.cpu > 90 ? Theme.amber : Theme.strataAccent }
                }
            }
        }
    }
    Repeater {
        model: root.snapshot.gpus || []
        GlowText {
            required property var modelData
            Layout.fillWidth: true; wrapMode: Text.WordWrap; font.pixelSize: Theme.small; color: Theme.strataMuted
            text: modelData.name + " · GPU " + (modelData.load === null ? "—" : modelData.load + "%")
                + " · VRAM " + (modelData.used === null ? "—" : Math.round(modelData.used) + " / " + (modelData.total === null ? "—" : Math.round(modelData.total)) + " MiB")
                + (modelData.temperature === null ? "" : " · " + modelData.temperature + "°C")
        }
    }
    GlowText { visible: !(root.snapshot.gpus || []).length; text: root.snapshot.gpuError || "GPU readings are unavailable for this device."; color: Theme.strataMuted; font.pixelSize: Theme.small; Layout.fillWidth: true; wrapMode: Text.WordWrap }
    RowLayout {
        Layout.fillWidth: true
        StrataButton { text: "Processes · " + root.snapshot.total; checked: !root.applications; onClicked: root.applications = false }
        StrataButton { text: "Applications · " + root.windows.length; checked: root.applications; onClicked: root.applications = true }
    }
    StrataField { objectName: "taskSearch"; Layout.fillWidth: true; placeholderText: "Filter by name, user or PID"; Accessible.name: "Filter tasks"; onTextChanged: root.query = text }
    RowLayout {
        visible: !root.applications
        Layout.fillWidth: true; spacing: 4
        Repeater {
            model: [{key:"name",label:"NAME"}, {key:"pid",label:"PID"}, {key:"cpu",label:"CPU"}, {key:"rss",label:"MEMORY"}]
            StrataButton {
                required property var modelData
                Layout.fillWidth: modelData.key === "name"
                text: modelData.label + (root.sortBy === modelData.key ? (["name", "pid"].includes(root.sortBy) ? " ▴" : " ▾") : "")
                checked: root.sortBy === modelData.key
                onClicked: root.sortBy = modelData.key
            }
        }
    }
    ListView {
        id: table
        objectName: "taskRows"
        Layout.fillWidth: true; Layout.preferredHeight: 310
        clip: true; model: root.rows; spacing: 1
        ScrollBar.vertical: ScrollBar {}
        boundsBehavior: Flickable.StopAtBounds
        delegate: Rectangle {
            required property var modelData
            required property int index
            width: table.width - 12
            height: 52
            color: index % 2 ? Qt.alpha(Theme.strataSurface, .6) : Theme.transparent
            RowLayout {
                anchors.fill: parent; anchors.margins: 6; spacing: 10
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 2
                    Text { Layout.fillWidth: true; text: root.applications ? modelData.title : modelData.name; textFormat: Text.PlainText; elide: Text.ElideRight; color: Theme.strataText; font.family: Theme.dataFont; font.pixelSize: Theme.small }
                    Text { Layout.fillWidth: true; text: root.applications ? modelData.app : modelData.user + " · " + modelData.state + " · " + modelData.threads + " threads"; textFormat: Text.PlainText; elide: Text.ElideRight; color: Theme.strataMuted; font.family: Theme.dataFont; font.pixelSize: 9 }
                }
                Text { text: String(modelData.pid); color: Theme.strataMuted; font.family: Theme.dataFont; font.pixelSize: 10; Layout.preferredWidth: 52; horizontalAlignment: Text.AlignRight }
                Text { visible: !root.applications; text: root.percent(modelData.cpu); color: Theme.strataAccent; font.family: Theme.dataFont; font.pixelSize: 10; Layout.preferredWidth: 60; horizontalAlignment: Text.AlignRight }
                Text { visible: !root.applications; text: root.memory(modelData.rss || 0); color: Theme.strataText; font.family: Theme.dataFont; font.pixelSize: 10; Layout.preferredWidth: 70; horizontalAlignment: Text.AlignRight }
                StrataButton {
                    visible: root.applications
                    text: "Space " + (modelData.workspace?.name || "")
                    hint: "Open this application's workspace"
                    onClicked: {
                        if (ShellState.locked || Config.testMode) return;
                        modelData.workspace.activate();
                        Canopy.close(); ShellState.close();
                    }
                }
            }
        }
    }
    GlowText { visible: root.rows.length === 0; text: root.query ? "No matching tasks." : root.applications ? "No application windows are available." : "Waiting for process readings…"; color: Theme.strataMuted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
    GlowText { visible: root.error !== ""; text: root.error; color: Theme.amber; Layout.fillWidth: true; wrapMode: Text.WordWrap }
    GlowText {
        text: (root.paused ? "Process sampling paused. " : "Processes refresh every 2 seconds. ") + "100% CPU = one logical core. Memory is resident RAM."
            + (root.snapshot.omitted ? " Showing the busiest 4096 of " + root.snapshot.total + " processes." : "")
        color: Theme.strataMuted; font.pixelSize: 10; Layout.fillWidth: true; wrapMode: Text.WordWrap
    }
}
