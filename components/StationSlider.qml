import QtQuick
import QtQuick.Controls
import ".."
Slider {
    id: root
    signal committed(real value)
    implicitHeight: 32
    from: 0; to: 1
    onPressedChanged: if (!pressed) committed(value)
    background: Rectangle {
        x: root.leftPadding; y: root.topPadding + root.availableHeight/2 - height/2
        width: root.availableWidth; height: 3; radius: 2
        color: Qt.alpha(Theme.teal, 0.15)
        Rectangle { width: root.visualPosition * parent.width; height: parent.height; radius: 2; color: root.enabled ? Theme.teal : Theme.muted }
    }
    handle: Rectangle {
        x: root.leftPadding + root.visualPosition * (root.availableWidth - width)
        y: root.topPadding + root.availableHeight/2 - height/2
        width: 12; height: 12; radius: 6
        color: !root.enabled ? Theme.muted : root.pressed ? Theme.green : Theme.teal
        border.width:root.activeFocus ? 2:0; border.color:Theme.text
    }
}
