import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import ".."
import "../components"
import "../services"

// The Focus application's content: the session as a large timer inside the
// progress ring, its readings, the controls, what a session quiets, the
// exceptions, and the session history. One shared entrance clock; the only
// recurring work is the service's one-second tick while this window is open.
FocusScope {
    id: root
    signal closed()
    readonly property bool wide: width >= 820
    readonly property color accent: Focus.active ? (Focus.paused ? Theme.amber : Theme.green) : Theme.teal
    function tone(state) { return state === "active" || state === "restored" ? Theme.success : state === "failed" ? Theme.danger : state === "applying" ? Theme.teal : state === "unavailable" ? Theme.muted : Theme.inactive; }
    function word(state) { return ({ active: "Active", restored: "Restored", failed: "Failed", unavailable: "Unavailable", off: "Off", pending: "Waiting", applying: "Applying" })[state] || state; }
    function when(at) {
        const diff = Math.max(0, Date.now() - at), m = Math.floor(diff / 60000);
        return m < 1 ? "just now" : m < 60 ? m + " min ago" : m < 1440 ? Math.floor(m / 60) + " h ago" : Qt.formatDateTime(new Date(at), Config.clock24 ? "d MMM HH:mm" : "d MMM h:mm ap");
    }
    property int chosen: Config.saved.focusMinutes || 25

    property real reveal: 1
    function ease(start, span) { const t = Math.max(0, Math.min(1, (reveal - start) / span)); return 1 - Math.pow(1 - t, 3); }
    function beat(order, span = .4) { return ease(.06 * order, span); }
    function enter() { entrance.stop(); if (Theme.reducedMotion || Config.testMode) { reveal = 1; return; } reveal = 0; entrance.start(); }
    NumberAnimation { id: entrance; target: root; property: "reveal"; from: 0; to: 1; duration: 1050 }
    Connections { target: Theme; function onReducedMotionChanged() { if (Theme.reducedMotion) { entrance.stop(); root.reveal = 1; } } }
    Component.onCompleted: enter()
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape || (event.key === Qt.Key_W && event.modifiers & Qt.ControlModifier)) { root.closed(); event.accepted = true; }
        else if (event.key === Qt.Key_Space && !(event.modifiers & Qt.ControlModifier) && Focus.active) { Focus.toggle(); event.accepted = true; }
        else if (event.key === Qt.Key_Return && event.modifiers & Qt.ControlModifier) { if (Focus.active) Focus.end(); else Focus.start(root.chosen); event.accepted = true; }
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
    component Reading: ColumnLayout {
        property string label: ""
        property string value: ""
        property color valueTone: Theme.text
        property int order: 0
        spacing: 2
        opacity: root.beat(order, .35)
        Accessible.role: Accessible.StaticText
        Accessible.name: label + ": " + value
        GlowText { text: label.toUpperCase(); font.pixelSize: 10; font.letterSpacing: 1.4; color: Theme.muted }
        GlowText { text: value; font.family: Theme.labelFont; font.pixelSize: Math.round(18 * Theme.fontScale); font.weight: Font.DemiBold; color: valueTone; Layout.fillWidth: true; elide: Text.ElideRight }
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
            ColumnLayout {
                Layout.fillWidth: true; spacing: 12
                RowLayout {
                    Layout.fillWidth: true; spacing: 16
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 3
                        opacity: root.ease(0, .45)
                        transform: Translate { y: 6 * (1 - root.ease(0, .45)) }
                        GlowText { text: "FOCUS"; font.family: Theme.labelFont; font.pixelSize: Math.round(20 * Theme.fontScale); font.weight: Font.DemiBold; font.letterSpacing: 3 + 6 * (1 - root.ease(0, .6)); color: Theme.text }
                        GlowText { text: Focus.active ? (Focus.paused ? "Paused. The desktop stays quiet until you resume or end." : "The desktop is quiet. Notifications wait unless they are critical or excepted.") : "A timed session in which the desktop quiets itself, then puts everything back."; font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                    }
                    StatusPill { text: Focus.busy ? "Working" : Focus.active ? (Focus.paused ? "Paused" : "Focusing") : "Off"; tone: root.accent; opacity: root.ease(.1, .4); Layout.alignment: Qt.AlignTop }
                }
                Item { Layout.fillWidth: true; implicitHeight: 1
                    Rectangle { width: parent.width * root.ease(.08, .5); height: 1; color: Qt.alpha(Theme.teal, .28)
                        Rectangle { anchors.right: parent.right; width: Math.min(parent.width, 120); height: 1; color: Theme.green; opacity: .8 * (1 - root.ease(.5, .4)) } } }
            }
            // The session: the ring, the time, the readings, the controls.
            Frame {
                order: 1
                Layout.fillWidth: true
                topLineColor: root.accent
                stroke: Qt.alpha(root.accent, Focus.active ? .3 : .16)
                padding: 26
                GridLayout {
                    Layout.fillWidth: true; columns: root.wide ? 2 : 1; columnSpacing: 32; rowSpacing: 20
                    ProgressArc {
                        Layout.alignment: Qt.AlignHCenter; Layout.preferredWidth: 280; Layout.preferredHeight: 280
                        value: Focus.active ? Focus.fraction * root.ease(.15, .6) : root.ease(.15, .6) * 0
                        accent: root.accent
                        opacity: root.ease(.05, .5); scale: .92 + .08 * root.ease(.05, .6)
                        ColumnLayout {
                            anchors.centerIn: parent; spacing: 2
                            GlowText { Layout.alignment: Qt.AlignHCenter; text: Focus.active ? Focus.clock(Focus.remaining) : Focus.clock(root.chosen * 60); font.pixelSize: Math.round(52 * Theme.fontScale); color: Focus.active ? root.accent : Theme.text; glow: Focus.active }
                            GlowText { Layout.alignment: Qt.AlignHCenter; text: Focus.active ? (Focus.paused ? "PAUSED" : "REMAINING") : "READY"; font.pixelSize: 10; font.letterSpacing: 2; color: Theme.muted }
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true; Layout.alignment: Qt.AlignVCenter; spacing: 18
                        GridLayout {
                            Layout.fillWidth: true; columns: 2; columnSpacing: 24; rowSpacing: 14
                            Reading { label: "Session"; value: Focus.active ? Focus.minutes(Focus.planned) + " · started " + root.when(Focus.startedAt) : "Not started"; order: 3 }
                            Reading { label: "Ends"; value: Focus.active ? (Focus.paused ? "When resumed" : Qt.formatDateTime(new Date(Focus.deadline), Config.clock24 ? "HH:mm" : "h:mm ap")) : "—"; order: 4 }
                            Reading { label: "Held"; value: Focus.active ? String(Focus.held) : "—"; valueTone: Focus.held ? Theme.green : Theme.text; order: 5 }
                            Reading { label: "Interruptions"; value: Focus.active ? String(Focus.interruptions) : "—"; valueTone: Focus.interruptions ? Theme.amber : Theme.text; order: 6 }
                        }
                        // Presets only while nothing runs; the session's length is fixed once started.
                        ColumnLayout {
                            visible: !Focus.active; spacing: 6; opacity: root.beat(7)
                            GlowText { text: "LENGTH"; font.pixelSize: 10; font.letterSpacing: 1.4; color: Theme.muted }
                            ChoiceChips { options: [{ value: 15, label: "15 min" }, { value: 25, label: "25 min" }, { value: 50, label: "50 min" }, { value: 90, label: "90 min" }]; current: root.chosen; accessibleLabel: "Session length"; onChosen: v => { root.chosen = v; Config.set("focusMinutes", v); } }
                        }
                        RowLayout {
                            spacing: 8; opacity: root.beat(8)
                            StationButton { visible: !Focus.active; text: Focus.busy ? "Working…" : "Start Focus"; accent: Theme.green; checked: true; enabled: !Focus.busy; hint: "Ctrl+Enter"; onClicked: Focus.start(root.chosen) }
                            StationButton { visible: Focus.active; text: Focus.paused ? "Resume" : "Pause"; enabled: !Focus.busy; hint: "Space"; onClicked: Focus.toggle() }
                            StationButton { visible: Focus.active; text: Focus.busy ? "Working…" : "End session"; accent: Theme.amber; enabled: !Focus.busy; hint: "Ctrl+Enter"; onClicked: Focus.end() }
                        }
                        GlowText { visible: Focus.error !== ""; text: Focus.error; color: Theme.danger; font.pixelSize: Theme.small; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                    }
                }
            }
            GridLayout {
                Layout.fillWidth: true; columns: root.wide ? 2 : 1; columnSpacing: 12; rowSpacing: 12
                // What the session quiets: the live rows while on, the plan while off.
                Frame {
                    order: 2
                    Layout.fillWidth: true; Layout.alignment: Qt.AlignTop
                    SectionMark { text: Focus.active ? "QUIETED" : "WHAT FOCUS QUIETS" }
                    Repeater {
                        model: Focus.active || Focus.steps.length ? Focus.steps.filter(s => s.state !== "off") : Focus.registry
                        RowLayout {
                            required property var modelData
                            Layout.fillWidth: true; spacing: 10
                            Rectangle { width: 8; height: 8; radius: 4; color: modelData.state ? root.tone(modelData.state) : (modelData.enabled ? Theme.teal : Theme.muted); opacity: modelData.state === "active" || modelData.state === "restored" || modelData.enabled ? 1 : .5 }
                            GlowText { text: modelData.hud || modelData.label; color: Theme.text; Layout.fillWidth: true; elide: Text.ElideRight }
                            StatusPill { text: modelData.state ? root.word(modelData.state) : (modelData.enabled ? "Planned" : "Left alone"); tone: modelData.state ? root.tone(modelData.state) : (modelData.enabled ? Theme.teal : Theme.muted) }
                        }
                    }
                    GlowText { text: "Chosen in Settings › Notifications › Focus. CEDAR is this session's notification server, so a held popup is really held; a critical alert or an excepted app still reaches you and counts as an interruption."; font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                }
                Frame {
                    order: 3
                    Layout.fillWidth: true; Layout.alignment: Qt.AlignTop
                    SectionMark { text: "EXCEPTIONS" }
                    GlowText { text: "Applications whose notifications still show during Focus, by the name they announce, separated by commas."; font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                    StationField { Layout.fillWidth: true; text: Config.saved.focusAllowedApps || ""; placeholderText: "Signal, Thunderbird"; Accessible.name: "Focus exceptions"; onCommit: value => Config.set("focusAllowedApps", value) }
                    Flow { Layout.fillWidth: true; spacing: 6
                        Repeater { model: Focus.allowedApps; StatusPill { required property string modelData; text: modelData; tone: Theme.teal } } }
                }
            }
            Frame {
                order: 4
                Layout.fillWidth: true
                RowLayout { Layout.fillWidth: true
                    SectionMark { text: "SESSION HISTORY" }
                    Item { Layout.fillWidth: true }
                    GlowText { text: Focus.history.length + (Focus.history.length === 1 ? " SESSION" : " SESSIONS") + " · LAST 30 KEPT"; font.pixelSize: 9; font.letterSpacing: 1.2; color: Theme.muted } }
                Repeater {
                    model: Focus.history
                    Item {
                        id: entry
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true; implicitHeight: row.implicitHeight + 16
                        opacity: root.beat(5 + index * .5, .35)
                        Rectangle { visible: entry.index < Focus.history.length - 1; x: 3; y: 14; width: 1; height: parent.height - 14; color: Qt.alpha(Theme.teal, .18) }
                        Rectangle { x: 0; y: 9; width: 7; height: 7; radius: 4; color: entry.modelData.completed ? Theme.green : Theme.amber }
                        RowLayout {
                            id: row
                            x: 20; y: 4; width: parent.width - 20; spacing: 12
                            ColumnLayout { Layout.fillWidth: true; spacing: 2
                                GlowText { text: Focus.minutes(entry.modelData.actual) + (entry.modelData.completed ? " · completed" : " of " + Focus.minutes(entry.modelData.planned) + " · ended early"); color: Theme.text; Layout.fillWidth: true; elide: Text.ElideRight }
                                GlowText { text: entry.modelData.held + " held · " + entry.modelData.interruptions + (entry.modelData.interruptions === 1 ? " interruption" : " interruptions"); font.pixelSize: Theme.small; color: Theme.muted } }
                            GlowText { text: root.when(entry.modelData.endedAt); font.pixelSize: Theme.small; color: Theme.muted; Layout.alignment: Qt.AlignTop }
                        }
                    }
                }
                GlowText { visible: !Focus.history.length; text: "No sessions yet."; color: Theme.muted; font.pixelSize: Theme.small }
            }
            GlowText { text: "Keyboard: Ctrl+Enter starts or ends, Space pauses and resumes, Escape or Ctrl+W closes. The session carries on with the window closed and survives a shell restart."; font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap; opacity: root.beat(9) }
        }
    }
}
