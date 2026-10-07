import QtQuick
import QtQuick.Shapes
import ".."
import "../services"

// The CEDAR shield: a geometric shield holding a cedar's branching structure.
// A trunk rises from the base; seven branch pairs — fourteen segments — leave
// it alternately left and right, one pair per protection, bottom to top.
// Segment colour is the protection's state (low contrast off, cedar green on,
// amber to check, ember failed). When a protection turns on, one short light
// travels from the trunk's base up to its pair over about 400 ms and stops;
// the lit state afterwards is static. Nothing here runs while nothing changes.
Item {
    id: root
    property var protections: Shield.protections
    property bool compact: false
    implicitWidth: compact ? 120 : 220
    implicitHeight: implicitWidth * 1.18
    readonly property real cx: width / 2
    readonly property real crown: height * .06
    readonly property real base: height * .94
    readonly property real halfWidth: width * .42
    function tone(state) { return state === "on" ? Theme.green : state === "warn" ? Theme.amber : state === "fail" ? Theme.ember : state === "working" ? Theme.teal : Qt.alpha(Theme.teal, .22); }
    // Branch i (0 = lowest) leaves the trunk at a height and reaches out with a slight upward lift.
    function branchY(i) { return base - height * .12 - i * (height * .68 / Math.max(1, protections.length)); }
    function branchLength(i) { return halfWidth * (.72 - i * .07); }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        // The shield outline.
        ShapePath {
            strokeColor: Qt.alpha(Theme.teal, .45); strokeWidth: 1.5; fillColor: Qt.alpha(Theme.surface, .7)
            startX: root.cx; startY: root.crown
            PathLine { x: root.cx + root.halfWidth; y: root.crown + root.height * .12 }
            PathLine { x: root.cx + root.halfWidth; y: root.height * .52 }
            PathQuad { x: root.cx; y: root.base; controlX: root.cx + root.halfWidth * .9; controlY: root.height * .86 }
            PathQuad { x: root.cx - root.halfWidth; y: root.height * .52; controlX: root.cx - root.halfWidth * .9; controlY: root.height * .86 }
            PathLine { x: root.cx - root.halfWidth; y: root.crown + root.height * .12 }
            PathLine { x: root.cx; y: root.crown }
        }
        // The trunk.
        ShapePath {
            strokeColor: Qt.alpha(Theme.green, .55); strokeWidth: 2; fillColor: "transparent"; capStyle: ShapePath.RoundCap
            startX: root.cx; startY: root.base - root.height * .05
            PathLine { x: root.cx; y: root.crown + root.height * .16 }
        }
    }
    // Fourteen branch segments: two per protection.
    Repeater {
        model: root.protections.length
        delegate: Item {
            id: pair
            required property int index
            readonly property var protection: root.protections[index]
            readonly property string state: protection ? protection.state : "unavailable"
            readonly property real y0: root.branchY(index)
            readonly property real reach: root.branchLength(index)
            property real light: 0        // 0 → 1 as the illumination travels out, then back to 0
            anchors.fill: parent
            onStateChanged: if (state === "on" && root.visible && !Theme.reducedMotion) travel.restart()
            SequentialAnimation {
                id: travel
                NumberAnimation { target: pair; property: "light"; from: 0; to: 1; duration: Theme.sweep * .6; easing.type: Easing.OutCubic }
                PauseAnimation { duration: 120 }
                NumberAnimation { target: pair; property: "light"; to: 0; duration: Theme.fast }
            }
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: root.tone(pair.state); strokeWidth: pair.state === "on" ? 2 : 1.5; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                    startX: root.cx; startY: pair.y0
                    PathQuad { x: root.cx - pair.reach; y: pair.y0 - root.height * .07; controlX: root.cx - pair.reach * .5; controlY: pair.y0 - root.height * .01 }
                }
                ShapePath {
                    strokeColor: root.tone(pair.state); strokeWidth: pair.state === "on" ? 2 : 1.5; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                    startX: root.cx; startY: pair.y0
                    PathQuad { x: root.cx + pair.reach; y: pair.y0 - root.height * .07; controlX: root.cx + pair.reach * .5; controlY: pair.y0 - root.height * .01 }
                }
            }
            // The travelling light: up the trunk from the base, then out both branches.
            Rectangle {
                visible: pair.light > 0
                width: 6; height: 6; radius: 3; color: Theme.white
                x: root.cx - 3
                y: root.base - root.height * .05 - (root.base - root.height * .05 - pair.y0) * Math.min(1, pair.light * 1.6) - 3
                opacity: pair.light > 0 ? .9 : 0
            }
            Rectangle {
                visible: pair.light > .6
                width: 5; height: 5; radius: 2.5; color: Theme.green
                readonly property real t: Math.max(0, (pair.light - .6) / .4)
                x: root.cx - pair.reach * t - 2.5; y: pair.y0 - root.height * .07 * t - 2.5
            }
            Rectangle {
                visible: pair.light > .6
                width: 5; height: 5; radius: 2.5; color: Theme.green
                readonly property real t: Math.max(0, (pair.light - .6) / .4)
                x: root.cx + pair.reach * t - 2.5; y: pair.y0 - root.height * .07 * t - 2.5
            }
        }
    }
    Accessible.role: Accessible.Graphic
    Accessible.name: "Shield: " + Shield.onCount + " of " + root.protections.length + " protections active"
}
