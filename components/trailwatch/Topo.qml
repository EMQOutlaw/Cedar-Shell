import QtQuick
import "../.."

Canvas {
    // Decorative contours, not a geographic map. Draw on resize or palette change.
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    // Canvas paint handlers do not track theme dependencies.
    readonly property var paintPalette: [Theme.teal]
    onPaintPaletteChanged: requestPaint()
    onPaint: {
        const c = getContext("2d");
        c.reset();
        c.strokeStyle = Qt.alpha(Theme.teal, .065);
        c.lineWidth = 1;
        for (let i = 0; i < 24; i++) {
            c.beginPath();
            for (let k = 0; k <= 180; k++) {
                const t = k / 180 * Math.PI * 2;
                const r = 90 + i * 32 + 12 * Math.sin(t * 3 + i * .16) + 18 * Math.sin(t * 5);
                const x = width * .12 + Math.cos(t) * r * 1.55, y = height * .78 + Math.sin(t) * r;
                if (k === 0)
                    c.moveTo(x, y);
                else
                    c.lineTo(x, y);
            }
            c.closePath();
            c.stroke();
        }
    }
}
