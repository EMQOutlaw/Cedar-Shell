import QtQuick
import ".."
// A section label with the station's tick before it. Width follows the label,
// so it never forces a layout column wider; give it fillWidth to elide instead.
Item {
    id: root
    property alias text: label.text
    property alias elide: label.elide
    property color tone: Theme.teal
    property int size: 10
    implicitWidth: 22 + label.implicitWidth
    implicitHeight: label.implicitHeight
    Rectangle { y: Math.round(parent.height / 2); width: 14; height: 1; color: root.tone; opacity: .7 }
    Text {
        id: label
        x: 22
        width: Math.max(0, parent.width - 22)
        textFormat: Text.PlainText
        font.family: Theme.dataFont
        font.pixelSize: root.size
        font.letterSpacing: 1.4
        color: root.tone
    }
}
