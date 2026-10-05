import QtQuick
import QtQuick.Controls
import ".."
import "../components"

Overlay {
    id: root
    panelName: "hud"
    Loader {
        anchors.centerIn: parent
        width: Math.min(root.width - 32, 940)
        height: Math.min(root.height - 48, item ? item.contentHeight : 0)
        active: root.visible
        asynchronous: true
        sourceComponent: Component {
            ScrollView {
                id: scroll
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
    }
}
