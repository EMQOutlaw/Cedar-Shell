import QtQuick
import ".."
import "../services"

Item {
    id: root
    property bool active: false
    readonly property bool moving: active && visible && Motion.active
    clip: true
    // Quiet fungal filaments at the edges leave the reading area clear.
    Canvas {
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        // Canvas paint handlers do not track theme dependencies.
        readonly property var paintPalette: [Theme.green]
        onPaintPaletteChanged: requestPaint()
        onPaint: {
            const c = getContext("2d"); c.reset(); c.lineWidth = 1;
            for (let i = 0; i < 14; i++) {
                const x = width * (i / 13), y = height;
                c.strokeStyle = Qt.alpha(Theme.green, 0.025 + (i % 3) * 0.012);
                c.beginPath(); c.moveTo(x, y);
                c.bezierCurveTo(x - 55, y - 45, x + 45, y - 95, x + (i % 2 ? -24 : 24), y - 155);
                c.stroke();
                c.beginPath(); c.moveTo(x - 2, y - 40); c.lineTo(x + 25, y - 72); c.lineTo(x + 40, y - 78); c.stroke();
            }
        }
    }
    // One ambient clock for every spore, stepped at Motion.ambientFps: each
    // spore reads its own phase of the same slow sine. Twenty Animator loops
    // here used to commit a frame every vsync on every mapped window while a
    // Canopy or the rail was open (2026-10-30).
    Breath {
        id: drift
        running: root.moving
        from: 0; to: 1
        rise: Theme.pulse; fall: Theme.pulse
    }
    Repeater {
        model: 20
        Item {
            id: spore
            required property int index
            readonly property real seed: ((index * 37 + 11) % 101) / 101
            // Each spore sits at its own point on the cycle.
            readonly property real phase: (drift.value + seed) % 1
            readonly property real wave: 0.5 - 0.5 * Math.cos(2 * Math.PI * phase)
            x: (0.025 + seed * 0.95) * root.width
            y: root.height * (0.12 + ((index * 29) % 83) / 100) - 24 * wave
            width: 18; height: 18
            opacity: root.moving ? 0.08 + 0.42 * (0.5 - 0.5 * Math.cos(2 * Math.PI * ((phase + 0.37) % 1))) : 0.12 + (index % 4) * 0.07
            Rectangle { anchors.centerIn: parent; width: 14; height: 14; radius: 7; color: Qt.alpha(Theme.green, 0.06) }
            Rectangle { anchors.centerIn: parent; width: 5; height: 5; radius: 3; color: Qt.alpha(Theme.green, 0.15) }
            Rectangle { anchors.centerIn: parent; width: index % 3 === 0 ? 2 : 1; height: width; radius: 1; color: Theme.green }
        }
    }
}
