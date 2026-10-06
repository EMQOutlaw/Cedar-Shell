import QtQuick
import ".."
// A quiet, non-interactive state label: dot plus short text.
Rectangle {
    id: root
    property string text: ""
    property color tone: Theme.teal
    implicitWidth: row.implicitWidth + 18; implicitHeight: 24
    radius: 12
    color: Qt.alpha(tone, .08); border.color: Qt.alpha(tone, .35)
    Accessible.role: Accessible.StaticText
    Accessible.name: text
    Row {
        id: row
        anchors.centerIn: parent; spacing: 6
        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 6; height: 6; radius: 3; color: root.tone }
        Text { anchors.verticalCenter: parent.verticalCenter; text: root.text.toUpperCase(); textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: 9; font.letterSpacing: 1.2; color: root.tone }
    }
}
