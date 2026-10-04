import QtQuick
import QtQuick.Controls
import ".."
TextField {
    id: root
    signal commit(string value)
    property string lastCommitted: text
    implicitHeight: 40
    color: Theme.text
    placeholderTextColor: Qt.alpha(Theme.muted, 0.65)
    selectionColor: Theme.border
    selectedTextColor: Theme.text
    font.family: Theme.dataFont
    font.pixelSize: 12
    leftPadding: 12; rightPadding: 12
    background: Rectangle { radius: 6; color: Qt.alpha(Theme.teal, 0.035); border.width: 1; border.color: root.activeFocus ? Theme.teal : Qt.alpha(Theme.teal, 0.18) }
    onEditingFinished: if (text !== lastCommitted) { lastCommitted = text; commit(text); }
    onTextChanged: if (!activeFocus) lastCommitted = text
}
