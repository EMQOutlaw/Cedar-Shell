import QtQuick
import ".."
import "../services"

// Canopy Pulse: thin strokes in the bar that follow real audio levels while
// something plays. Twelve strokes, each the average of two CAVA bands, with
// rounded ends and heights that swell toward the middle like a canopy. The
// feed is shared (services/Pulse.qml) and held only while this is shown and
// allowed; on silence the strokes rest at a sliver and the feed keeps its
// own cadence. Without CAVA the strip shows nothing and says why in its
// accessible name; it never invents a level.
Item {
    id: root
    property bool active: visible
    property color tone: Theme.teal
    property int strokes: 16
    implicitWidth: strokes * 6 - 3
    implicitHeight: 22
    readonly property bool fed: Pulse.available && Pulse.levels.length === 24
    readonly property var profile: [.4, .5, .62, .74, .86, .95, 1, 1, 1, 1, .95, .86, .74, .62, .5, .4]
    onActiveChanged: active ? Pulse.hold() : Pulse.release()
    Component.onCompleted: if (active) Pulse.hold()
    Component.onDestruction: if (active) Pulse.release()
    function level(i) {
        if (!fed) return 0;
        const k = Math.floor(i * 24 / root.strokes), a = Pulse.levels[k] || 0, b = Pulse.levels[Math.min(23, k + 1)] || 0;
        return Math.pow(Math.min(1, (a + b) / 2), .65);
    }
    Row {
        anchors.fill: parent
        spacing: 3
        Repeater {
            model: root.strokes
            Rectangle {
                required property int index
                readonly property real value: root.level(index) * root.profile[index]
                width: 3; radius: 1.5
                anchors.verticalCenter: parent.verticalCenter
                height: Math.max(2, Math.round(value * root.height))
                color: Qt.alpha(value > .75 ? Theme.brightGreen : root.tone, .45 + .55 * value)
                Behavior on height { enabled: root.active && !Theme.reducedMotion; NumberAnimation { duration: 50 } }
            }
        }
    }
    Accessible.role: Accessible.Graphic
    Accessible.name: root.fed ? "Canopy Pulse, audio levels" : Pulse.available ? "Canopy Pulse, waiting for audio" : "Canopy Pulse unavailable: " + Pulse.error
}
