import QtQuick
Item {
    id: root
    property string iconKey: ""
    implicitWidth: 24; implicitHeight: 24
    Image { id: icon; anchors.fill: parent; source: Task.iconSource(root.iconKey); sourceSize.width: 32; sourceSize.height: 32; visible: status===Image.Ready }
    Rectangle {
        anchors.centerIn: parent; width: parent.width*.7; height: width; rotation: 45; radius: 2
        visible: icon.status!==Image.Ready; color: Qt.alpha(TM.accent,.08); border.color: Qt.alpha(TM.accent,.65)
        Rectangle { anchors.centerIn: parent; width: parent.width*.35; height: width; color: TM.accent; radius: 1 }
    }
}
