import QtQuick
import QtQuick.Shapes
import ".."

Item {
    id: root
    property real value: 0
    property string label: ""
    property string valueText: Math.round(value * 100) + "%"
    property color accent: Theme.green
    property bool pulse: false
    property bool active: visible
    property real reveal: 0
    implicitWidth: 150
    implicitHeight: 150
    Component.onCompleted: if (active) sweepAnimation.start()
    onActiveChanged: { if (active) sweepAnimation.restart(); else sweepAnimation.stop(); }
    NumberAnimation { id: sweepAnimation; target: root; property: "reveal"; from: 0; to: 1; duration: Theme.reducedMotion ? 0 : Theme.sweep; easing.type: Easing.OutCubic }
    Behavior on value { enabled: root.active && root.visible; NumberAnimation { duration: Theme.reducedMotion ? 0 : Theme.fast } }
    Canvas {
        id: arc
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const c = getContext("2d"); c.reset();
            const x = width/2, y = height/2, r = Math.min(x,y) - 10;
            if (r <= 0) return;
            const start = Math.PI * 0.75, span = Math.PI * 1.5;
            c.lineWidth = 1; c.strokeStyle = Theme.border;
            c.beginPath(); c.arc(x,y,r,start,start+span); c.stroke();
            c.strokeStyle = Theme.border; c.lineWidth = 1;
            for (let i = 0; i <= 24; i++) {
                const a = start + span*i/24;
                c.beginPath(); c.moveTo(x+(r-8)*Math.cos(a), y+(r-8)*Math.sin(a));
                c.lineTo(x+(r-12)*Math.cos(a), y+(r-12)*Math.sin(a)); c.stroke();
            }
        }
    }
    // Retained vector geometry replaces a full Canvas upload on every gauge frame.
    Repeater {
        model: [9, 5, 2]
        Shape {
            id: stroke
            required property int modelData
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            opacity: modelData === 2 ? 0.8 : 0.08
            SequentialAnimation on opacity {
                running: stroke.modelData === 2 && root.pulse && root.active && root.visible && !Theme.reducedMotion
                loops: Animation.Infinite
                OpacityAnimator { to: 1; duration: Theme.pulse }
                OpacityAnimator { to: 0.65; duration: Theme.pulse }
            }
            ShapePath {
                strokeWidth: stroke.modelData
                strokeColor: root.accent
                fillColor: Theme.transparent
                capStyle: ShapePath.FlatCap
                PathAngleArc {
                    centerX: root.width / 2
                    centerY: root.height / 2
                    radiusX: Math.max(0, Math.min(root.width, root.height) / 2 - 10)
                    radiusY: radiusX
                    startAngle: 135
                    sweepAngle: 270 * Math.max(0, Math.min(1, root.value)) * root.reveal
                }
            }
        }
    }
    Column {
        anchors.centerIn: parent
        spacing: 6
        width: parent.width - 34
        GlowText { anchors.horizontalCenter: parent.horizontalCenter; text: root.valueText; width: parent.width; horizontalAlignment: Text.AlignHCenter; fontSizeMode: Text.Fit; minimumPixelSize: 10; font.pixelSize: root.width > 220 ? 42 : 23; color: root.accent; glow: true }
        GlowText { anchors.horizontalCenter: parent.horizontalCenter; text: root.label; font.family: Theme.labelFont; font.pixelSize: 15; color: Theme.muted }
    }
}
