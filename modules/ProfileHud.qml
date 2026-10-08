import QtQuick
import Quickshell
import Quickshell.Wayland
import ".."
import "../services"

// The Desktop Profiles preparation panel: the same overlay surface as Gaming
// Mode's, a little above the centre of the monitor that had focus, taking
// no input and no keyboard focus. It exists only while Profiles.hudShown is
// true; shell.qml creates it for the transaction and releases it after the hold.
PanelWindow {
    id: root
    screen: Quickshell.screens.find(s => s.name === Profiles.hudScreen) || Quickshell.screens.find(s => s.name === Config.saved.mainDisplay) || Quickshell.screens[0] || null
    anchors.top: true
    margins.top: Math.round((screen ? screen.height : 1080) * 0.3)
    implicitWidth: card.implicitWidth + 24
    implicitHeight: card.implicitHeight + 24
    exclusionMode: ExclusionMode.Ignore
    color: Theme.transparent
    mask: Region {}
    WlrLayershell.namespace: "cedar-profiles"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    visible: Profiles.hudShown
    ProfileHudCard { id: card; anchors.centerIn: parent; width: 480 }
}
