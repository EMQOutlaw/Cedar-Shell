import QtQuick
import ".."

Item {
    id: root
    property bool active: false
    readonly property bool moving: active && visible && !Theme.reducedMotion
    clip: true
    // Quiet fungal filaments at the edges leave the reading area clear.
    Canvas {
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
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
    Repeater {
        model: 20
        Item {
            id: spore
            required property int index
            readonly property real seed: ((index * 37 + 11) % 101) / 101
            x: (0.025 + seed * 0.95) * root.width
            y: root.height * (0.12 + ((index * 29) % 83) / 100)
            width: 18; height: 18
            opacity: 0.12 + (index % 4) * 0.07
            Item {
            id: motes
            width: parent.width; height: parent.height
            Rectangle { anchors.centerIn: parent; width: 14; height: 14; radius: 7; color: Qt.alpha(Theme.green, 0.06) }
            Rectangle { anchors.centerIn: parent; width: 5; height: 5; radius: 3; color: Qt.alpha(Theme.green, 0.15) }
            Rectangle { anchors.centerIn: parent; width: index % 3 === 0 ? 2 : 1; height: width; radius: 1; color: Theme.green }
            SequentialAnimation on y {
                running: root.moving; loops: Animation.Infinite
                YAnimator { from: 0; to: -24; duration: 4500 + spore.index * 220; easing.type: Easing.InOutSine }
                YAnimator { from: -24; to: 0; duration: 5200 + spore.index * 180; easing.type: Easing.InOutSine }
            }
            }
            SequentialAnimation on opacity {
                running: root.moving; loops: Animation.Infinite
                OpacityAnimator { to: 0.5; duration: 3500 + spore.index * 170; easing.type: Easing.InOutSine }
                OpacityAnimator { to: 0.08; duration: 4700 + spore.index * 130; easing.type: Easing.InOutSine }
            }
        }
    }
}
