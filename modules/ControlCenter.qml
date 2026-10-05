import QtQuick
import ".."
import "../components"
Overlay {
    id: root
    panelName: "control"
    // Built when first shown; a closed panel holds no delegates on any output.
    Loader {
        anchors.centerIn: parent
        width: Math.min(root.width-32,720); height: Math.min(root.height-40,860)
        active: root.visible
        asynchronous: true
        sourceComponent: Component { ControlPanel { active: root.visible } }
    }
}
