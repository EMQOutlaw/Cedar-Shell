import QtQuick
import ".."

// Shared drop action: quiet foundation, chamfered edge and a clear focus ring.
StationButton {
    id: root
    accent: Theme.strataAccent
    background: ChamferFrame {
        anchors.fill: parent
        cut: Math.min(Theme.strataCut, root.height / 4)
        fill: root.down ? Qt.tint(Theme.strataFoundation, Qt.alpha(root.accent, .18))
            : root.checked ? Qt.tint(Theme.strataFoundation, Qt.alpha(root.accent, .10))
            : root.hovered ? Qt.tint(Theme.strataFoundation, Qt.alpha(root.accent, .05))
            : Theme.strataFoundation
        stroke: root.visualFocus ? root.accent : Qt.alpha(root.accent, root.checked ? .55 : root.hovered ? .32 : .16)
        strokeWidth: root.visualFocus ? Theme.focusWidth : 1
    }
    contentItem: Text {
        text: root.text
        textFormat: Text.PlainText
        font.family: Theme.dataFont
        font.pixelSize: root.iconOnly ? 16 : Theme.small
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        color: !root.enabled ? Theme.strataMuted : root.checked || root.down ? root.accent : Theme.strataText
        elide: Text.ElideRight
    }
}
