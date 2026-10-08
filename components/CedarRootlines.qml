import QtQuick
import QtQuick.Shapes
import ".."
import "../services"

// Rootlines: a root along the bar's foot with branches rising from it and a
// lit tip on each. The geometry is built once per width and retained.
// Four motions, each from real state:
//   grow()            the root and branches draw themselves in from the left
//                     (the shell awakening, a profile change)
//   flowing/flowTo    while a panel is open, light streams along the root
//                     from both ends toward the control it grew from; it
//                     stops the moment the panel closes
//   pulse(region)     a region's branches and tips flare in a colour and fade
//   signalTo(x)       a bright light runs from the right end to a point
Item {
    id: root
    property real intensity: VisualQuality.effectIntensity
    property color tone: Theme.green
    readonly property bool live: VisualQuality.effects && intensity > 0
    readonly property real footY: height - 5
    readonly property real lineWidth: 1.5
    readonly property int branchSpacing: 104
    readonly property real third: width / 3

    // ---- geometry, built once per width
    function branchPath(x0, x1) {
        let d = "";
        for (let x = x0 + 36; x < x1 - 24; x += branchSpacing) {
            const up = ((x / branchSpacing) | 0) % 2 === 0 ? 1 : -1;
            d += "M" + x + " " + footY + " l" + (up * 16) + " -9 l" + (up * 14) + " -5 ";
            d += "M" + (x + 26) + " " + footY + " l" + (up * -9) + " -6 ";
        }
        return d;
    }
    function tipsFor(x0, x1) {
        const out = [];
        for (let x = x0 + 36; x < x1 - 24; x += branchSpacing) { const up = ((x / branchSpacing) | 0) % 2 === 0 ? 1 : -1; out.push({ x: x + up * 30, y: footY - 14 }); out.push({ x: x + 26 - up * 9, y: footY - 6 }); }
        return out;
    }
    readonly property string leftPath: branchPath(0, third)
    readonly property string centrePath: branchPath(third, 2 * third)
    readonly property string rightPath: branchPath(2 * third, width)
    readonly property var tips: tipsFor(0, width)
    // Dash units are multiples of the stroke width.
    function units(px) { return px / lineWidth; }

    // ---- growth: the whole drawing draws itself in, left to right
    // Absent until the awakening draws it in; grow() breaks the binding and animates.
    property real growth: VisualQuality.awakenedOnce || Config.testMode || !live ? 1 : 0
    readonly property real drawLength: width * 1.6
    function grow() { if (!live) return; growth = 0; growing.restart(); }
    NumberAnimation { id: growing; target: root; property: "growth"; from: 0; to: 1; duration: VisualQuality.ms(1100); easing.type: Easing.OutCubic }

    // ---- flow: light streaming toward an open control, while it is open
    property bool flowing: false
    property real flowTo: width / 2
    property real flowPhase: 0
    NumberAnimation on flowPhase { running: root.flowing && root.live && root.visible; loops: Animation.Infinite; from: 0; to: 1; duration: 760 }
    readonly property real flowStep: units(38)

    // ---- pulses
    property real litLeft: 0
    property real litCentre: 0
    property real litRight: 0
    property color pulseTone: tone
    function pulse(region, color) {
        if (!live) return;
        pulseTone = color || tone;
        (region === "left" ? pulseLeft : region === "right" ? pulseRight : pulseCentre).restart();
    }
    SequentialAnimation { id: pulseLeft; NumberAnimation { target: root; property: "litLeft"; to: 1; duration: VisualQuality.ms(160); easing.type: Easing.OutCubic } NumberAnimation { target: root; property: "litLeft"; to: 0; duration: VisualQuality.ms(900); easing.type: Easing.InCubic } }
    SequentialAnimation { id: pulseCentre; NumberAnimation { target: root; property: "litCentre"; to: 1; duration: VisualQuality.ms(160); easing.type: Easing.OutCubic } NumberAnimation { target: root; property: "litCentre"; to: 0; duration: VisualQuality.ms(900); easing.type: Easing.InCubic } }
    SequentialAnimation { id: pulseRight; NumberAnimation { target: root; property: "litRight"; to: 1; duration: VisualQuality.ms(160); easing.type: Easing.OutCubic } NumberAnimation { target: root; property: "litRight"; to: 0; duration: VisualQuality.ms(900); easing.type: Easing.InCubic } }
    function litAt(x) { return x < third ? litLeft : x < 2 * third ? litCentre : litRight; }

    // ---- the travelling light
    property real traceFrom: 0
    property real traceTo: 0
    property real traceProgress: -1
    property color traceTone: tone
    readonly property real traceLength: Math.abs(traceTo - traceFrom)
    function trace(fromX, toX, color) {
        if (!live || !isFinite(fromX) || !isFinite(toX) || Math.abs(toX - fromX) < 24) return;
        traceTone = color || tone; traceFrom = fromX; traceTo = toX;
        runner.duration = VisualQuality.ms(Math.max(320, Math.min(900, Math.abs(toX - fromX) * .7)));
        runner.restart();
    }
    function signalTo(toX, color) { trace(width - 8, toX, color || Theme.amber); }
    NumberAnimation { id: runner; target: root; property: "traceProgress"; from: 0; to: 1; easing.type: Easing.InOutQuad; onFinished: root.traceProgress = -1 }

    readonly property real restAlpha: .24 * Math.min(1.5, intensity)
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        // The root, drawn in with the growth.
        ShapePath {
            strokeWidth: root.lineWidth; strokeColor: Qt.alpha(root.tone, root.restAlpha); fillColor: "transparent"; capStyle: ShapePath.RoundCap
            strokeStyle: ShapePath.DashLine; dashPattern: [root.units(root.drawLength), root.units(root.drawLength)]; dashOffset: root.units(root.drawLength) * (1 - root.growth)
            startX: 12; startY: root.footY
            PathLine { x: root.width - 12; y: root.footY }
        }
        // The branches, three regions, each lit by its pulse; drawn in with the growth.
        ShapePath { strokeWidth: root.lineWidth; strokeColor: Qt.alpha(root.litLeft > 0 ? root.pulseTone : root.tone, Math.min(1, root.restAlpha + .76 * root.litLeft)); fillColor: "transparent"; capStyle: ShapePath.RoundCap
            strokeStyle: ShapePath.DashLine; dashPattern: [root.units(root.drawLength), root.units(root.drawLength)]; dashOffset: root.units(root.drawLength) * (1 - root.growth); PathSvg { path: root.leftPath } }
        ShapePath { strokeWidth: root.lineWidth; strokeColor: Qt.alpha(root.litCentre > 0 ? root.pulseTone : root.tone, Math.min(1, root.restAlpha + .76 * root.litCentre)); fillColor: "transparent"; capStyle: ShapePath.RoundCap
            strokeStyle: ShapePath.DashLine; dashPattern: [root.units(root.drawLength), root.units(root.drawLength)]; dashOffset: root.units(root.drawLength) * (1 - root.growth); PathSvg { path: root.centrePath } }
        ShapePath { strokeWidth: root.lineWidth; strokeColor: Qt.alpha(root.litRight > 0 ? root.pulseTone : root.tone, Math.min(1, root.restAlpha + .76 * root.litRight)); fillColor: "transparent"; capStyle: ShapePath.RoundCap
            strokeStyle: ShapePath.DashLine; dashPattern: [root.units(root.drawLength), root.units(root.drawLength)]; dashOffset: root.units(root.drawLength) * (1 - root.growth); PathSvg { path: root.rightPath } }
        // The flow: short dashes streaming along the root from both ends toward the control.
        ShapePath {
            strokeWidth: 2.5; strokeColor: root.flowing ? Qt.alpha(root.tone, Math.min(1, .9 * root.intensity)) : "transparent"; fillColor: "transparent"; capStyle: ShapePath.RoundCap
            strokeStyle: ShapePath.DashLine; dashPattern: [root.units(5), root.units(33)]
            dashOffset: -root.flowPhase * root.flowStep
            startX: 12; startY: root.footY
            PathLine { x: Math.max(12, root.flowTo - 10); y: root.footY }
        }
        ShapePath {
            strokeWidth: 2.5; strokeColor: root.flowing ? Qt.alpha(root.tone, Math.min(1, .9 * root.intensity)) : "transparent"; fillColor: "transparent"; capStyle: ShapePath.RoundCap
            strokeStyle: ShapePath.DashLine; dashPattern: [root.units(5), root.units(33)]
            dashOffset: -root.flowPhase * root.flowStep
            startX: root.width - 12; startY: root.footY
            PathLine { x: Math.min(root.width - 12, root.flowTo + 10); y: root.footY }
        }
        // The travelling light: long, bright, with a tail.
        ShapePath {
            strokeWidth: 3.5; strokeColor: root.traceProgress >= 0 ? Qt.alpha(root.traceTone, Math.min(1, root.intensity)) : "transparent"; fillColor: "transparent"; capStyle: ShapePath.RoundCap
            strokeStyle: ShapePath.DashLine
            dashPattern: [root.units(44), root.units(Math.max(60, root.traceLength + 60))]
            dashOffset: root.units(44) - root.traceProgress * root.units(root.traceLength + 44)
            startX: root.traceFrom; startY: root.footY
            PathLine { x: root.traceTo; y: root.footY }
        }
    }
    // The tips: a lit dot at every branch end, flaring with its region's pulse and glowing where the flow converges.
    Repeater {
        model: root.tips
        Rectangle {
            required property var modelData
            readonly property real lit: root.litAt(modelData.x)
            readonly property real near: root.flowing ? Math.max(0, 1 - Math.abs(modelData.x - root.flowTo) / 160) : 0
            x: modelData.x - width / 2; y: modelData.y - height / 2
            width: 3 + 3 * Math.max(lit, near); height: width; radius: width / 2
            color: lit > 0 ? root.pulseTone : root.tone
            opacity: (root.restAlpha * 1.4 + .8 * Math.max(lit, near)) * root.growth
            Behavior on width { enabled: root.live; NumberAnimation { duration: 180 } }
        }
    }
}
