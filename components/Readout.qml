import QtQuick
import QtQuick.Layouts
import ".."
// A read-only status tile. It shows state; it never navigates.
Rectangle {
    id: root
    property string label: ""
    property string value: ""
    property string detail: ""
    property bool lit: false
    property color tone: Theme.green
    Layout.fillWidth: true
    Layout.fillHeight: true
    Layout.preferredWidth: 200
    implicitHeight: column.implicitHeight + 28
    radius: 10
    color: Qt.alpha(Theme.teal, .035)
    border.color: lit ? Qt.alpha(tone, .35) : Qt.alpha(Theme.teal, .12)
    Accessible.role: Accessible.StaticText
    Accessible.name: label + ": " + value + (detail ? ". " + detail : "")
    ColumnLayout {
        id: column
        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 14
        spacing: 4
        RowLayout {
            spacing: 8
            Rectangle { width: 7; height: 7; radius: 4; color: root.lit ? root.tone : Qt.alpha(Theme.muted, .55) }
            Text { text: root.label.toUpperCase(); textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: 10; font.letterSpacing: 1.4; color: Theme.muted }
        }
        Text { Layout.fillWidth: true; text: root.value; textFormat: Text.PlainText; font.family: Theme.labelFont; font.pixelSize: Math.round(21 * Theme.fontScale); color: root.lit ? root.tone : Theme.text; elide: Text.ElideRight }
        Text { Layout.fillWidth: true; visible: text !== ""; text: root.detail; textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: 10; color: Theme.muted; wrapMode: Text.WordWrap; maximumLineCount: 3; elide: Text.ElideRight }
    }
}
