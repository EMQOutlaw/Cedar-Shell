import QtQuick
import QtQuick.Layouts
import ".."
// One titled card. Every Settings page is built from these, so pages read alike.
Item {
    id: root
    default property alias content: body.data
    property string heading: ""
    property string caption: ""
    property string badge: ""
    property color badgeColor: Theme.teal
    property color accent: Theme.teal
    property bool emphasis: false
    property int padding: 18
    Layout.fillWidth: true
    implicitHeight: body.implicitHeight + padding * 2
    Rectangle {
        anchors.fill: parent; radius: Theme.cardRadius
        color: Qt.alpha(root.accent, root.emphasis ? .06 : .035)
        border.color: Qt.alpha(root.accent, root.emphasis ? .32 : .12)
    }
    // A short lit edge marks the card's title line.
    Rectangle { x: 0; y: root.padding + 4; width: 2; height: 18; radius: 1; color: Qt.alpha(root.accent, .7); visible: root.heading !== "" }
    ColumnLayout {
        id: body
        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: root.padding
        spacing: 10
        RowLayout {
            visible: root.heading !== "" || root.badge !== ""
            Layout.fillWidth: true; spacing: 10
            GlowText { text: root.heading; font.family: Theme.labelFont; font.pixelSize: Math.round(21 * Theme.fontScale); color: root.accent; Layout.fillWidth: true; wrapMode: Text.WordWrap }
            StatusPill { visible: root.badge !== ""; text: root.badge; tone: root.badgeColor }
        }
        GlowText { visible: root.caption !== ""; text: root.caption; color: Theme.muted; font.pixelSize: Theme.small; Layout.fillWidth: true; wrapMode: Text.WordWrap }
    }
}
