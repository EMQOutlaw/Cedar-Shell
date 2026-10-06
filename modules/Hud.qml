import QtQuick
import QtQuick.Controls
import ".."
import "../components"

Overlay {
    id: root
    panelName: "hud"
    Loader {
        id: hudLoader
        anchors.centerIn: parent
        width: Math.min(root.width - 32, 940)
        // The content height is copied from the page's signal rather than
        // bound through `item`: the scroll view's layout reads this height
        // while computing the content height it would feed back into it.
        property real measured: 0
        height: Math.min(root.height - 48, measured)
        active: root.visible
        asynchronous: true
        onLoaded: measured = item.contentHeight
        Connections {
            target: hudLoader.item
            ignoreUnknownSignals: true
            function onContentHeightChanged() { hudLoader.measured = hudLoader.item.contentHeight; }
        }
        sourceComponent: Component {
            ScrollView {
                id: scroll
                contentWidth: availableWidth
                contentHeight: station.implicitHeight
                clip: true
                FieldStation {
                    id: station
                    // Full width, not availableWidth: the scrollbar's own
                    // visibility depends on this height, which depends on width.
                    width: scroll.width
                    height: implicitHeight
                    active: root.visible
                }
            }
        }
    }
}
