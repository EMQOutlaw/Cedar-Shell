import QtQuick
import QtQuick.Shapes
import ".."
import "../services"

// The CEDAR shield: a geometric shield holding a cedar's branching structure.
// A trunk rises from the base; one branch per protection leaves it,
// alternately left and right, bottom to top in Shield's order. Segment colour
// is the protection's state (low contrast off, cedar green on, amber to
// check, ember failed). On show the outline settles in, the branches light
// outward in sequence and the mark holds still (about 800 ms, once). When a
// protection turns on, one short light travels from the trunk's base up to
// its branch and stops. Nothing here runs while nothing changes.
Item {
    id: root
    property var protections: Shield.protections
    property bool compact: false
    property bool interactive: true
    property bool revealOnShow: false
    property string highlight: ""       // a protection id drawn alone, for a detail view
    implicitWidth: compact ? 120 : 220
    implicitHeight: implicitWidth * 1.18
    readonly property real cx: width / 2
    readonly property real crown: height * .06
    readonly property real base: height * .94
    readonly property real halfWidth: width * .42
    readonly property int count: protections.length
    // 0 → 1 once on show; branches light in order as it passes them.
    property real reveal: revealOnShow && !Theme.reducedMotion ? 0 : 1
    Component.onCompleted: if (revealOnShow && !Theme.reducedMotion) revealAnimation.start()
    NumberAnimation { id: revealAnimation; target: root; property: "reveal"; from: 0; to: 1; duration: 800; easing.type: Easing.OutCubic }
    function tone(state) { return state === "on" ? Theme.success : state === "warn" ? Theme.warning : state === "fail" ? Theme.danger : state === "working" ? Theme.teal : Qt.alpha(Theme.teal, .22); }
    function branchY(i) { return base - height * .14 - i * (height * .62 / Math.max(1, count)); }
    function branchLength(i) { return halfWidth * (.78 - i * .045); }
    function side(i) { return i % 2 === 0 ? -1 : 1; }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        opacity: .35 + .65 * Math.min(1, root.reveal * 2)
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
        ShapePath {
            strokeColor: Qt.alpha(Theme.green, .55); strokeWidth: 2; fillColor: "transparent"; capStyle: ShapePath.RoundCap
            startX: root.cx; startY: root.base - root.height * .05
            PathLine { x: root.cx; y: root.crown + root.height * .16 }
        }
    }
    Repeater {
        model: root.count
        delegate: Item {
            id: branch
            required property int index
            readonly property var protection: root.protections[index]
            readonly property string state: protection ? protection.state : "unavailable"
            readonly property bool dimmed: root.highlight !== "" && protection && protection.id !== root.highlight
            readonly property real y0: root.branchY(index)
            readonly property real reach: root.branchLength(index)
            readonly property real dir: root.side(index)
            // Lights in sequence during the reveal: branch i turns on as reveal passes its share.
            readonly property real shown: Math.max(0, Math.min(1, (root.reveal * (root.count + 2) - index) / 2))
            property real light: 0
            anchors.fill: parent
            opacity: (dimmed ? .18 : 1) * (.25 + .75 * shown)
            onStateChanged: if (state === "on" && root.visible && root.interactive && !Theme.reducedMotion) travel.restart()
            SequentialAnimation {
                id: travel
                NumberAnimation { target: branch; property: "light"; from: 0; to: 1; duration: Theme.sweep * .6; easing.type: Easing.OutCubic }
                PauseAnimation { duration: 120 }
                NumberAnimation { target: branch; property: "light"; to: 0; duration: Theme.fast }
            }
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: root.tone(branch.state); strokeWidth: branch.state === "on" ? 2 : 1.5; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                    startX: root.cx; startY: branch.y0
                    PathQuad { x: root.cx + branch.dir * branch.reach; y: branch.y0 - root.height * .07; controlX: root.cx + branch.dir * branch.reach * .5; controlY: branch.y0 - root.height * .01 }
                }
            }
            Rectangle {
                visible: branch.light > 0
                width: 6; height: 6; radius: 3; color: Theme.white; opacity: .9
                x: root.cx - 3
                y: root.base - root.height * .05 - (root.base - root.height * .05 - branch.y0) * Math.min(1, branch.light * 1.6) - 3
            }
            Rectangle {
                visible: branch.light > .6
                width: 5; height: 5; radius: 2.5; color: Theme.success
                readonly property real t: Math.max(0, (branch.light - .6) / .4)
                x: root.cx + branch.dir * branch.reach * t - 2.5; y: branch.y0 - root.height * .07 * t - 2.5
            }
        }
    }
    Accessible.role: Accessible.Graphic
    Accessible.name: "Shield: " + Shield.onCount + " of " + root.count + " protections active"
}
