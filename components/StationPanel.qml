import QtQuick
import ".."
Item {
    id: root
    default property alias content: body.data
    property int padding: 18
    implicitWidth: 320
    implicitHeight: 140
    Rectangle { anchors.fill: parent; radius: 10; color: Qt.alpha(Theme.teal, 0.035); border.width: 1; border.color: Qt.alpha(Theme.teal, 0.12) }
    Item { id: body; anchors.fill: parent; anchors.margins: root.padding }
}
