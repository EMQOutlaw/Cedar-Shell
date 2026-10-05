import QtQuick
import ".."
import "../components"

Overlay {
    id: root
    panelName: "settings"
    Loader {
        id: loader
        anchors.centerIn: parent
        width: Math.min(root.width - 32, 1000)
        height: Math.min(root.height - 40, 700)
        // Input drafts live in the shared controller. Other existing editors
        // retain their one dirty view until explicitly applied/discarded.
        // `draft` is set from the page's signal, not bound through `item`:
        // a binding on item?.dirty re-enters `active` while the item unloads.
        property bool draft: false
        active: root.visible || draft
        asynchronous: true
        sourceComponent: Component {
            SettingsPanel { section: ShellState.settingsSection }
        }
        onLoaded: {
            item.active = Qt.binding(() => root.visible);
            loader.draft = item.dirty === true;
        }
        Connections {
            target: loader.item
            ignoreUnknownSignals: true
            function onDirtyChanged() { loader.draft = loader.item.dirty === true; }
        }
    }
}
