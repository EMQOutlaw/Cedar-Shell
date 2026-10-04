import QtQuick
import ".."
import "../components"

Overlay {
    id: root
    panelName: "settings"
    SettingsPanel {
        anchors.centerIn: parent
        width: Math.min(root.width - 32, 1180)
        height: Math.min(root.height - 40, 850)
        active: root.visible
    }
}
