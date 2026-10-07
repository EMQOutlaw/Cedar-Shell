import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../services"

// The Gaming Mode preparation card: CEDAR GAMING, what it is doing, one row
// per optimization that moves as the backend verifies it, and a count. It
// reads Gaming.steps and nothing else; no timers, no polling, no loops. The
// entrance (opacity 0 → 1, scale .96 → 1) and the exit (→ 0, → .98) are
// functional transitions gated on the user's Reduced Motion preference, not
// on the gaming quality level this card is announcing. One emblem pulse on
// entry and one sweep along the top edge on completion; then it is still.
Item {
    id: root
    implicitWidth: 400
    implicitHeight: frame.height + 12
    readonly property bool functional: !Config.saved.reducedMotion
    readonly property bool leave: Gaming.hudMode === "leave"
    readonly property bool settled: Gaming.hudSettled
    readonly property bool forGame: Gaming.trigger === "gamemode" && !leave
    readonly property var rows: Gaming.steps.filter(s => s.state !== "off")
    readonly property int failed: Gaming.failures.length
    readonly property string heading: settled ? (leave ? "Gaming Mode Ended" : "Gaming Mode Ready") : leave ? "Restoring system…" : forGame ? "Preparing for" : "Preparing system…"
    readonly property string footer: !settled ? Gaming.readyCount + " / " + Gaming.plannedCount + (leave ? " restored" : " ready")
        : leave ? (failed ? Gaming.readyCount + " / " + Gaming.plannedCount + " restored" : "System restored")
        : failed ? Gaming.readyCount + " / " + Gaming.plannedCount + " optimizations" : "Gaming Mode Active"
    readonly property color accent: settled ? (failed ? Theme.warning : Theme.success) : Theme.teal
    property bool entered: false
    readonly property bool shown: entered && !Gaming.hudClosing
    opacity: shown ? 1 : 0
    scale: shown ? 1 : (entered ? .98 : .96)
    Behavior on opacity { enabled: root.functional; NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    Behavior on scale { enabled: root.functional; NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    Component.onCompleted: Qt.callLater(() => root.entered = true)
    onSettledChanged: if (settled) sweep.restart()
    onHeadingChanged: if (functional) headingFade.restart()

    function glyph(state) { return ({ pending: "○", applying: "◌", active: "✓", restored: "✓", failed: "!", unavailable: "–", observing: "◦" })[state] || "○"; }
    function tone(state) {
        return state === "active" || state === "restored" ? Theme.success : state === "applying" || state === "observing" ? Theme.teal
            : state === "failed" ? Theme.warning : Theme.inactive;
    }
    function aside(row) {
        if (row.state === "unavailable") return row.id === "gamemode" ? "Not installed" : "Not available";
        if (row.state === "failed") return root.leave ? "Could not restore" : "Could not apply";
        if (row.state === "observing") return "Watching";
        return "";
    }
    function label(row) { return root.leave && row.state === "restored" ? (row.restored || row.hud + " restored") : row.hud; }

    // Soft shadow: the same silhouette, a little larger and darker, no effects.
    ChamferFrame { anchors.fill: frame; anchors.margins: -5; cut: 14; fill: Qt.alpha(Theme.background, .38); stroke: Theme.transparent; strokeWidth: 0 }
    ChamferFrame {
        id: frame
        width: root.width; height: column.implicitHeight + 40
        cut: 12
        fill: Qt.alpha(Theme.surface, .96)
        stroke: Qt.alpha(root.accent, root.settled ? .5 : .28)
        line: true; lineColor: root.accent; lineFraction: .45; lineOpacity: .7
        Behavior on stroke { enabled: root.functional; ColorAnimation { duration: Theme.transition } }
        // Completion sweep along the top edge, once.
        Rectangle {
            id: topSweep
            x: frame.cut; y: 0; height: 1; width: 0; color: root.accent; opacity: .9
            NumberAnimation { id: sweep; target: topSweep; property: "width"; from: 0; to: frame.width - frame.cut - frame.longCut; duration: root.functional ? 420 : 0; easing.type: Easing.OutCubic }
        }
        ColumnLayout {
            id: column
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
            spacing: 6
            RowLayout {
                Layout.alignment: Qt.AlignHCenter; spacing: 10
                // The emblem: a cedar-green chamfered mark with a lit centre. One pulse on entry.
                Item {
                    id: emblem
                    implicitWidth: 16; implicitHeight: 16
                    Rectangle { anchors.centerIn: parent; width: 11; height: 11; rotation: 45; radius: 2; color: Theme.transparent; border.width: 1.5; border.color: root.accent }
                    Rectangle { anchors.centerIn: parent; width: 4; height: 4; radius: 2; color: root.accent }
                    SequentialAnimation { id: pulse; running: root.functional && root.entered; NumberAnimation { target: emblem; property: "scale"; to: 1.25; duration: 160; easing.type: Easing.OutCubic } NumberAnimation { target: emblem; property: "scale"; to: 1; duration: 220; easing.type: Easing.OutCubic } }
                }
                Text { text: "CEDAR GAMING"; textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: 11; font.letterSpacing: 2.2; color: root.accent }
            }
            GlowText {
                id: headingText
                Layout.fillWidth: true; Layout.topMargin: 6
                text: root.heading; horizontalAlignment: Text.AlignHCenter
                font.family: Theme.labelFont; font.pixelSize: Math.round(19 * Theme.fontScale); font.weight: Font.DemiBold
                color: Theme.text; elide: Text.ElideRight
                NumberAnimation { id: headingFade; target: headingText; property: "opacity"; from: .35; to: 1; duration: 160; easing.type: Easing.OutCubic }
            }
            GlowText {
                visible: root.forGame && !root.settled
                Layout.fillWidth: true
                text: Gaming.gameName || "game"; horizontalAlignment: Text.AlignHCenter
                font.family: Theme.labelFont; font.pixelSize: Math.round(16 * Theme.fontScale); color: Theme.teal; elide: Text.ElideRight
            }
            ColumnLayout {
                Layout.fillWidth: true; Layout.topMargin: 10; Layout.leftMargin: 18; Layout.rightMargin: 18
                spacing: 5
                Repeater {
                    model: root.rows
                    RowLayout {
                        id: row
                        required property var modelData
                        readonly property color tone: root.tone(modelData.state)
                        readonly property bool quiet: modelData.state === "unavailable" || modelData.state === "pending"
                        Layout.fillWidth: true; spacing: 10
                        Text {
                            text: root.glyph(row.modelData.state); textFormat: Text.PlainText
                            font.family: Theme.dataFont; font.pixelSize: 13; color: row.tone
                            Layout.preferredWidth: 16; horizontalAlignment: Text.AlignHCenter
                            Behavior on color { enabled: root.functional; ColorAnimation { duration: 140 } }
                        }
                        GlowText {
                            text: root.label(row.modelData); Layout.fillWidth: true; elide: Text.ElideRight
                            font.family: Theme.labelFont; font.pixelSize: Math.round(14 * Theme.fontScale)
                            color: row.quiet ? Theme.muted : Theme.text
                            Behavior on color { enabled: root.functional; ColorAnimation { duration: 140 } }
                        }
                        Text {
                            visible: text !== ""; text: root.aside(row.modelData); textFormat: Text.PlainText
                            font.family: Theme.dataFont; font.pixelSize: 9; font.letterSpacing: 1.1; color: row.tone; opacity: .85
                        }
                    }
                }
            }
            Text {
                Layout.fillWidth: true; Layout.topMargin: 10
                text: root.footer; textFormat: Text.PlainText; horizontalAlignment: Text.AlignHCenter
                font.family: Theme.dataFont; font.pixelSize: 11; font.letterSpacing: 1.2
                color: root.settled ? root.accent : Theme.muted
                Behavior on color { enabled: root.functional; ColorAnimation { duration: Theme.transition } }
            }
        }
    }
}
