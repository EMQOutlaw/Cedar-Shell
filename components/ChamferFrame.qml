import QtQuick
import QtQuick.Shapes
import ".."
// The Core pill's silhouette: short cuts top-left and bottom-right, long cuts on
// the other two corners. Optional ember line along the bottom edge.
Item {
    id: root
    property real cut: 9
    readonly property real longCut: Math.round(cut * 16 / 9)
    property color fill: Qt.alpha(Theme.background, Math.max(.94, Config.barOpacity))
    property color stroke: Qt.alpha(Theme.teal, .15)
    property real strokeWidth: 1
    property bool line: false
    property color lineColor: Theme.teal
    property real lineFraction: .7
    property real lineOpacity: .85
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: root.strokeWidth
            strokeColor: root.stroke
            fillColor: root.fill
            startX: 0; startY: root.cut
            PathLine { x: root.cut; y: 0 }
            PathLine { x: root.width - root.longCut; y: 0 }
            PathLine { x: root.width; y: root.longCut }
            PathLine { x: root.width; y: root.height - root.cut }
            PathLine { x: root.width - root.cut; y: root.height }
            PathLine { x: root.longCut; y: root.height }
            PathLine { x: 0; y: root.height - root.longCut }
            PathLine { x: 0; y: root.cut }
        }
    }
    Rectangle {
        visible: root.line
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom; anchors.bottomMargin: 2
        width: (root.width - 2 * root.longCut) * root.lineFraction
        height: 2; radius: 1
        color: root.lineColor; opacity: root.lineOpacity
        Behavior on width { enabled: !Theme.reducedMotion; NumberAnimation { duration: Theme.transition; easing.type: Easing.OutCubic } }
    }
}
