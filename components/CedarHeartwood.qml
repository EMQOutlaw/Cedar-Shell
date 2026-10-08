import QtQuick
import QtQuick.Shapes
import ".."
import "../services"

// CEDAR's signature instrument: the cross-section of a cedar. The trunk and
// branches of the shield mark at the heart, three growth rings of six, nine
// and twelve segments with cutouts between them, a soft glow behind. Each
// ring is one dashed arc path; turning a ring is a dash-offset animation and
// the light that runs the outer ring is a second short dash on the same
// circle. Every motion is a state or an event:
//   awaken()     the rings spin and settle into place from a spread (shell start)
//   hovered      the middle ring turns slowly while the pointer stays, the glow rises
//   pulse()      a bloom: the whole instrument swells and springs back while a
//                light runs the outer ring (click)
//   ripple()     a ring expands outward and fades (a signal arriving)
//   unfolding    the rings separate radially and settle (a panel growing from the pill)
//   gaming       the outer ring brightens, completes one slow turn and locks
//   focus        the rings draw inward and quieten
//   warning      one outer segment turns amber and flares twice
Item {
    id: root
    property real size: 30
    property bool hovered: false
    property bool unfolding: false
    property string mode: "idle"        // idle | gaming | focus
    property bool warning: false
    property color accent: Theme.green
    property real intensity: 1
    readonly property bool live: VisualQuality.effects && intensity > 0
    width: size; height: size
    readonly property real cx: width / 2
    readonly property real cy: height / 2
    readonly property real stroke: Math.max(1.2, size / 22)
    property real contract: mode === "focus" ? .84 : 1
    property real separation: 0           // 0 … 1 while separating
    property real bloom: 1                // scale of the whole instrument
    property real glow: 0                 // 0 … 1 behind the rings
    property real quiet: mode === "focus" ? .55 : 1
    readonly property real r1: size * .20 * contract * (1 + .08 * separation)
    readonly property real r2: size * .31 * contract * (1 + .16 * separation)
    readonly property real r3: size * .43 * contract * (1 + .24 * separation)
    readonly property color ringColor: mode === "gaming" ? Theme.brightGreen : accent
    scale: bloom
    // Absent until the awakening; awaken() breaks the binding and fades it in.
    opacity: VisualQuality.awakenedOnce || Config.testMode || !live ? 1 : 0
    Behavior on contract { enabled: root.live; NumberAnimation { duration: VisualQuality.ms(Theme.morphGrow); easing.type: Easing.OutCubic } }
    Behavior on quiet { enabled: root.live; NumberAnimation { duration: VisualQuality.ms(Theme.morphGrow) } }
    Behavior on glow { enabled: root.live; NumberAnimation { duration: VisualQuality.ms(260) } }
    function units(r) { return 2 * Math.PI * r / stroke; }
    function pattern(r, n) { const u = units(r) / n; return [u * .82, u * .18]; }

    // ---- turning
    property real turn1: 0
    property real turn2: 0
    property real turn3: 0
    // Hover: the middle ring turns slowly for as long as the pointer stays; the glow rises.
    NumberAnimation on turn2 { running: root.hovered && root.live; loops: Animation.Infinite; from: root.turn2; to: root.turn2 + root.units(root.r2); duration: 3200 }
    onHoveredChanged: glow = hovered ? .45 : (mode === "gaming" ? .2 : 0)
    // Gaming: the outer ring completes one slow turn, then locks.
    onModeChanged: { if (mode === "gaming" && live) gamingTurn.restart(); glow = mode === "gaming" ? .2 : hovered ? .45 : 0; }
    NumberAnimation { id: gamingTurn; target: root; property: "turn3"; from: 0; to: root.units(root.r3); duration: VisualQuality.ms(1400); easing.type: Easing.InOutCubic }
    // Warning: the amber segment flares twice.
    property real flare: 1
    onWarningChanged: if (warning && live) flaring.restart()
    SequentialAnimation { id: flaring; loops: 2; NumberAnimation { target: root; property: "flare"; to: .2; duration: 220 } NumberAnimation { target: root; property: "flare"; to: 1; duration: 220 } }

    // ---- events
    property real runner: -1
    function pulse() {
        if (!live) return;
        sweep.restart(); blooming.restart();
    }
    NumberAnimation { id: sweep; target: root; property: "runner"; from: 0; to: 1; duration: VisualQuality.ms(720); easing.type: Easing.InOutQuad; onFinished: root.runner = -1 }
    SequentialAnimation {
        id: blooming
        ParallelAnimation {
            NumberAnimation { target: root; property: "bloom"; to: 1.28; duration: VisualQuality.ms(180); easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "glow"; to: .8; duration: VisualQuality.ms(160) }
        }
        ParallelAnimation {
            NumberAnimation { target: root; property: "bloom"; to: 1; duration: VisualQuality.ms(520); easing.type: Easing.OutBack }
            NumberAnimation { target: root; property: "glow"; to: root.hovered ? .45 : root.mode === "gaming" ? .2 : 0; duration: VisualQuality.ms(600) }
        }
    }
    property real rippleRadius: 0
    property real rippleAlpha: 0
    function ripple() { if (live) rippling.restart(); }
    ParallelAnimation {
        id: rippling
        NumberAnimation { target: root; property: "rippleRadius"; from: root.r1; to: root.size * .95; duration: VisualQuality.ms(700); easing.type: Easing.OutCubic }
        SequentialAnimation { PropertyAction { target: root; property: "rippleAlpha"; value: .9 } NumberAnimation { target: root; property: "rippleAlpha"; to: 0; duration: VisualQuality.ms(700); easing.type: Easing.InQuad } }
    }
    onUnfoldingChanged: if (unfolding && live) separating.restart()
    function separateOnce() { if (live) separating.restart(); }
    SequentialAnimation {
        id: separating
        ParallelAnimation {
            NumberAnimation { target: root; property: "separation"; to: 1; duration: VisualQuality.ms(260); easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "turn1"; to: root.turn1 + root.units(root.r1) / 6; duration: VisualQuality.ms(260); easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "glow"; to: .5; duration: VisualQuality.ms(200) }
        }
        ParallelAnimation {
            NumberAnimation { target: root; property: "separation"; to: 0; duration: VisualQuality.ms(560); easing.type: Easing.OutBack }
            NumberAnimation { target: root; property: "glow"; to: root.hovered ? .45 : 0; duration: VisualQuality.ms(600) }
        }
    }
    // Awakening: spread and turned, the rings spin into place and the glow settles.
    function awaken() {
        if (!live) return;
        separation = 1; turn1 = units(r1) / 3; turn2 = -units(r2) / 2; turn3 = units(r3) / 2; glow = .7; opacity = 0;
        awakening.restart();
    }
    ParallelAnimation {
        id: awakening
        NumberAnimation { target: root; property: "opacity"; to: 1; duration: VisualQuality.ms(500) }
        NumberAnimation { target: root; property: "separation"; to: 0; duration: VisualQuality.ms(1100); easing.type: Easing.OutBack }
        NumberAnimation { target: root; property: "turn1"; to: 0; duration: VisualQuality.ms(1000); easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "turn2"; to: 0; duration: VisualQuality.ms(1200); easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "turn3"; to: 0; duration: VisualQuality.ms(1400); easing.type: Easing.OutCubic }
        SequentialAnimation { PauseAnimation { duration: VisualQuality.ms(900) } NumberAnimation { target: root; property: "glow"; to: 0; duration: VisualQuality.ms(700) } }
    }

    // ---- drawing
    Rectangle {
        anchors.centerIn: parent
        width: root.size * 1.5; height: width; radius: width / 2
        color: Qt.alpha(root.ringColor, Math.min(1, .22 * root.glow * Math.min(1.5, root.intensity)))
        visible: root.glow > 0
    }
    Rectangle {
        visible: root.rippleAlpha > 0
        anchors.centerIn: parent
        width: root.rippleRadius * 2; height: width; radius: width / 2
        color: "transparent"; border.width: 1.5; border.color: Qt.alpha(root.ringColor, root.rippleAlpha)
    }
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        opacity: root.quiet
        ShapePath {
            strokeWidth: root.stroke; strokeColor: Qt.alpha(root.ringColor, .6 * Math.min(1, root.intensity) + .25); fillColor: "transparent"; capStyle: ShapePath.FlatCap
            strokeStyle: ShapePath.DashLine; dashPattern: root.pattern(root.r1, 6); dashOffset: root.turn1
            PathAngleArc { centerX: root.cx; centerY: root.cy; radiusX: root.r1; radiusY: root.r1; startAngle: -90; sweepAngle: 360 }
        }
        ShapePath {
            strokeWidth: root.stroke; strokeColor: Qt.alpha(root.ringColor, .5 * Math.min(1, root.intensity) + .2); fillColor: "transparent"; capStyle: ShapePath.FlatCap
            strokeStyle: ShapePath.DashLine; dashPattern: root.pattern(root.r2, 9); dashOffset: root.turn2
            PathAngleArc { centerX: root.cx; centerY: root.cy; radiusX: root.r2; radiusY: root.r2; startAngle: -90; sweepAngle: 360 }
        }
        ShapePath {
            strokeWidth: root.stroke * (root.mode === "gaming" ? 1.7 : 1.15); strokeColor: Qt.alpha(root.ringColor, Math.min(1, (root.mode === "gaming" ? 1 : .8) * Math.min(1, root.intensity) + .15)); fillColor: "transparent"; capStyle: ShapePath.FlatCap
            strokeStyle: ShapePath.DashLine; dashPattern: root.pattern(root.r3, 12); dashOffset: root.turn3
            PathAngleArc { centerX: root.cx; centerY: root.cy; radiusX: root.r3; radiusY: root.r3; startAngle: -90; sweepAngle: 360 }
        }
        ShapePath {
            strokeWidth: root.stroke * 1.6; strokeColor: root.warning ? Qt.alpha(Theme.amber, root.flare) : "transparent"; fillColor: "transparent"; capStyle: ShapePath.FlatCap
            PathAngleArc { centerX: root.cx; centerY: root.cy; radiusX: root.r3; radiusY: root.r3; startAngle: -90; sweepAngle: 30 * .82 }
        }
        ShapePath {
            strokeWidth: root.stroke * 2.2; strokeColor: root.runner >= 0 ? Theme.white : "transparent"; fillColor: "transparent"; capStyle: ShapePath.RoundCap
            strokeStyle: ShapePath.DashLine
            dashPattern: [root.units(root.r3) * .16, root.units(root.r3) * .84]
            dashOffset: -root.runner * root.units(root.r3)
            PathAngleArc { centerX: root.cx; centerY: root.cy; radiusX: root.r3; radiusY: root.r3; startAngle: -90; sweepAngle: 360 }
        }
        ShapePath {
            strokeWidth: root.stroke; strokeColor: Qt.alpha(root.ringColor, .95); fillColor: "transparent"; capStyle: ShapePath.RoundCap
            startX: root.cx; startY: root.cy + root.r1 * .6
            PathLine { x: root.cx; y: root.cy - root.r1 * .65 }
        }
        ShapePath {
            strokeWidth: root.stroke * .9; strokeColor: Qt.alpha(root.ringColor, .8); fillColor: "transparent"; capStyle: ShapePath.RoundCap
            startX: root.cx; startY: root.cy + root.r1 * .15
            PathLine { x: root.cx - root.r1 * .5; y: root.cy - root.r1 * .1 }
            PathMove { x: root.cx; y: root.cy + root.r1 * .15 }
            PathLine { x: root.cx + root.r1 * .5; y: root.cy - root.r1 * .1 }
            PathMove { x: root.cx; y: root.cy - root.r1 * .25 }
            PathLine { x: root.cx - root.r1 * .32; y: root.cy - root.r1 * .48 }
            PathMove { x: root.cx; y: root.cy - root.r1 * .25 }
            PathLine { x: root.cx + root.r1 * .32; y: root.cy - root.r1 * .48 }
        }
    }
    Accessible.role: Accessible.Graphic
    Accessible.name: "CEDAR heartwood" + (mode !== "idle" ? ", " + mode : "") + (warning ? ", attention" : "")
}
