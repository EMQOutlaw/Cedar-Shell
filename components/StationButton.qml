import QtQuick
import QtQuick.Controls
import ".."

AbstractButton {
    id: root
    property color accent: Theme.teal
    property string hint: ""
    property bool iconOnly: false
    implicitWidth: Math.max(36, label.implicitWidth + 24)
    implicitHeight: Theme.controlHeight
    padding: 8
    hoverEnabled: true
    activeFocusOnTab: true
    HoverHandler { cursorShape: Qt.PointingHandCursor }
    background: Rectangle {
        radius: Theme.controlRadius
        color: root.down ? Qt.alpha(root.accent, 0.18) : root.checked ? Qt.alpha(root.accent, 0.10) : Theme.transparent
        Rectangle {
            anchors.fill: parent; anchors.margins: Theme.focusInset
            radius: Math.max(0, parent.radius - Theme.focusInset)
            color: Theme.transparent
            border.width: root.visualFocus ? Theme.focusWidth : 0
            border.color: root.accent
        }
    }
    contentItem: Text {
        id: label
        text: root.text
        textFormat: Text.PlainText
        font.family: Theme.dataFont
        font.pixelSize: root.iconOnly ? 16 : Theme.small
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        color: !root.enabled ? Theme.muted : root.checked || root.down ? root.accent : Theme.text
        elide: Text.ElideRight
    }
    Accessible.name: hint || text
    ToolTip.visible: hovered && hint !== ""
    ToolTip.text: hint
    ToolTip.delay: 600
}
