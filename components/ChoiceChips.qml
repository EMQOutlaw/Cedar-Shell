import QtQuick
import ".."
// A small segmented choice. options: [{value, label}] or plain strings.
Flow {
    id: root
    property var options: []
    property var current
    property string accessibleLabel: ""
    signal chosen(var value)
    spacing: 6
    Repeater {
        model: root.options
        StationButton {
            required property var modelData
            readonly property var value: typeof modelData === "object" ? modelData.value : modelData
            text: typeof modelData === "object" ? modelData.label : String(modelData)
            checked: root.current === value
            Accessible.name: (root.accessibleLabel ? root.accessibleLabel + ": " : "") + text
            Accessible.role: Accessible.RadioButton
            Accessible.checked: checked
            background: Rectangle {
                radius: Theme.controlRadius
                color: parent.down ? Qt.alpha(Theme.teal, .18) : parent.checked ? Qt.alpha(Theme.teal, .12) : parent.hovered ? Qt.alpha(Theme.teal, .05) : Theme.transparent
                border.width: parent.visualFocus ? Theme.focusWidth : 1
                border.color: parent.visualFocus ? Theme.green : parent.checked ? Qt.alpha(Theme.teal, .55) : Qt.alpha(Theme.teal, .16)
            }
            onClicked: root.chosen(value)
        }
    }
}
