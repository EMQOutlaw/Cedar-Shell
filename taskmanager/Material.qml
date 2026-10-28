import QtQuick
import QtQuick.Shapes
// Standalone rendering of StrataBarFrame/DropFrame: foundation, partial inner
// grain contour, asymmetric cut and a quiet edge. No Quickshell service graph.
Item {
    id: root
    property color fill: TM.surface
    property color accent: TM.accent
    property bool active: false
    property bool alert: false
    property bool grain: false
    property bool texture: false
    property real cut: Math.min(10, width/4, height/4)
    Shape {
        anchors.fill: parent
        ShapePath {
            strokeWidth: 1; strokeColor: Qt.alpha(root.active ? root.accent : TM.border, root.active ? .45 : .36)
            fillColor: root.fill
            startX: root.cut; startY: .5
            PathLine { x: root.width-.5; y: .5 }
            PathLine { x: root.width-.5; y: root.height-root.cut }
            PathLine { x: root.width-root.cut; y: root.height-.5 }
            PathLine { x: .5; y: root.height-.5 }
            PathLine { x: .5; y: root.cut }
            PathLine { x: root.cut; y: .5 }
        }
        ShapePath {
            strokeWidth: 1; strokeColor: Qt.alpha(TM.border, root.grain && TM.effects ? .22 : 0); fillColor: "transparent"
            startX: root.cut+3; startY: 3
            PathLine { x: root.width*.42; y: 3 }
            PathMove { x: root.width-3; y: root.height*.5 }
            PathLine { x: root.width-3; y: root.height-root.cut-1 }
            PathLine { x: root.width-root.cut-1; y: root.height-3 }
            PathLine { x: root.width*.58; y: root.height-3 }
        }
    }
    Image { anchors.fill: parent; anchors.margins: 12; visible: root.texture && TM.effects; source: "grain.svg"; fillMode: Image.Tile; opacity: .025 }
    LivingEdge { x: root.cut; width: Math.min(root.width*.45, 190); active: root.active; signalOn: root.alert; accent: root.alert ? TM.warning : root.accent }
}
