import QtQuick
import ".."

Item {
    id: root
    property string time: ""
    property string date: ""
    property string period: ""
    property real activity: 0
    property bool active: true
    implicitWidth: 270
    implicitHeight: 270
    Canvas {
        anchors.fill: parent
        opacity: 0.675 + Math.max(0, root.activity) * 0.2
        scale: 0.98
        SequentialAnimation on opacity {
            running: root.active && root.visible && !Theme.reducedMotion
            loops: Animation.Infinite
            OpacityAnimator { to: 0.8 + Math.max(0, root.activity) * 0.2; duration: 3600; easing.type: Easing.InOutSine }
            OpacityAnimator { to: 0.625 + Math.max(0, root.activity) * 0.2; duration: 4400; easing.type: Easing.InOutSine }
        }
        SequentialAnimation on scale {
            running: root.active && root.visible && !Theme.reducedMotion
            loops: Animation.Infinite
            ScaleAnimator { to: 1; duration: 3600; easing.type: Easing.InOutSine }
            ScaleAnimator { to: 0.972; duration: 4400; easing.type: Easing.InOutSine }
        }
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const c = getContext("2d"); c.reset();
            const r = Math.min(width,height)/2;
            const gradient = c.createRadialGradient(width/2,height/2,12,width/2,height/2,r);
            gradient.addColorStop(0, Qt.alpha(Theme.green,0.11));
            gradient.addColorStop(0.6, Qt.alpha(Theme.green,0.055));
            gradient.addColorStop(1, Qt.alpha(Theme.green,0));
            c.fillStyle=gradient; c.fillRect(0,0,width,height);
        }
    }
    Canvas {
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const c = getContext("2d"); c.reset();
            const x = width / 2, y = height / 2, r = Math.min(x, y) - 12;
            c.lineWidth = 1;
            for (const offset of [0, 16]) {
                c.strokeStyle = Qt.alpha(Theme.teal, offset === 0 ? 0.28 : 0.12);
                c.beginPath(); c.arc(x, y, r - offset, 0, Math.PI * 2); c.stroke();
            }
            for (let i = 0; i < 60; i++) {
                const a = i * Math.PI / 30;
                const length = i % 5 === 0 ? 6 : 2;
                c.strokeStyle = Qt.alpha(Theme.teal, i % 5 === 0 ? 0.45 : 0.16);
                c.beginPath(); c.moveTo(x + (r-3)*Math.cos(a), y + (r-3)*Math.sin(a));
                c.lineTo(x + (r-3-length)*Math.cos(a), y + (r-3-length)*Math.sin(a)); c.stroke();
            }
        }
    }
    Canvas {
        id: orbit
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const c = getContext("2d"); c.reset();
            const x = width/2, y = height/2, r = Math.min(x,y)-12;
            c.lineWidth = 2; c.lineCap = "round"; c.strokeStyle = Theme.green;
            c.beginPath(); c.arc(x,y,r,-Math.PI/2,-Math.PI/2+0.38); c.stroke();
            c.lineWidth = 1; c.strokeStyle = Qt.alpha(Theme.green, 0.5);
            c.beginPath(); c.arc(x,y,r-16,Math.PI*0.35,Math.PI*0.8); c.stroke();
        }
        RotationAnimator on rotation {
            from: 0; to: 360; duration: 60000; loops: Animation.Infinite
            running: root.active && root.visible && !Theme.reducedMotion
        }
    }
    Column {
        anchors.centerIn: parent
        spacing: 8
        width: parent.width - 52
        Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: "THE LIGHT STAYS ON"; font.family: Theme.dataFont; font.pixelSize: 10; font.letterSpacing: 1.2; color: Theme.muted }
        Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: root.time; font.family: Theme.labelFont; font.pixelSize: 58; font.weight: Font.Light; color: Theme.text }
        Text { visible: root.period !== ""; width: parent.width; horizontalAlignment: Text.AlignHCenter; text: root.period; font.family: Theme.dataFont; font.pixelSize: 10; color: Theme.green }
        Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: root.date; font.family: Theme.dataFont; font.pixelSize: 11; color: Theme.teal }
    }
}
