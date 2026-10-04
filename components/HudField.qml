import QtQuick
import QtQuick.Controls
import ".."

// Single-line text input in CEDAR glass. `commit` fires when editing ends
// with a changed value, so callers persist without saving every keystroke.
TextField {
    id: root
    signal commit(string value)
    property string lastCommitted: text
    implicitHeight: 36
    color: Theme.text
    placeholderTextColor: Theme.muted
    selectionColor: Theme.border
    selectedTextColor: Theme.white
    font.family: Theme.dataFont
    font.pixelSize: Theme.normal
    leftPadding: 10; rightPadding: 10
    background: Rectangle {
        color: Theme.surface
        border.color: root.activeFocus ? Theme.green : Theme.border
        border.width: 1
    }
    onEditingFinished: if (text !== lastCommitted) { lastCommitted = text; commit(text); }
    onTextChanged: if (!activeFocus) lastCommitted = text
}
