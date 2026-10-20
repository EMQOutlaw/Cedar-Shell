import QtQuick
import QtQuick.Layouts
import ".."
Item {
    id: root
    default property alias content: body.data
    property int padding: 18
    property bool selected: false
    property color accent: Theme.strataAccent
    implicitHeight: body.implicitHeight + padding * 2
    Layout.fillWidth: true
    ChamferFrame {
        anchors.fill: parent; cut: Theme.strataCut
        fill: Qt.alpha(Theme.strataSurface, .78)
        stroke: Qt.alpha(root.accent, root.selected ? .55 : .20)
        topLine: root.selected; topLineColor: root.accent; topLineFraction: .35
    }
    ColumnLayout {
        id: body
        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
        anchors.margins: root.padding; spacing: 12
    }
}
