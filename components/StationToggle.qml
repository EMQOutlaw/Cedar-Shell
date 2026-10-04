import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."
RowLayout {
    id: root
    property string label: ""
    property string accessibleLabel: label
    property string description: ""
    property bool checked: false
    property bool busy: false
    signal toggled(bool value)
    spacing: 20
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 5
        Text { Layout.fillWidth: true; text: root.label; wrapMode: Text.WordWrap; font.family: Theme.dataFont; font.pixelSize: 13; color: Theme.text }
        Text { Layout.fillWidth: true; visible: text !== ""; text: root.description; wrapMode: Text.WordWrap; font.family: Theme.dataFont; font.pixelSize: 11; color: Theme.muted }
    }
    AbstractButton {
        id: toggle
        implicitWidth: 42; implicitHeight: 30
        enabled: !root.busy; activeFocusOnTab: true
        Accessible.name: root.accessibleLabel
        Accessible.role: Accessible.CheckBox
        Accessible.checkable: true
        Accessible.checked: root.checked
        onClicked: root.toggled(!root.checked)
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        background: Rectangle {
            y: 4; height: 22; radius: 11
            color: root.checked ? Qt.alpha(Theme.teal, 0.24) : Theme.surface
            border.width: 1; border.color: toggle.activeFocus ? Theme.green : root.checked ? Theme.teal : Theme.border
            Rectangle { x: root.checked ? 23 : 5; y: 4; width: 14; height: 14; radius: 7; color: root.checked ? Theme.teal : Theme.muted }
        }
    }
}
