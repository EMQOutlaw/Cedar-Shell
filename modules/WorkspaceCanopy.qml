import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import ".."
import "../components"
import "../services"

// The workspace overview: one column per monitor, one chamfered tile per
// workspace in the shape of its monitor, each window drawn where it sits.
// Thumbnails come from the compositor's toplevel-export path through
// ScreencopyView, captured once when the overview opens and again when the
// focused window changes while it is open; never live, never for windows
// the compositor refuses. Everything else is Hyprland's own IPC state:
// workspaces, their monitor, their windows and the active one.
//
// Click or Enter switches; arrows move the selection; a window dragged onto
// another tile moves there (silently, so the overview stays). The
// dispatcher strings follow the running Hyprland: its Lua form when the
// compositor reports a Lua configuration, the classic form otherwise.
ColumnLayout {
    id: root
    property bool active: true
    spacing: 14
    function beat(order, span = .4) { return Canopy.ease(.06 * order, span); }
    readonly property var monitors: Hyprland.monitors.values.slice().sort((a, b) => a.x - b.x || a.y - b.y)
    readonly property var workspaces: Hyprland.workspaces.values.slice().filter(w => w.id > 0).sort((a, b) => a.id - b.id)
    readonly property var specials: Hyprland.workspaces.values.filter(w => w.id < 0)
    readonly property int columns: Math.max(1, monitors.length)
    readonly property bool available: monitors.length > 0
    // The next empty id, for the "new workspace" tile.
    readonly property int nextId: { let n = 1; const ids = workspaces.map(w => w.id); while (ids.includes(n)) n++; return n; }
    property string selected: ""     // "<workspace id>" or "new:<monitor name>"
    property int captureRevision: 0
    function lua(expr) { return Hyprland.usingLua ? expr : null; }
    function switchTo(id) {
        if (ShellState.locked) return;
        Hyprland.dispatch(Hyprland.usingLua ? "hl.dsp.focus({ workspace = \"" + id + "\" })" : "workspace " + id);
        Canopy.close();
    }
    function moveWindow(address, id) {
        if (!address || ShellState.locked) return;
        Hyprland.dispatch(Hyprland.usingLua ? "hl.dsp.window.move({ workspace = \"" + id + "\", follow = false, window = \"address:" + address + "\" })" : "movetoworkspacesilent " + id + ",address:" + address);
        Forest.record("canopy", "Moved a window to workspace " + id, "workspaces");
    }
    function recapture() { captureRevision++; }
    // One capture when the overview opens, one more when focus moves while it is open; nothing afterwards.
    onActiveChanged: if (active) { recapture(); selected = String(Hyprland.focusedWorkspace?.id || ""); }
    Component.onCompleted: if (active) { recapture(); selected = String(Hyprland.focusedWorkspace?.id || ""); }
    Connections { target: Hyprland; function onActiveToplevelChanged() { if (root.active) refocus.restart(); } }
    Timer { id: refocus; interval: 300; onTriggered: root.recapture() }
    readonly property var order: {
        const rows = [];
        for (const m of monitors) { for (const w of workspaces.filter(w => w.monitor && w.monitor.name === m.name)) rows.push(String(w.id)); rows.push("new:" + m.name); }
        return rows;
    }
    function move(delta) { const at = Math.max(0, order.indexOf(selected)); const next = order[Math.max(0, Math.min(order.length - 1, at + delta))]; if (next) selected = next; }
    function activateSelected() { if (selected.startsWith("new:")) switchTo(nextId); else if (selected) switchTo(Number(selected)); }
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Left || event.key === Qt.Key_Up) { move(-1); event.accepted = true; }
        else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down || event.key === Qt.Key_Tab) { move(1); event.accepted = true; }
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Space) { activateSelected(); event.accepted = true; }
        else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9) { switchTo(event.key - Qt.Key_0); event.accepted = true; }
    }
    focus: true

    RowLayout {
        Layout.fillWidth: true; spacing: 8
        opacity: root.beat(0)
        SectionMark { text: "WORKSPACES" }
        Item { Layout.fillWidth: true }
        GlowText { text: root.available ? root.workspaces.length + (root.workspaces.length === 1 ? " WORKSPACE" : " WORKSPACES") + " · " + root.monitors.length + (root.monitors.length === 1 ? " MONITOR" : " MONITORS") : "NO COMPOSITOR"; font.pixelSize: 9; font.letterSpacing: 1.2; color: Theme.muted }
        StationButton { text: "Refresh"; implicitHeight: 26; hint: "Capture the thumbnails again"; onClicked: root.recapture() }
    }
    GlowText { visible: !root.available; text: "Hyprland is not reachable from this shell, so there is nothing to show."; font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }

    // One column per monitor.
    RowLayout {
        visible: root.available
        Layout.fillWidth: true; spacing: 16
        Repeater {
            model: root.monitors
            ColumnLayout {
                id: column
                required property var modelData
                required property int index
                readonly property var monitor: modelData
                readonly property var rows: root.workspaces.filter(w => w.monitor && w.monitor.name === column.monitor.name)
                readonly property real aspect: monitor.width > 0 && monitor.height > 0 ? monitor.height / monitor.width : .5625
                Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.alignment: Qt.AlignTop
                spacing: 10
                opacity: root.beat(1 + index)
                RowLayout { Layout.fillWidth: true; spacing: 8
                    Rectangle { width: 6; height: 6; radius: 3; color: column.monitor.focused ? Theme.green : Theme.muted }
                    GlowText { text: column.monitor.name.toUpperCase(); font.pixelSize: 10; font.letterSpacing: 1.4; color: column.monitor.focused ? Theme.green : Theme.muted }
                    GlowText { text: column.monitor.width + "×" + column.monitor.height; font.pixelSize: 9; color: Theme.muted; Layout.fillWidth: true; elide: Text.ElideRight } }
                Repeater {
                    model: column.rows
                    WorkspaceTile { required property var modelData; required property int index; workspace: modelData; monitor: column.monitor; aspect: column.aspect; order: 2 + column.index * 2 + index * .6 }
                }
                // A new, empty workspace on this monitor.
                WorkspaceTile { workspace: null; monitor: column.monitor; aspect: column.aspect; order: 2 + column.index * 2 + column.rows.length * .6 }
            }
        }
    }
    GlowText { visible: root.available && root.specials.length; text: root.specials.map(w => w.name.replace("special:", "")).join(", ") + " · special " + (root.specials.length === 1 ? "workspace" : "workspaces") + " (not shown)"; font.pixelSize: 10; color: Theme.muted; Layout.fillWidth: true; elide: Text.ElideRight; opacity: root.beat(6) }
    GlowText { visible: root.available; text: "Click or Enter switches · arrows and 1–9 choose · drag a window onto another workspace to move it there"; font.pixelSize: 10; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap; opacity: root.beat(7) }

    // One workspace, in its monitor's shape, with its windows where they are.
    component WorkspaceTile: Item {
        id: tile
        property var workspace: null
        property var monitor: null
        property real aspect: .5625
        property real order: 0
        readonly property bool empty: workspace === null
        readonly property string key: empty ? "new:" + (monitor ? monitor.name : "") : String(workspace.id)
        readonly property bool current: !empty && workspace.active
        readonly property bool chosen: root.selected === key
        readonly property var toplevels: empty ? [] : workspace.toplevels.values
        readonly property string label: empty ? "NEW · " + root.nextId : (workspace.name !== String(workspace.id) ? workspace.name.toUpperCase() + " · " + workspace.id : String(workspace.id))
        Layout.fillWidth: true
        implicitHeight: Math.round(width * aspect) + 26
        opacity: root.beat(order, .35)
        Accessible.role: Accessible.Button
        Accessible.name: (empty ? "New workspace" : "Workspace " + workspace.name) + (current ? ", active" : "") + ", " + toplevels.length + " windows"
        ChamferFrame {
            id: frame
            anchors.fill: parent; anchors.bottomMargin: 26
            cut: 8
            fill: tile.current ? Qt.alpha(Theme.green, .05) : hover.hovered ? Qt.alpha(Theme.elevated, .9) : Qt.alpha(Theme.surface, .85)
            stroke: tile.chosen ? Theme.green : tile.current ? Qt.alpha(Theme.green, .5) : drop.containsDrag ? Qt.alpha(Theme.amber, .7) : hover.hovered ? Qt.alpha(Theme.teal, .4) : Qt.alpha(Theme.teal, .16)
            strokeWidth: tile.chosen ? 2 : 1
            line: tile.current; lineColor: Theme.green; lineFraction: .5
            // The empty tile is a suggestion: dashed inner outline.
            Canvas { visible: tile.empty; anchors.fill: parent; anchors.margins: 10; onWidthChanged: requestPaint(); onHeightChanged: requestPaint()
                onPaint: { const c = getContext("2d"); c.reset(); c.strokeStyle = Qt.alpha(Theme.teal, .25); c.lineWidth = 1; c.setLineDash([4, 4]); c.strokeRect(.5, .5, width - 1, height - 1); } }
            GlowText { visible: tile.empty || !tile.toplevels.length; anchors.centerIn: parent; text: tile.empty ? "EMPTY" : "NO WINDOWS"; font.pixelSize: 10; font.letterSpacing: 1.6; color: Theme.muted }
            // Windows where they sit on the monitor, scaled into the tile.
            Item {
                id: stage
                anchors.fill: parent; anchors.margins: 6
                readonly property real sx: tile.monitor && tile.monitor.width > 0 ? width / (tile.monitor.width / (tile.monitor.scale || 1)) : 0
                readonly property real sy: tile.monitor && tile.monitor.height > 0 ? height / (tile.monitor.height / (tile.monitor.scale || 1)) : 0
                Repeater {
                    model: tile.toplevels
                    Item {
                        id: win
                        required property var modelData
                        readonly property var ipc: modelData.lastIpcObject || ({})
                        readonly property var at: ipc.at || [0, 0]
                        readonly property var size: ipc.size || [0, 0]
                        readonly property string address: modelData.address || ipc.address || ""
                        readonly property string klass: ipc["class"] || ipc.initialClass || ""
                        x: Math.round(((at[0] || 0) - (tile.monitor ? tile.monitor.x : 0)) * stage.sx)
                        y: Math.round(((at[1] || 0) - (tile.monitor ? tile.monitor.y : 0)) * stage.sy)
                        width: Math.max(8, Math.round((size[0] || 0) * stage.sx))
                        height: Math.max(8, Math.round((size[1] || 0) * stage.sy))
                        z: modelData.activated ? 2 : 1
                        Drag.active: pull.drag.active
                        Drag.hotSpot.x: width / 2; Drag.hotSpot.y: height / 2
                        Drag.keys: ["cedar-window"]
                        // Attached Drag state is only reachable from the item itself.
                        function finishDrag() { const target = Drag.target; Drag.drop(); return target; }
                        Rectangle { anchors.fill: parent; radius: 3; color: Qt.alpha(Theme.background, .9); border.width: modelData.activated ? 1.5 : 1; border.color: modelData.activated ? Theme.green : Qt.alpha(Theme.teal, .35) }
                        // The thumbnail: captured once per revision, never live. A refused or absent capture shows the class instead.
                        ScreencopyView {
                            id: shot
                            anchors.fill: parent; anchors.margins: 1
                            captureSource: win.modelData.wayland || null
                            live: false
                            paintCursor: false
                            property int revision: root.captureRevision
                            // The recording context is created after the source is set and the
                            // view is shown; a capture asked for at once is refused. One short
                            // one-shot timer per request, nothing recurring.
                            onRevisionChanged: if (captureSource && tile.visible) arm.restart()
                            Component.onCompleted: if (captureSource) arm.restart()
                            onCaptureSourceChanged: if (captureSource) arm.restart()
                            Timer { id: arm; interval: 160; onTriggered: if (shot.captureSource && shot.visible !== undefined) shot.captureFrame() }
                            visible: hasContent || !captureSource
                        }
                        Rectangle { visible: !shot.hasContent; anchors.centerIn: parent; width: Math.min(parent.width - 6, classLabel.implicitWidth + 10); height: 16; radius: 3; color: Qt.alpha(Theme.surface, .9)
                            GlowText { id: classLabel; anchors.centerIn: parent; text: (win.klass || win.modelData.title || "window").slice(0, 24); font.pixelSize: 9; color: Theme.muted } }
                        MouseArea {
                            id: pull
                            anchors.fill: parent
                            drag.target: win
                            cursorShape: Qt.OpenHandCursor
                            hoverEnabled: true
                            ToolTip.visible: containsMouse && !drag.active && (win.modelData.title || "") !== ""
                            ToolTip.text: win.modelData.title || ""
                            ToolTip.delay: 500
                            onReleased: { const ox = win.x, oy = win.y; const target = win.finishDrag(); if (target && target.workspaceId !== undefined && target.workspaceId !== (tile.empty ? -1 : tile.workspace.id)) root.moveWindow(win.address, target.workspaceId); win.x = ox; win.y = oy; }
                            onClicked: if (!tile.empty) root.switchTo(tile.workspace.id)
                        }
                    }
                }
            }
            DropArea { id: drop; anchors.fill: parent; keys: ["cedar-window"]; property int workspaceId: tile.empty ? root.nextId : tile.workspace.id }
            HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: { root.selected = tile.key; if (tile.empty) root.switchTo(root.nextId); else root.switchTo(tile.workspace.id); } }
        }
        RowLayout {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 22; spacing: 6
            GlowText { text: tile.label; font.pixelSize: 10; font.letterSpacing: 1.2; color: tile.current ? Theme.green : Theme.text }
            StatusPill { visible: tile.current; text: "Active"; tone: Theme.green; implicitHeight: 18 }
            Item { Layout.fillWidth: true }
            GlowText { visible: !tile.empty; text: tile.toplevels.length + (tile.toplevels.length === 1 ? " WINDOW" : " WINDOWS") + (tile.workspace && tile.workspace.hasFullscreen ? " · FULLSCREEN" : "") + (tile.workspace && tile.workspace.urgent ? " · URGENT" : ""); font.pixelSize: 9; font.letterSpacing: 1; color: tile.workspace && tile.workspace.urgent ? Theme.amber : Theme.muted }
        }
    }
}
