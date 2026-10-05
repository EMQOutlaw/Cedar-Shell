import QtQuick
import ".."
import "../components"

Overlay {
    id: root
    panelName: "settings"
    Loader {
        anchors.centerIn: parent
        width: Math.min(root.width - 32, 1000)
        height: Math.min(root.height - 40, 700)
        // Input drafts live in the shared controller. Other existing editors
        // retain their one dirty view until explicitly applied/discarded.
        active: root.visible || item?.dirty === true
        asynchronous: true
        sourceComponent: Component {
            SettingsPanel { section: ShellState.settingsSection }
        }
        onLoaded: item.active = Qt.binding(() => root.visible)
    }
}
