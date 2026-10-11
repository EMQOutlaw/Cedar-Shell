import QtQuick
import ".."

StationField {
    id: root
    color: Theme.strataText
    placeholderTextColor: Qt.alpha(Theme.strataMuted, .8)
    selectionColor: Qt.alpha(Theme.strataAccent, .35)
    selectedTextColor: Theme.strataText
    background: ChamferFrame {
        anchors.fill: parent
        cut: Math.min(Theme.strataCut, root.height / 4)
        fill: Theme.strataFoundation
        stroke: Qt.alpha(Theme.strataAccent, root.activeFocus ? .85 : .25)
        strokeWidth: root.activeFocus ? Theme.focusWidth : 1
    }
}
