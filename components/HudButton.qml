import QtQuick
import QtQuick.Controls
import ".."

AbstractButton {
    id: root
    property color accent: Theme.green
    implicitWidth: Math.max(60, label.implicitWidth + 28)
    implicitHeight: 38
    hoverEnabled: true
    activeFocusOnTab: true
    background: HudPanel {
        padding: 0
        highlighted: root.hovered || root.activeFocus || root.checked
        accent: root.accent
        fillColor: root.down ? Theme.elevated : Theme.glass
    }
    contentItem: GlowText {
        id: label
        text: root.text
        color: root.enabled ? root.accent : Theme.muted
        font.family: Theme.labelFont
        font.pixelSize: 16
        font.weight: Font.DemiBold
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    Accessible.name: text
}
