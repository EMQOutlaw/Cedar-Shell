import QtQuick
import QtQuick.Shapes
import ".."

// A restrained progress ring: a faint full circle, twelve short ticks like
// branch stubs, and the lit arc from the top. Retained vector geometry, so a
// value change re-renders one path and no canvas; nothing animates on its
// own. Children sit in the middle (a timer, a reading).
Item {
    id: root
    property real value: 0           // 0 … 1
    property color accent: Theme.green
    property real thickness: 4
    property bool ticks: true
    default property alias content: centre.data
    implicitWidth: 240
    implicitHeight: 240
    readonly property real radius: Math.max(0, Math.min(width, height) / 2 - thickness - 10)
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: root.thickness; strokeColor: Qt.alpha(root.accent, .12); fillColor: Theme.transparent; capStyle: ShapePath.FlatCap
            PathAngleArc { centerX: root.width / 2; centerY: root.height / 2; radiusX: root.radius; radiusY: root.radius; startAngle: -90; sweepAngle: 360 }
        }
        ShapePath {
            strokeWidth: root.thickness; strokeColor: root.accent; fillColor: Theme.transparent; capStyle: ShapePath.RoundCap
            PathAngleArc { centerX: root.width / 2; centerY: root.height / 2; radiusX: root.radius; radiusY: root.radius; startAngle: -90; sweepAngle: 360 * Math.max(0, Math.min(1, root.value)) }
        }
    }
    Repeater {
        model: root.ticks ? 12 : 0
        Rectangle {
            required property int index
            readonly property bool passed: index / 12 < root.value
            width: 1; height: index % 3 === 0 ? 10 : 6; radius: .5
            color: passed ? root.accent : Qt.alpha(root.accent, .35)
            opacity: passed ? .9 : .6
            x: root.width / 2 - .5; y: root.height / 2 - root.radius - root.thickness - 4 - height
            transformOrigin: Item.Bottom
            transform: Rotation { origin.x: .5; origin.y: parent.height + root.radius + root.thickness + 4; angle: parent.index * 30 }
        }
    }
    Item { id: centre; anchors.centerIn: parent; width: root.radius * 1.5; height: root.radius * 1.5 }
}
