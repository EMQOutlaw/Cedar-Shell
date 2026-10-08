import QtQuick
import Quickshell
import Quickshell.Wayland
import ".."
import "../services"

// The Focus preparation panel: the same overlay surface as Gaming Mode's.
// It takes no input and no keyboard focus, and exists only while
// Focus.hudShown is true.
PanelWindow {
    id: root
    screen: Quickshell.screens.find(s => s.name === Focus.hudScreen) || Quickshell.screens.find(s => s.name === Config.saved.mainDisplay) || Quickshell.screens[0] || null
    anchors.top: true
    margins.top: Math.round((screen ? screen.height : 1080) * 0.3)
    implicitWidth: card.implicitWidth + 24
    implicitHeight: card.implicitHeight + 24
    exclusionMode: ExclusionMode.Ignore
    color: Theme.transparent
    mask: Region {}
    WlrLayershell.namespace: "cedar-focus"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    visible: Focus.hudShown
    FocusHudCard { id: card; anchors.centerIn: parent; width: 480 }
}
