import QtQuick
import Quickshell
import ".."
import "../components"
import "../services"

// CEDAR AI's window: a regular toplevel (Hyprland tiles or floats it) over
// the Relay service. Closing it leaves a running session running; Stop on
// the page ends it. The window remembers its size.
FloatingWindow {
    id: root
    title: "CEDAR AI"
    color: Theme.background
    implicitWidth: Config.saved.relayWindowWidth || 1120
    implicitHeight: Config.saved.relayWindowHeight || 760
    minimumSize: Qt.size(720, 520)
    visible: true
    onVisibleChanged: if (!visible) Relay.closeApp()
    onWidthChanged: remember.restart()
    onHeightChanged: remember.restart()
    // One write a moment after the last resize; nothing recurring.
    Timer { id: remember; interval: 600; onTriggered: if (root.width >= 720 && root.height >= 520) { Config.set("relayWindowWidth", root.width); Config.set("relayWindowHeight", root.height); } }
    CedarAtmosphere { anchors.fill: parent; active: false; visible: Config.saved.ambientIntensity > 0; opacity: Config.saved.ambientIntensity * .7 }
    RelayPages { anchors.fill: parent; focus: true; onClosed: Relay.closeApp() }
}
