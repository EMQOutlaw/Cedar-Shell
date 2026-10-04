import QtQuick
import QtQuick.Layouts
import ".."

// Labeled on/off switch drawn as a chamfered HUD button pair.
RowLayout {
    id: root
    property string label: ""
    property string description: ""
    property bool checked: false
    property bool busy: false
    signal toggled(bool value)
    spacing: Theme.gap
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 2
        GlowText { text: root.label; Layout.fillWidth: true; elide: Text.ElideRight }
        GlowText { visible: root.description !== ""; text: root.description; color: Theme.muted; font.pixelSize: Theme.small; Layout.fillWidth: true; wrapMode: Text.WordWrap }
    }
    HudButton {
        text: root.busy ? "…" : (root.checked ? "ON" : "OFF")
        checked: root.checked
        accent: root.checked ? Theme.green : Theme.muted
        implicitWidth: 72
        enabled: !root.busy
        onClicked: root.toggled(!root.checked)
    }
}
