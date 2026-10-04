import QtQuick
import ".."

Canvas {
    id: root
    property bool active: false
    property real value: -1
    property var samples: []
    implicitHeight: 24
    onValueChanged: {
        if (!active || value < 0) return;
        samples = samples.concat([Math.max(0, Math.min(1, value))]).slice(-40);
        requestPaint();
    }
    onActiveChanged: if (active) { samples = value >= 0 ? [value] : []; requestPaint(); }
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
        const c = getContext("2d"); c.reset();
        c.strokeStyle = Qt.alpha(Theme.green, 0.12); c.lineWidth = 1;
        c.beginPath(); c.moveTo(0,height-2); c.lineTo(width,height-2); c.stroke();
        if (samples.length < 2) return;
        c.strokeStyle = Qt.alpha(Theme.green, 0.65); c.lineWidth = 1;
        c.beginPath();
        for (let i=0; i<samples.length; i++) {
            const x = width - (samples.length - 1 - i) * width / 39;
            const y = height - 3 - samples[i] * (height - 6);
            if (i===0) c.moveTo(x,y); else c.lineTo(x,y);
        }
        c.stroke();
    }
}
