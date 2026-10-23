import QtQuick
import QtQuick.Controls
AbstractButton {
    id: button
    property bool danger: false
    property int alignment: Text.AlignHCenter
    implicitWidth: Math.max(32, label.implicitWidth + 22)
    implicitHeight: Math.max(32, label.implicitHeight + 12)
    padding: 8
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    font.family: TM.font
    font.pixelSize: 13 * TM.scale
    contentItem: Text { id: label; text: button.text; textFormat: Text.PlainText; font: button.font; color: !button.enabled ? TM.muted : button.danger ? TM.danger : TM.text; horizontalAlignment: button.alignment; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
    background: Rectangle {
        radius: 4; color: button.down || button.checked ? TM.elevated : button.hovered ? Qt.alpha(TM.accent,.07) : "transparent"
        border.width: button.visualFocus ? 2 : 1
        border.color: button.visualFocus ? TM.accent : Qt.alpha(button.danger ? TM.danger : TM.border, button.checked ? .7 : .35)
        opacity: button.enabled ? 1 : .45
        Behavior on color { enabled: TM.motion; ColorAnimation { duration: TM.ms(120) } }
        LivingEdge { anchors.bottom: parent.bottom; width: parent.width; active: button.checked; visible: button.checked; accent: button.danger ? TM.danger : TM.accent }
    }
    Accessible.name: text
}
