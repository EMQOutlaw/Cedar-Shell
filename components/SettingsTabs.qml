import QtQuick
import QtQuick.Layouts
import ".."
Flow {
    id: root
    property var tabs: []
    property string current: ""
    signal chosen(string tab)
    spacing: 6
    Layout.fillWidth: true
    Repeater {
        model: root.tabs
        StrataButton {
            required property string modelData
            text: modelData; checked: root.current === modelData
            onClicked: root.chosen(modelData)
        }
    }
}
