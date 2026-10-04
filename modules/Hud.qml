import QtQuick
import QtQuick.Controls
import ".."
import "../components"

Overlay {
    id: root
    panelName: "hud"
    ScrollView {
        id: scroll
        anchors.centerIn: parent
        width: Math.min(root.width - 32, 940)
        height: Math.min(root.height - 48, station.implicitHeight)
        contentWidth: availableWidth
        contentHeight: station.implicitHeight
        clip: true
        FieldStation {
            id: station
            width: scroll.availableWidth
            height: implicitHeight
            active: root.visible
        }
    }
}
