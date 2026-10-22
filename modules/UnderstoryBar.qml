import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.UPower
import ".."
import "../components"
import "../services"

// The Understory bar: the Strata bar stood on its end along the left edge,
// one per output, reserving its width. The same material (Foundation, Grain,
// the chamfered ends) in one column: CEDAR's mark, Applications, the
// workspaces, the focused window's title read upwards, then status, the
// clock and the session at the foot. Clicking the mark grows the full
// Understory rail out of it. The Core pill rests while this bar is in use;
// its signals still arrive as notifications.
PanelWindow {
    id: root
    required property var output
    screen: output
    Component.onCompleted: Canopy.registerControls(root)
    Component.onDestruction: Canopy.unregisterControls(root)
    readonly property string outputName: output?.name || ""
    anchors { top: true; left: true; bottom: true }
    implicitWidth: Config.barHeight
    exclusiveZone: Config.barHeight
    color: Theme.transparent
    WlrLayershell.namespace: "cedar-bar"
    WlrLayershell.layer: WlrLayer.Top
    readonly property var monitor: Hyprland.monitorFor(screen)
    readonly property var battery: UPower.displayDevice
    readonly property bool nerd: Theme.availableFonts.includes("JetBrainsMono Nerd Font")
    readonly property var localWorkspaces: (Hyprland.workspaces?.values || []).filter(w => w.id > 0 && w.monitor?.name === outputName)
    readonly property var activeWorkspace: monitor?.activeWorkspace || null
    readonly property string activeTitle: Config.moduleEnabled("activeWindow") && Hyprland.focusedMonitor?.name === outputName ? (Hyprland.activeToplevel?.title || ToplevelManager.activeToplevel?.title || "") : ""
    readonly property bool railOpen: Understory.shown && Understory.outputName === outputName
    // Flush: the material meets the screen's edge on three sides; only the
    // right side is a seam, with the pill's cut at both of its corners.
    readonly property real pad: 4
    readonly property real cut: Theme.strataCut
    function glyph(icon, fallback) { return nerd ? icon : fallback; }
    // The drops that grow sideways out of this bar need to know where their
    // control is along it: a screen-y rect in the anchor's x/width slots.
    function sideAnchor(item) {
        return () => { const p = item.mapToItem(null, 0, 0); return { x: p.y, width: item.height }; };
    }
    SystemClock { id: clock; precision: SystemClock.Minutes }

    // ---- material ----------------------------------------------------------
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: 0; strokeColor: Theme.transparent
            fillGradient: LinearGradient {
                x1: 0; y1: 0; x2: root.width; y2: 0
                GradientStop { position: 0; color: Qt.alpha(Theme.strataSurface, Config.barOpacity) }
                GradientStop { position: 1; color: Qt.alpha(Theme.strataFoundation, Config.barOpacity) }
            }
            startX: -1; startY: -1
            PathLine { x: root.width - root.cut; y: -1 }
            PathLine { x: root.width - root.cut; y: 0 }
            PathLine { x: root.width; y: root.cut }
            PathLine { x: root.width; y: root.height - root.cut }
            PathLine { x: root.width - root.cut; y: root.height }
            PathLine { x: root.width - root.cut; y: root.height + 1 }
            PathLine { x: -1; y: root.height + 1 }
            PathLine { x: -1; y: -1 }
        }
        // The seam: only the outer side has an edge, lit a little more while the rail is out.
        ShapePath {
            strokeWidth: 1; fillColor: Theme.transparent
            strokeColor: Qt.alpha(Theme.strataGrain, root.railOpen ? .5 : .28)
            startX: root.width - root.cut; startY: 0
            PathLine { x: root.width; y: root.cut }
            PathLine { x: root.width; y: root.height - root.cut }
            PathLine { x: root.width - root.cut; y: root.height }
        }
        // Grain: a partial inner lip along the outer side.
        ShapePath {
            strokeWidth: 1; fillColor: Theme.transparent
            strokeColor: Qt.alpha(Theme.strataGrain, .12)
            startX: root.width - 2; startY: root.cut + 2
            PathLine { x: root.width - 2; y: root.height - root.cut - 2 }
        }
    }

    // ---- the column ----------------------------------------------------------
    component BarMark: StrataButton {
        id: mark
        implicitWidth: root.width - 2 * root.pad; implicitHeight: implicitWidth
        iconOnly: true
        enabled: !ShellState.locked
        // The Canopy topic that grows from this control, if any.
        property string anchorTopic: ""
        readonly property var provider: root.sideAnchor(mark)
        function publish() {
            if (!anchorTopic) return;
            if (visible && enabled) Canopy.setAnchorProvider(anchorTopic, root.outputName, provider);
            else Canopy.clearAnchorProvider(anchorTopic, root.outputName, provider);
        }
        Component.onCompleted: Qt.callLater(publish)
        Component.onDestruction: if (anchorTopic) Canopy.clearAnchorProvider(anchorTopic, root.outputName, provider)
        onVisibleChanged: Qt.callLater(publish)
        onEnabledChanged: Qt.callLater(publish)
    }

    Column {
        id: head
        x: root.pad; y: 8; spacing: 4
        width: root.width - 2 * root.pad
        StrataButton {
            objectName: "understoryBarMark"
            width: parent.width; height: width
            iconOnly: true; hint: "Understory"
            enabled: Config.stage >= 2 && !ShellState.locked
            checked: root.railOpen
            background: Item {}
            contentItem: Item {
                CedarHeartwood { anchors.centerIn: parent; size: Math.min(26, parent.width - 4); active: Config.saved.barHeartwood && !ShellState.locked; unfolding: root.railOpen; mode: Gaming.active ? "gaming" : Focus.active ? "focus" : "idle" }
            }
            onClicked: Understory.toggle(root.outputName)
        }
        BarMark {
            objectName: "understoryBarLauncher"
            visible: Config.stage >= 3 && Config.moduleEnabled("go")
            text: root.glyph("󰀻", "⊞"); hint: "Applications"
            anchorTopic: "go"
            onClicked: { if (Config.saved.canopyEnabled) Canopy.toggleTopic("go", root.outputName); else Go.toggle("root"); }
        }
        Item { width: 1; height: 4 }
        // Workspaces: one cell each, the active one marked along the outer edge.
        Column {
            objectName: "understoryBarWorkspaces"
            visible: Config.moduleEnabled("workspaces")
            width: parent.width; spacing: 2
            Rectangle { width: parent.width; height: 1; color: Qt.alpha(Theme.strataGrain, .5) }
            Repeater {
                model: root.localWorkspaces
                StrataButton {
                    id: workspaceButton
                    required property var modelData
                    width: parent.width; height: 26
                    text: /^\d+$/.test(modelData.name) ? modelData.name : modelData.name.slice(0, 2)
                    hint: "Workspace " + modelData.name
                    enabled: !ShellState.locked
                    checked: root.activeWorkspace?.id === modelData.id
                    accent: modelData.urgent ? Theme.warning : Theme.strataAccent
                    background: Item {
                        Rectangle { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; width: 2; height: workspaceButton.checked ? 16 : 0; radius: 1; color: workspaceButton.accent
                            Behavior on height { enabled: VisualQuality.functionalMotion; NumberAnimation { duration: VisualQuality.ms(Theme.hover); easing.type: Easing.OutCubic } } }
                    }
                    contentItem: Text { text: workspaceButton.text; textFormat: Text.PlainText; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; font.family: Theme.dataFont; font.pixelSize: Theme.small; color: workspaceButton.checked ? workspaceButton.accent : Theme.strataMuted }
                    onClicked: modelData.activate()
                }
            }
            BarMark {
                visible: Config.stage >= 3 && Config.saved.canopyEnabled
                text: "▣"; hint: "Workspace overview"
                anchorTopic: "workspaces"
                checked: Canopy.shown && Canopy.topic === "workspaces" && Canopy.outputName === root.outputName
                onClicked: Canopy.toggleTopic("workspaces", root.outputName)
            }
            Rectangle { width: parent.width; height: 1; color: Qt.alpha(Theme.strataGrain, .5) }
        }
    }
    // The focused window's title, read upwards, in whatever room is left.
    // (Hyprland's own activeToplevel can stay empty in a fresh process; the
    // foreign-toplevel manager always knows the focused window.)
    Item {
        id: titleSlot
        objectName: "understoryBarTitle"
        x: root.pad; width: root.width - 2 * root.pad
        anchors.top: head.bottom; anchors.topMargin: 10
        anchors.bottom: foot.top; anchors.bottomMargin: 10
        visible: root.activeTitle !== "" && height > 60
        clip: true
        Text {
            anchors.centerIn: parent
            width: titleSlot.height
            rotation: -90
            text: root.activeTitle; textFormat: Text.PlainText
            elide: Text.ElideRight; horizontalAlignment: Text.AlignHCenter
            font.family: Theme.labelFont; font.pixelSize: Math.round(12 * Theme.fontScale); font.letterSpacing: .6
            color: Theme.strataMuted
        }
    }
    Column {
        id: foot
        x: root.pad; spacing: 4
        width: root.width - 2 * root.pad
        anchors.bottom: parent.bottom; anchors.bottomMargin: 8
        // Status: each reading opens the rail, where its control lives.
        BarMark {
            objectName: "understoryBarNetwork"
            visible: Config.moduleEnabled("network")
            text: root.nerd ? Network.glyph : Network.fallbackGlyph
            hint: Network.statusDescription
            accent: Network.state === "connected" ? Theme.strataAccent : Theme.strataMuted
            onClicked: Understory.toggle(root.outputName)
        }
        BarMark {
            objectName: "understoryBarAudio"
            visible: Config.moduleEnabled("audio") && Audio.audio !== null
            text: Audio.muted ? root.glyph("󰝟", "×") : root.glyph("󰕾", "♪")
            hint: "Output " + Audio.label + " · scroll adjusts"
            accent: Audio.muted ? Theme.amber : Theme.strataAccent
            onClicked: Understory.toggle(root.outputName)
            WheelHandler { onWheel: event => Audio.setVolume(Audio.volume + (event.angleDelta.y > 0 ? .05 : -.05)) }
        }
        Column {
            objectName: "understoryBarBattery"
            visible: Config.moduleEnabled("battery") && (root.battery?.isPresent ?? false)
            width: parent.width; spacing: 0
            readonly property int percent: Math.round((root.battery?.percentage ?? 0) * 100)
            readonly property bool low: UPower.onBattery && (root.battery?.percentage ?? 1) < .2
            BarMark {
                text: root.nerd ? (UPower.onBattery ? "󰁹" : "󰂄") : (UPower.onBattery ? "B" : "⚡")
                hint: parent.percent + "% · " + (UPower.onBattery ? "on battery" : "plugged in")
                accent: parent.low ? Theme.amber : Theme.strataAccent
                onClicked: Understory.toggle(root.outputName)
            }
            Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: parent.percent; textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: 9; color: parent.low ? Theme.amber : Theme.strataMuted }
        }
        Rectangle { width: parent.width; height: 1; color: Qt.alpha(Theme.strataGrain, .5) }
        // The clock, stacked: hours over minutes.
        StrataButton {
            objectName: "understoryBarClock"
            visible: Config.moduleEnabled("clock")
            width: parent.width; height: 40
            hint: Config.formatDate(clock.date, false)
            enabled: !ShellState.locked
            background: Item {}
            contentItem: Column {
                spacing: -2
                Text { width: foot.width; horizontalAlignment: Text.AlignHCenter; text: Config.clock24 ? Qt.formatDateTime(clock.date, "HH") : Qt.formatDateTime(clock.date, "h AP").split(" ")[0]; textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: Theme.small + 1; font.weight: Font.DemiBold; color: Theme.strataText }
                Text { width: foot.width; horizontalAlignment: Text.AlignHCenter; text: Qt.formatDateTime(clock.date, "mm"); textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: Theme.small + 1; color: Theme.strataText }
            }
            onClicked: { if (Config.saved.canopyEnabled) Canopy.toggleTopic("calendar", root.outputName); else Understory.toggle(root.outputName); }
            readonly property var provider: root.sideAnchor(this)
            function publish() { if (visible) Canopy.setAnchorProvider("calendar", root.outputName, provider); else Canopy.clearAnchorProvider("calendar", root.outputName, provider); }
            Component.onCompleted: Qt.callLater(publish)
            Component.onDestruction: Canopy.clearAnchorProvider("calendar", root.outputName, provider)
            onVisibleChanged: Qt.callLater(publish)
        }
        BarMark {
            objectName: "understoryBarPower"
            text: root.glyph("󰐥", "⏻"); hint: "Power & session"
            anchorTopic: "power"
            accent: Theme.ember
            onClicked: { if (Config.saved.canopyEnabled) Canopy.open("power", root.outputName); else ShellState.toggle("power"); }
        }
    }
}
