import QtQuick
import QtQuick.Layouts
import ".."
TextEdit {
    Layout.fillWidth: true
    readOnly: true
    selectByMouse: true
    activeFocusOnTab: true
    textFormat: TextEdit.PlainText
    wrapMode: TextEdit.Wrap
    font.family: Theme.labelFont
    font.pixelSize: Math.round(18 * Theme.fontScale)
    color: Theme.text
    selectedTextColor: Theme.background
    selectionColor: Theme.green
    Accessible.role: Accessible.StaticText
    Accessible.name: text
    Rectangle { anchors.fill: parent; anchors.margins: -3; color: "transparent"; border.color: Theme.teal; radius: 3; visible: parent.activeFocus }
}
