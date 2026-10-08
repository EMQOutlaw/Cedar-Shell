import QtQuick
import ".."
import "../services"
// The Audio Canopy's spectrum: 24 real CAVA bands from the shared Pulse feed,
// held only while this instrument is shown.
Rectangle {
    id: root
    property bool active: false
    readonly property var levels: Pulse.levels
    readonly property string error: Pulse.error
    implicitHeight: 76
    color: Theme.transparent
    readonly property bool holding: active && visible && !Theme.reducedMotion && !Config.testMode
    onHoldingChanged: holding ? Pulse.hold() : Pulse.release()
    Component.onCompleted: if (holding) Pulse.hold()
    Component.onDestruction: if (holding) Pulse.release()
    Row {
        anchors.fill: parent; spacing: 3
        Repeater {
            model: 24
            Rectangle {
                required property int index
                width: (root.width - 69) / 24; height: Math.max(1, (root.levels[index] || 0) * (root.height - 18)); y: root.height - height
                radius: 2; color: Qt.alpha(Theme.teal, .55)
                Behavior on height { enabled: root.active && !Theme.reducedMotion; NumberAnimation { duration: 40; easing.type: Easing.Linear } }
                Behavior on y { enabled: root.active && !Theme.reducedMotion; NumberAnimation { duration: 40; easing.type: Easing.Linear } }
            }
        }
    }
    GlowText { visible: root.error !== ""; text: root.error; color: Theme.muted; width: parent.width; wrapMode: Text.WordWrap; font.pixelSize: 10 }
}
