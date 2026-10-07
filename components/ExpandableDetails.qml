import QtQuick
import QtQuick.Layouts
import ".."

// A "Details" row that opens a technical block beneath a plain statement, so
// a card stays simple without hiding anything from someone who wants it.
ColumnLayout {
    id: root
    property string label: "Details"
    property bool expanded: false
    default property alias content: body.data
    spacing: 6
    StationButton {
        text: root.expanded ? "Hide " + root.label.toLowerCase() : root.label
        implicitHeight: 28
        onClicked: root.expanded = !root.expanded
        Accessible.name: (root.expanded ? "Hide " : "Show ") + root.label
    }
    ColumnLayout {
        id: body
        Layout.fillWidth: true
        Layout.leftMargin: 4
        spacing: 4
        visible: root.expanded
    }
}
