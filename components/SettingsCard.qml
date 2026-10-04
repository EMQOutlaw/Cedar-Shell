import QtQuick
import QtQuick.Layouts
import ".."
Item {
    id: root
    default property alias content: body.data
    property int padding: 20
    property string title: ""
    implicitHeight: body.implicitHeight + padding*2
    Rectangle { anchors.fill: parent; radius: 10; color: Qt.alpha(Theme.teal,.035); border.color: Qt.alpha(Theme.teal,.12) }
    ColumnLayout { id: body; anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: root.padding; spacing: 12
        GlowText { visible: root.title !== ""; text: root.title; font.family: Theme.labelFont; font.pixelSize: Theme.title; Layout.fillWidth: true; wrapMode: Text.WordWrap }
    }
}
