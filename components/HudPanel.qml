import QtQuick
import ".."

Item {
    id: root
    default property alias content: contentItem.data
    property bool highlighted: false
    property color accent: Theme.teal
    property color fillColor: Theme.glass
    property int padding: Theme.padding
    implicitWidth: 320
    implicitHeight: 160
    MouseArea { anchors.fill: parent; onWheel: event => event.accepted = false }
    Canvas {
        id: frame
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const c = getContext("2d"); c.reset();
            const m = 5, w = width - 5, h = height - 5, k = Theme.chamfer;
            c.beginPath(); c.moveTo(m + k, m); c.lineTo(w, m);
            c.lineTo(w, h - k); c.lineTo(w - k, h); c.lineTo(m, h);
            c.lineTo(m, m + k); c.closePath();
            c.fillStyle = root.fillColor; c.fill();
            if (root.highlighted) {
                c.strokeStyle = Qt.alpha(root.accent, 0.1); c.lineWidth = 9; c.stroke();
                c.strokeStyle = Qt.alpha(root.accent, 0.15); c.lineWidth = 5; c.stroke();
            }
            c.strokeStyle = root.highlighted ? root.accent : Theme.border;
            c.lineWidth = 1; c.stroke();
            c.strokeStyle = root.accent;
            c.beginPath(); c.moveTo(m + k, m); c.lineTo(m + k + 36, m); c.stroke();
            c.strokeStyle = Theme.grid;
            for (let y = 12; y < h; y += 6) {
                c.beginPath(); c.moveTo(m + 12, y); c.lineTo(w - 12, y); c.stroke();
            }
        }
        Connections {
            target: root
            function onHighlightedChanged() { frame.requestPaint(); }
            function onAccentChanged() { frame.requestPaint(); }
            function onFillColorChanged() { frame.requestPaint(); }
        }
    }
    Item { id: contentItem; anchors.fill: parent; anchors.margins: root.padding }
}
