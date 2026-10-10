import QtQuick
import QtQuick.Shapes
import ".."
import "../services"

// CEDAR's living root: retained curves, centre-out growth and a soft current
// drawn toward the active control. Only light/opacity moves; paths stay cached.
Item {
    id: root
    clip: true
    property real intensity: VisualQuality.effectIntensity
    property color tone: Theme.green
    // Strata shows the root only while it answers an event. A retained path
    // still carries the full growth / pulse vocabulary, then leaves no idle
    // contour through the integrated Core.
    property bool eventOnly: false
    readonly property bool live: visible && VisualQuality.effects && VisualQuality.decorative && Motion.active && intensity > 0
    readonly property bool animating: growing.running || runner.running || pulseLeft.running || pulseCentre.running || pulseRight.running || (flowing && live)
    opacity: eventOnly ? Math.max(traceEnvelope, litLeft, litCentre, litRight, growing.running ? Math.sin(Math.PI * growth) : 0) : 1
    readonly property real footY: Math.max(0, height - 2)
    readonly property real third: width / 3
    readonly property real strength: Math.max(0, Math.min(1.5, intensity))
    readonly property real restAlpha: .14 * strength
    readonly property real centre: width / 2
    readonly property real reach: Math.max(0, width / 2 - 12)

    // Irregular spacing and outward-facing forks suggest cedar roots. Keep the
    // detail in the bottom eight pixels, below labels and button centres.
    readonly property var branches: {
        const rows = [], spacing = 112;
        for (let side = -1; side <= 1; side += 2) {
            for (let i = 0; i < Math.floor(reach / spacing); i++) {
                const distance = 38 + i * spacing + (i % 3) * 9;
                const x = centre + side * distance;
                const length = 38 + (i % 3) * 8;
                const rise = Math.min(Math.max(0, footY - 1), 7 + (i % 3));
                const end = x + side * length;
                if (end < 12 || end > width - 12) continue;
                const f = n => Number(n).toFixed(2);
                const path = `M ${f(x)} ${f(footY)} C ${f(x + side * 17)} ${f(footY)} ${f(end - side * 19)} ${f(footY - rise)} ${f(end)} ${f(footY - rise)}`;
                const twig = `M ${f(x + side * 23)} ${f(footY - rise * .48)} Q ${f(x + side * 29)} ${f(footY - rise - 2)} ${f(x + side * 37)} ${f(footY - rise - 2)}`;
                rows.push({ x: x, distance: distance, length: length, tipX: end, tipY: footY - rise, path: path, twig: twig });
            }
        }
        return rows;
    }

    property real growth: VisualQuality.awakenedOnce || Config.testMode || !live ? 1 : 0
    function grow() { if (live) growing.restart(); }
    NumberAnimation { id: growing; target: root; property: "growth"; from: 0; to: 1; duration: VisualQuality.ms(1250); easing.type: Easing.OutCubic }

    property bool flowing: false
    property real flowTo: width / 2
    readonly property real destination: Math.max(12, Math.min(width - 12, flowTo))
    property real flowPhase: 0
    property real flowAmount: flowing && live ? 1 : 0
    Behavior on flowAmount { enabled: root.live; NumberAnimation { duration: VisualQuality.ms(280); easing.type: Easing.OutCubic } }
    NumberAnimation on flowPhase {
        running: root.flowing && root.live
        loops: Animation.Infinite
        from: 0; to: 1; duration: VisualQuality.ms(2600)
    }
    readonly property real leftCurrent: 12 + (destination - 12) * flowPhase
    readonly property real rightCurrent: width - 12 + (destination - width + 12) * flowPhase
    readonly property real currentEnvelope: Math.sin(Math.PI * flowPhase) * flowAmount

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

    property real traceFrom: 0
    property real traceTo: 0
    property real traceProgress: -1
    property color traceTone: tone
    readonly property real traceX: traceFrom + (traceTo - traceFrom) * Math.max(0, traceProgress)
    readonly property real traceEnvelope: traceProgress >= 0 ? Math.sin(Math.PI * traceProgress) : 0
    function trace(fromX, toX, color) {
        if (!live || !isFinite(fromX) || !isFinite(toX) || Math.abs(toX - fromX) < 24) return;
        traceTone = color || tone;
        traceFrom = Math.max(12, Math.min(width - 12, fromX));
        traceTo = Math.max(12, Math.min(width - 12, toX));
        runner.duration = VisualQuality.ms(Math.max(650, Math.min(1400, Math.abs(traceTo - traceFrom))));
        runner.restart();
    }
    function signalTo(toX, color) { trace(width - 12, toX, color || Theme.amber); }
    NumberAnimation { id: runner; target: root; property: "traceProgress"; from: 0; to: 1; easing.type: Easing.InOutCubic; onFinished: root.traceProgress = -1 }

    // A policy change stops in-flight effects as well as the panel's loop.
    onLiveChanged: {
        if (live) return;
        growing.stop(); runner.stop(); pulseLeft.stop(); pulseCentre.stop(); pulseRight.stop();
        growth = 1; traceProgress = -1; litLeft = 0; litCentre = 0; litRight = 0;
    }
    function proximity(x, at, radius) { return Math.max(0, 1 - Math.abs(x - at) / radius); }

    // One quiet root with feathered ends. Reveal symmetrically from Heartwood.
    Item {
        x: root.centre * (1 - root.growth)
        width: root.width * root.growth; height: root.height; clip: true
        Rectangle {
            x: -parent.x + 12; y: root.footY; width: Math.max(0, root.width - 24); height: 1
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: "transparent" }
                GradientStop { position: .08; color: Qt.alpha(root.tone, root.restAlpha) }
                GradientStop { position: .5; color: Qt.alpha(root.tone, root.restAlpha * 1.5) }
                GradientStop { position: .92; color: Qt.alpha(root.tone, root.restAlpha) }
                GradientStop { position: 1; color: "transparent" }
            }
        }
    }
    Repeater {
        model: root.branches
        Item {
            id: branch
            required property var modelData
            anchors.fill: parent
            readonly property real revealed: Math.max(0, Math.min(1, (root.growth * root.reach - modelData.distance) / modelData.length))
            readonly property real current: Math.max(root.proximity(modelData.x, root.leftCurrent, 130), root.proximity(modelData.x, root.rightCurrent, 130)) * root.currentEnvelope
            readonly property real signalLight: root.proximity(modelData.x, root.traceX, 110) * root.traceEnvelope
            readonly property real lit: Math.max(root.litAt(modelData.x), current * .85, signalLight, growing.running ? Math.max(0, 1 - Math.abs(root.growth * root.reach - modelData.distance - modelData.length) / 100) : 0)
            readonly property color ink: signalLight > .1 ? root.traceTone : root.litAt(modelData.x) > .1 ? root.pulseTone : root.tone
            opacity: revealed
            // Small sap sparks bloom only as light reaches the end of a root.
            Rectangle {
                x: branch.modelData.tipX - width / 2; y: branch.modelData.tipY - height / 2
                width: 3 + branch.lit * 4; height: width; radius: width / 2
                color: branch.ink; opacity: branch.lit * .18 * root.strength
                Rectangle {
                    anchors.centerIn: parent; width: 2; height: 2; radius: 1
                    color: Qt.tint(branch.ink, "#80ffffff"); opacity: branch.lit
                }
            }
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                // The broad pass is a restrained halo, with no blur texture.
                ShapePath {
                    strokeWidth: 4; strokeColor: Qt.alpha(branch.ink, branch.lit * .18 * root.strength)
                    fillColor: "transparent"; capStyle: ShapePath.RoundCap
                    PathSvg { path: branch.modelData.path }
                }
                ShapePath {
                    strokeWidth: 1; strokeColor: Qt.alpha(branch.ink, Math.min(1, root.restAlpha + branch.lit * .75 * root.strength))
                    fillColor: "transparent"; capStyle: ShapePath.RoundCap
                    PathSvg { path: branch.modelData.path }
                }
                ShapePath {
                    strokeWidth: .65; strokeColor: Qt.alpha(branch.ink, Math.min(1, root.restAlpha * .65 + branch.lit * .35 * root.strength))
                    fillColor: "transparent"; capStyle: ShapePath.RoundCap
                    PathSvg { path: branch.modelData.twig }
                }
            }
        }
    }
    // Soft currents replace the dotted conveyor. Each pass fades at both ends
    // of its journey; branches respond as it passes through them.
    Repeater {
        model: 3
        Item {
            id: current
            required property int index
            readonly property bool signalPass: index === 2
            readonly property color ink: signalPass ? root.traceTone : root.tone
            width: signalPass ? 190 : 160; height: 9
            x: (signalPass ? root.traceX : index === 0 ? root.leftCurrent : root.rightCurrent) - width / 2
            y: root.footY - 4
            opacity: Math.min(1, (signalPass ? root.traceEnvelope : root.currentEnvelope * .9) * root.strength) * root.growth
            visible: opacity > .001
            Rectangle {
                anchors.fill: parent; radius: height / 2; opacity: .22
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: .5; color: current.ink }
                    GradientStop { position: 1; color: "transparent" }
                }
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 1.5
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: .5; color: current.ink }
                    GradientStop { position: 1; color: "transparent" }
                }
            }
        }
    }
    // A small pool of light seats an open panel on its root.
    Rectangle {
        x: root.destination - width / 2; y: root.footY - .5
        width: 52; height: 2
        opacity: root.flowAmount * .7 * Math.min(1, root.strength)
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: "transparent" }
            GradientStop { position: .5; color: root.tone }
            GradientStop { position: 1; color: "transparent" }
        }
    }
}
