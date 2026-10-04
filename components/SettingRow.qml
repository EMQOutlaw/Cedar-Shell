import QtQuick
import QtQuick.Layouts
import ".."
Item {
    id: root
    property string title: ""
    property string description: ""
    property bool highlighted: false
    property bool compact: width < 570
    default property alias controls: slot.data
    implicitHeight: layout.implicitHeight + 24
    Rectangle { anchors.fill: parent; radius: 7; color: root.highlighted ? Qt.alpha(Theme.green,.09) : Theme.transparent; border.width: root.highlighted ? 1:0; border.color: Qt.alpha(Theme.green,.45) }
    GridLayout {
        id: layout
        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
        anchors.margins: 12
        columns: root.compact ? 1:2; columnSpacing: 24; rowSpacing: 10
        ColumnLayout {
            Layout.fillWidth: true; spacing: 5
            GlowText { text: root.title; font.pixelSize: Theme.normal; Layout.fillWidth: true; wrapMode: Text.WordWrap; color: root.enabled ? Theme.text:Theme.muted }
            GlowText { text: root.description; visible: text!==""; color: Theme.muted; font.pixelSize: Theme.small-1; Layout.fillWidth: true; wrapMode: Text.WordWrap }
        }
        RowLayout { id: slot; Layout.fillWidth: root.compact; Layout.preferredWidth: root.compact ? -1 : 240; spacing: 8 }
    }
    Rectangle { anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right; anchors.leftMargin: 12; anchors.rightMargin: 12; height: 1; color: Qt.alpha(Theme.teal,.10) }
}
