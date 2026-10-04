import QtQuick
import QtQuick.Controls
import ".."

AbstractButton {
    id: root
    property color accent: Theme.teal
    property string hint: ""
    property bool iconOnly: false
    implicitWidth: Math.max(36, label.implicitWidth + 24)
    implicitHeight: 36
    padding: 8
    hoverEnabled: true
    activeFocusOnTab: true
    HoverHandler { cursorShape: Qt.PointingHandCursor }
    background: Rectangle {
        radius: 6
        color: root.down || root.checked ? Qt.alpha(root.accent, 0.16) : root.hovered || root.activeFocus ? Qt.alpha(Theme.teal, 0.08) : Theme.transparent
        border.width: root.activeFocus || root.checked ? 1 : 0
        border.color: Qt.alpha(root.accent, 0.45)
    }
    contentItem: Text {
        id: label
        text: root.text
        textFormat: Text.PlainText
        font.family: Theme.dataFont
        font.pixelSize: root.iconOnly ? 16 : Theme.small
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        color: !root.enabled ? Qt.alpha(Theme.muted, 0.4) : root.hovered || root.checked ? root.accent : Theme.text
        elide: Text.ElideRight
    }
    Accessible.name: hint || text
    ToolTip.visible: hovered && hint !== ""
    ToolTip.text: hint
    ToolTip.delay: 600
}
