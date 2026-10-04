import QtQuick
import ".."
import "../components"

Overlay {
    id: root
    panelName: "power"
    HudPanel {
        anchors.centerIn: parent
        width: Math.min(720, root.width - 32)
        height: Math.max(320, actions.implicitHeight + 48)
        highlighted: true
        SessionControls {
            id: actions
            anchors.fill: parent
        }
    }
}
