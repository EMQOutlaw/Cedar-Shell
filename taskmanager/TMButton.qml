import QtQuick
import QtQuick.Controls
AbstractButton {
    id: button
    property bool danger: false
    implicitWidth: Math.max(64, label.implicitWidth + 24)
    implicitHeight: 36
    padding: 10
    hoverEnabled: true
    font.family: Task.style.font || "sans-serif"
    contentItem: Text { id: label; text: button.text; textFormat: Text.PlainText; font: button.font; color: !button.enabled ? Task.style.muted : button.danger ? Task.style.ember : Task.style.text; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
    background: Rectangle {
        radius: 6; color: button.down || button.checked ? Task.style.elevated : button.hovered ? Task.style.surface : "transparent"
        border.color: button.activeFocus || button.checked ? Task.style.teal : Task.style.border
        opacity: button.enabled ? 1 : .45
        Behavior on color { enabled: !Task.style.reducedMotion; ColorAnimation { duration: 120 } }
    }
    Accessible.name: text
}
