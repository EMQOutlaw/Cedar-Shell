import QtQuick
import QtQuick.Shapes
import ".."

// A foldback binder clip seen from the front, gripping the top edge of the
// paper at y = 26: the back wire handle, the clip body, the front wire handle
// running over the body, and the rolled jaw lip the wire tucks into. Its metal
// is CEDAR's own dark surfaces, so it belongs to the shell it floats over.
//
// Derived from Field Notes by OldJobobo (MIT, see licenses/Field-Notes-MIT.txt).
Item {
    id: root

    property bool hovered: false
    // Picked up: the clip rises a little off the paper while the board is dragged.
    property bool lifted: false
    // The paper's rotation, so the clip sits along its tilted edge.
    property real tilt: 0
    property QtObject theme
    readonly property real cx: width / 2
    readonly property color wire: lifted || hovered ? Theme.text : Theme.muted
    readonly property color wireShadow: Qt.alpha(Theme.background, .9)
    readonly property color bodyEdge: Theme.background
    readonly property color bodyLight: Theme.elevated
    readonly property color bodyMid: Theme.surface
    readonly property color bodyDark: Theme.background
    readonly property color spineLight: Qt.alpha(Theme.muted, .7)

    implicitWidth: 120
    implicitHeight: 50

    transform: Rotation {
        origin.x: root.cx
        origin.y: 26
        angle: root.tilt
    }

    // Soft shadow under the body: an offset copy, no render layer.
    Rectangle {
        x: root.cx - 50 + 1
        y: (root.lifted ? -1 : 0) + 27
        width: 100
        height: 20
        radius: 3
        color: root.theme ? root.theme.shadowSoft : Qt.rgba(0, 0, 0, .18)
    }

    Item {
        width: parent.width
        height: parent.height
        y: root.lifted ? -1 : 0

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            // Back handle: its legs disappear behind the body.
            ShapePath {
                strokeColor: root.wireShadow
                strokeWidth: 3.6
                fillColor: Theme.transparent
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                startX: root.cx - 28
                startY: 30

                PathLine { x: root.cx - 18.8; y: 9.5 }
                PathQuad { x: root.cx - 14; y: 5; controlX: root.cx - 19.6; controlY: 5 }
                PathLine { x: root.cx + 14; y: 5 }
                PathQuad { x: root.cx + 18.8; y: 9.5; controlX: root.cx + 19.6; controlY: 5 }
                PathLine { x: root.cx + 28; y: 30 }
            }
            ShapePath {
                strokeColor: Qt.alpha(Theme.muted, .7)
                strokeWidth: 1.8
                fillColor: Theme.transparent
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                startX: root.cx - 28
                startY: 30

                PathLine { x: root.cx - 18.8; y: 9.5 }
                PathQuad { x: root.cx - 14; y: 5; controlX: root.cx - 19.6; controlY: 5 }
                PathLine { x: root.cx + 14; y: 5 }
                PathQuad { x: root.cx + 18.8; y: 9.5; controlX: root.cx + 19.6; controlY: 5 }
                PathLine { x: root.cx + 28; y: 30 }
            }

            // Body: narrower at the folded spine, which stands just above the paper edge.
            ShapePath {
                strokeColor: root.bodyEdge
                strokeWidth: 1
                fillGradient: LinearGradient {
                    x1: 0
                    y1: 21
                    x2: 0
                    y2: 46

                    GradientStop { position: 0; color: root.bodyLight }
                    GradientStop { position: 0.22; color: root.bodyMid }
                    GradientStop { position: 1; color: root.bodyDark }
                }
                startX: root.cx - 50
                startY: 44

                PathLine { x: root.cx - 43; y: 24 }
                PathQuad { x: root.cx - 38.5; y: 21; controlX: root.cx - 42; controlY: 21 }
                PathLine { x: root.cx + 38.5; y: 21 }
                PathQuad { x: root.cx + 43; y: 24; controlX: root.cx + 42; controlY: 21 }
                PathLine { x: root.cx + 50; y: 44 }
                PathLine { x: root.cx - 50; y: 44 }
            }

            // Light catching the rounded spine.
            ShapePath {
                strokeColor: root.spineLight
                strokeWidth: 1
                fillColor: Theme.transparent
                capStyle: ShapePath.RoundCap
                startX: root.cx - 37
                startY: 22.5

                PathLine { x: root.cx + 37; y: 22.5 }
            }

            // Front handle, running over the body into the jaw lip.
            ShapePath {
                strokeColor: root.wireShadow
                strokeWidth: 3.8
                fillColor: Theme.transparent
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                startX: root.cx - 34
                startY: 44

                PathLine { x: root.cx - 21.8; y: 6.4 }
                PathQuad { x: root.cx - 16.6; y: 1.6; controlX: root.cx - 22.8; controlY: 1.6 }
                PathLine { x: root.cx + 16.6; y: 1.6 }
                PathQuad { x: root.cx + 21.8; y: 6.4; controlX: root.cx + 22.8; controlY: 1.6 }
                PathLine { x: root.cx + 34; y: 44 }
            }
            ShapePath {
                strokeColor: root.wire
                strokeWidth: 2
                fillColor: Theme.transparent
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                startX: root.cx - 34
                startY: 44

                PathLine { x: root.cx - 21.8; y: 6.4 }
                PathQuad { x: root.cx - 16.6; y: 1.6; controlX: root.cx - 22.8; controlY: 1.6 }
                PathLine { x: root.cx + 16.6; y: 1.6 }
                PathQuad { x: root.cx + 21.8; y: 6.4; controlX: root.cx + 22.8; controlY: 1.6 }
                PathLine { x: root.cx + 34; y: 44 }
            }
        }

        // Rolled jaw lip pressing on the paper.
        Rectangle {
            x: root.cx - 52
            y: 42
            width: 104
            height: 6
            radius: 3
            gradient: Gradient {
                GradientStop { position: 0; color: root.bodyLight }
                GradientStop { position: 0.4; color: root.bodyMid }
                GradientStop { position: 1; color: root.bodyDark }
            }
        }
    }
}
