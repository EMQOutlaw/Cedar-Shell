import QtQuick
import QtQuick.Controls
import ".."

// Horizontal slider with CEDAR's glow; `committed` fires on release so a
// drag produces one change instead of a stream of them.
Slider {
    id: root
    signal committed(real value)
    implicitHeight: 28
    from: 0; to: 1
    onPressedChanged: if (!pressed) committed(value)
    background: Rectangle {
        x: root.leftPadding; y: root.topPadding + root.availableHeight / 2 - height / 2
        width: root.availableWidth; height: 4
        color: Theme.border
        Rectangle { width: root.visualPosition * parent.width; height: parent.height; color: root.enabled ? Theme.green : Theme.muted }
    }
    handle: Rectangle {
        x: root.leftPadding + root.visualPosition * (root.availableWidth - width)
        y: root.topPadding + root.availableHeight / 2 - height / 2
        width: 16; height: 16; rotation: 45
        color: root.pressed ? Theme.elevated : Theme.surface
        border.color: root.enabled ? Theme.green : Theme.muted; border.width: 1
    }
}
