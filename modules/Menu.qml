import QtQuick
import ".."
import "../components"

Overlay {
    id: root
    panelName: "menu"
    Loader {
        anchors.fill: parent
        active: root.visible
        asynchronous: true
        source: Qt.resolvedUrl("MenuContent.qml")
        onLoaded: if (root.visible) item.focusMenu()
    }
}
