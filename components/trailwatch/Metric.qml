import QtQuick
import QtQuick.Layouts
import "../.."

Item {
    id: root
    property string label: ""
    property string value: ""
    property color accent: Theme.text
    implicitHeight: Math.max(key.implicitHeight, reading.implicitHeight)
    Layout.fillWidth: true
    FieldText {
        id: key
        width: parent.width * .43
        text: root.label
        color: Theme.muted
        font.pixelSize: Theme.small
    }
    FieldText {
        id: reading
        anchors.right: parent.right
        width: parent.width * .56
        text: root.value
        color: root.accent
        font.pixelSize: Theme.small
        horizontalAlignment: Text.AlignRight
    }
}
