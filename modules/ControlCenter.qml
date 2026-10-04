import QtQuick
import ".."
import "../components"
Overlay {
    id: root
    panelName: "control"
    ControlPanel {
        anchors.centerIn: parent
        width: Math.min(root.width-32,720); height: Math.min(root.height-40,860)
        active: root.visible
    }
}
