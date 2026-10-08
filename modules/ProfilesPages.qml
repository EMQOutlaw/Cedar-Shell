import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import ".."
import "../components"
import "../services"

// The Profiles application's content: the active profile as a station card,
// the six profiles as a grid of chamfered tiles, and the Custom editor. One
// shared entrance clock (the Shield and Field Station pattern); nothing
// loops. Every tile and chip is a keyboard target.
FocusScope {
    id: root
    signal closed()
    readonly property int columns: width < 700 ? 1 : width < 1100 ? 2 : 3
    readonly property string current: Profiles.current
    readonly property var currentDef: Profiles.definition(current)
    readonly property color currentAccent: current ? Profiles.accentOf(current) : Theme.teal
    function tone(state) { return state === "active" || state === "restored" ? Theme.success : state === "failed" ? Theme.danger : state === "applying" ? Theme.teal : state === "unavailable" ? Theme.muted : Theme.inactive; }
    function word(state) { return ({ active: "Active", restored: "Restored", failed: "Failed", unavailable: "Unavailable", off: "Off", pending: "Waiting", applying: "Applying" })[state] || state; }

    // ---------------------------------------------------------- entrance
    property real reveal: 1
    function ease(start, span) { const t = Math.max(0, Math.min(1, (reveal - start) / span)); return 1 - Math.pow(1 - t, 3); }
    function beat(order, span = .4) { return ease(.06 * order, span); }
    function enter() { entrance.stop(); if (Theme.reducedMotion || Config.testMode) { reveal = 1; return; } reveal = 0; entrance.start(); }
    NumberAnimation { id: entrance; target: root; property: "reveal"; from: 0; to: 1; duration: 1050 }
    Connections { target: Theme; function onReducedMotionChanged() { if (Theme.reducedMotion) { entrance.stop(); root.reveal = 1; } } }
    Component.onCompleted: enter()
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape || (event.key === Qt.Key_W && event.modifiers & Qt.ControlModifier)) { root.closed(); event.accepted = true; }
        else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_6 && event.modifiers & Qt.ControlModifier) { const d = Profiles.definitions[event.key - Qt.Key_1]; if (d) Profiles.toggle(d.id); event.accepted = true; }
    }

    component Frame: ChamferFrame {
        property int order: 0
        property int padding: 20
        default property alias content: frameBody.data
        cut: 10; fill: Qt.alpha(Theme.surface, .88); stroke: Qt.alpha(Theme.teal, .16)
        topLine: true; topLineColor: Theme.teal
        implicitHeight: frameBody.implicitHeight + padding * 2
        opacity: root.beat(order)
        transform: Translate { y: 6 * (1 - root.beat(order)) }
        ColumnLayout { id: frameBody; anchors { left: parent.left; right: parent.right; top: parent.top; margins: padding } spacing: 10 }
    }
    // One profile: its accent on the top line and, when current, on the lit bottom line.
    component ProfileTile: StationButton {
        id: tile
        required property var modelData
        required property int index
        readonly property string pid: modelData.id
        readonly property bool current: root.current === pid
        readonly property var managed: Profiles.managed(pid)
        readonly property bool gaming: !!modelData.gaming
        Layout.fillWidth: true; Layout.preferredWidth: 1
        implicitHeight: 150
        padding: 16
        accent: Profiles.accentOf(pid)
        enabled: !Profiles.anyBusy
        opacity: root.beat(3 + index)
        scale: .96 + .04 * root.beat(3 + index)
        hint: current ? "Leave " + modelData.label : "Activate " + modelData.label + " (Ctrl+" + (index + 1) + ")"
        Accessible.name: modelData.label + (current ? ", active" : "") + ": " + modelData.line
        onClicked: Profiles.toggle(pid)
        background: ChamferFrame {
            cut: 9
            fill: tile.down ? Theme.elevated : tile.current ? Qt.alpha(tile.accent, .07) : tile.hovered ? Qt.alpha(Theme.elevated, .9) : Qt.alpha(Theme.surface, .88)
            stroke: tile.visualFocus ? Theme.green : tile.current ? Qt.alpha(tile.accent, .55) : tile.hovered ? Qt.alpha(tile.accent, .45) : Qt.alpha(Theme.teal, .16)
            strokeWidth: tile.visualFocus ? 2 : 1
            topLine: true; topLineColor: tile.accent; topLineFraction: tile.current ? .5 : .28
            line: tile.current; lineColor: tile.accent; lineFraction: .55
        }
        contentItem: ColumnLayout {
            spacing: 6
            RowLayout { Layout.fillWidth: true; spacing: 8
                Text { text: tile.modelData.label.toUpperCase(); textFormat: Text.PlainText; font.family: Theme.labelFont; font.pixelSize: Math.round(16 * Theme.fontScale); font.weight: Font.DemiBold; font.letterSpacing: 2; color: tile.current ? tile.accent : Theme.text; Layout.fillWidth: true; elide: Text.ElideRight }
                StatusPill { visible: tile.current; text: Profiles.anyBusy ? "Working" : "Active"; tone: tile.accent } }
            Text { Layout.fillWidth: true; text: tile.modelData.line; textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: Theme.small; color: Theme.muted; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight }
            Item { Layout.fillHeight: true }
            Flow { Layout.fillWidth: true; spacing: 6
                Repeater {
                    model: tile.gaming ? [{ key: "gaming", value: "" }] : tile.managed
                    Rectangle {
                        required property var modelData
                        width: chip.implicitWidth + 12; height: 18; radius: 9
                        color: Qt.alpha(tile.accent, .08); border.color: Qt.alpha(tile.accent, .3)
                        Text { id: chip; anchors.centerIn: parent; text: modelData.key === "gaming" ? "GAMING MODE" : (Profiles.ops[modelData.key].hud + " · " + Profiles.describe(modelData.key, modelData.value)).toUpperCase(); textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: 8; font.letterSpacing: 1; color: tile.accent }
                    }
                }
                Text { visible: !tile.gaming && !tile.managed.length; text: "NOTHING SET YET"; textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: 8; font.letterSpacing: 1; color: Theme.muted }
            }
        }
    }

    Flickable {
        id: scroll
        anchors.fill: parent
        contentWidth: width; contentHeight: body.implicitHeight + 56
        clip: true; boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: scroll.contentHeight > scroll.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }
        ColumnLayout {
            id: body
            x: 28; y: 28; width: scroll.width - 56
            spacing: 22
            // Title
            ColumnLayout {
                Layout.fillWidth: true; spacing: 12
                RowLayout {
                    Layout.fillWidth: true; spacing: 16
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 3
                        opacity: root.ease(0, .45)
                        transform: Translate { y: 6 * (1 - root.ease(0, .45)) }
                        GlowText { text: "PROFILES"; font.family: Theme.labelFont; font.pixelSize: Math.round(20 * Theme.fontScale); font.weight: Font.DemiBold; font.letterSpacing: 3 + 6 * (1 - root.ease(0, .6)); color: Theme.text }
                        GlowText { text: "One stance for the desktop at a time: applied through each setting's own provider, verified, and restored exactly when you leave."; font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                    }
                    StatusPill { text: Profiles.anyBusy ? "Working" : root.current ? Profiles.currentLabel : "No profile"; tone: root.currentAccent; opacity: root.ease(.1, .4); Layout.alignment: Qt.AlignTop }
                }
                Item { Layout.fillWidth: true; implicitHeight: 1
                    Rectangle { width: parent.width * root.ease(.08, .5); height: 1; color: Qt.alpha(Theme.teal, .28)
                        Rectangle { anchors.right: parent.right; width: Math.min(parent.width, 120); height: 1; color: Theme.green; opacity: .8 * (1 - root.ease(.5, .4)) } } }
            }
            // The active profile (level 1): what it changed, step by step.
            Frame {
                order: 1
                Layout.fillWidth: true
                topLineColor: root.currentAccent
                stroke: Qt.alpha(root.currentAccent, root.current ? .3 : .16)
                padding: 22
                RowLayout {
                    Layout.fillWidth: true; spacing: 16
                    ColumnLayout { Layout.fillWidth: true; spacing: 4
                        SectionMark { text: root.current ? "ACTIVE PROFILE" : "NO PROFILE"; tone: root.currentAccent }
                        GlowText { text: root.current ? Profiles.currentLabel : "The desktop is as you left it"; font.family: Theme.labelFont; font.pixelSize: Math.round(26 * Theme.fontScale); font.weight: Font.DemiBold; color: root.current ? root.currentAccent : Theme.text }
                        GlowText { text: root.current === "gaming" ? Gaming.summary + (Gaming.detail ? " · " + Gaming.detail : "") : root.current ? Profiles.summary + (Profiles.detail ? " · " + Profiles.detail : "") : "Choose a profile below. Each one is a set of changes CEDAR can verify and put back."; font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap } }
                    StationButton { visible: !!root.current; text: Profiles.anyBusy ? "Working…" : "Leave " + Profiles.currentLabel; accent: Theme.amber; enabled: !Profiles.anyBusy; onClicked: Profiles.toggle(root.current) }
                }
                // Rows of the last transaction: Gaming's or ours.
                Repeater {
                    model: root.current === "gaming" ? Gaming.steps.filter(s => s.state !== "off") : Profiles.steps
                    RowLayout {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true; spacing: 10
                        opacity: root.beat(3 + index * .5, .35)
                        Rectangle { width: 8; height: 8; radius: 4; color: root.tone(modelData.state); opacity: modelData.state === "active" || modelData.state === "restored" ? 1 : .6 }
                        GlowText { text: modelData.hud || modelData.label; color: Theme.text; Layout.preferredWidth: 200; elide: Text.ElideRight }
                        GlowText { text: modelData.detail; font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; elide: Text.ElideRight }
                        StatusPill { text: root.word(modelData.state); tone: root.tone(modelData.state) }
                    }
                }
                GlowText { visible: Profiles.error !== ""; text: Profiles.error; color: Theme.danger; font.pixelSize: Theme.small; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                GlowText { visible: !!root.current && Overrides.keysHeldBy("profile").some(k => (Overrides.entry(k, "profile") || {}).overridden); text: "You changed a held setting by hand; leaving the profile keeps your change."; color: Theme.muted; font.pixelSize: Theme.small; Layout.fillWidth: true; wrapMode: Text.WordWrap }
            }
            // The profiles (level 2 tiles).
            ColumnLayout {
                Layout.fillWidth: true; spacing: 10
                opacity: root.beat(2)
                RowLayout { Layout.fillWidth: true; SectionMark { text: "PROFILES" } Item { Layout.fillWidth: true } GlowText { text: "CTRL+1…6 TOGGLES"; font.pixelSize: 9; font.letterSpacing: 1.2; color: Theme.muted } }
                GridLayout {
                    Layout.fillWidth: true; columns: root.columns; columnSpacing: 12; rowSpacing: 12; uniformCellWidths: true
                    Repeater { model: Profiles.definitions; ProfileTile {} }
                }
            }
            // Custom: the user's own set, operation by operation.
            Frame {
                order: 9
                Layout.fillWidth: true
                readonly property var custom: Profiles.definition("custom") || ({ ops: {}, accent: "green" })
                topLineColor: Profiles.accentOf("custom")
                RowLayout { Layout.fillWidth: true
                    SectionMark { text: "CUSTOM PROFILE"; tone: Profiles.accentOf("custom") }
                    Item { Layout.fillWidth: true }
                    GlowText { text: "SAVED IN ~/.config/cedar/profiles.json"; font.pixelSize: 9; font.letterSpacing: 1.2; color: Theme.muted } }
                GlowText { text: "Choose what Custom changes. “Leave” means the profile does not touch that setting."; font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                Repeater {
                    model: Profiles.opOrder
                    RowLayout {
                        id: opRow
                        required property string modelData
                        readonly property var op: Profiles.ops[modelData]
                        readonly property var value: (Profiles.definition("custom") || { ops: {} }).ops[modelData]
                        readonly property bool set: value !== undefined && value !== null
                        readonly property var scenes: (AudioInstruments.data.scenes || []).map(s => ({ value: s.name, label: s.name }))
                        Layout.fillWidth: true; spacing: 12
                        GlowText { text: opRow.op.label; color: Theme.text; Layout.preferredWidth: 150; elide: Text.ElideRight }
                        ChoiceChips {
                            Layout.fillWidth: true
                            accessibleLabel: "Custom: " + opRow.op.label
                            enabled: !Profiles.anyBusy
                            options: [{ value: "__leave", label: "Leave" }].concat(opRow.op.kind === "bool" ? [{ value: false, label: "Off" }, { value: true, label: "On" }] : opRow.op.kind === "choice" ? opRow.op.options : opRow.scenes)
                            current: opRow.set ? opRow.value : "__leave"
                            onChosen: v => Profiles.setCustomOp(opRow.modelData, v === "__leave" ? null : v)
                        }
                        GlowText { visible: opRow.op.kind === "scene" && !opRow.scenes.length; text: "No saved audio scenes"; font.pixelSize: Theme.small; color: Theme.muted }
                    }
                }
                RowLayout { Layout.fillWidth: true; spacing: 12; Layout.topMargin: 6
                    GlowText { text: "Accent"; color: Theme.text; Layout.preferredWidth: 150 }
                    Row { spacing: 8
                        Repeater {
                            model: ["green", "teal", "moss", "blue", "violet", "amber", "brightGreen"]
                            AbstractButton {
                                required property string modelData
                                readonly property bool chosen: (Profiles.definition("custom") || {}).accent === modelData
                                implicitWidth: 28; implicitHeight: 28
                                activeFocusOnTab: true
                                Accessible.name: "Custom accent " + modelData
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                onClicked: Profiles.setCustomAccent(modelData)
                                background: Rectangle { radius: 14; color: Qt.alpha(Profiles.accent(parent.modelData), parent.chosen ? .35 : .12); border.width: parent.visualFocus || parent.chosen ? 2 : 1; border.color: parent.visualFocus ? Theme.green : Profiles.accent(parent.modelData)
                                    Rectangle { anchors.centerIn: parent; width: 10; height: 10; radius: 5; color: Profiles.accent(parent.parent.modelData) } }
                            }
                        }
                    }
                }
            }
            GlowText { text: "Gaming is Gaming Mode: Super+G, the Gaming tile and GameMode detection keep working, and its own settings stay in Settings › Power & Lock. Keyboard: Ctrl+1…6 toggle a profile, Escape or Ctrl+W closes."; font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap; opacity: root.beat(10) }
        }
    }
}
