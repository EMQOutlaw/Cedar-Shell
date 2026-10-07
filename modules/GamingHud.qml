import QtQuick
import Quickshell
import Quickshell.Wayland
import ".."
import "../services"

// The Gaming Mode preparation panel: a small overlay-layer surface a little
// above the centre of the monitor that had focus when Super+G was pressed.
// It takes no input (an empty mask lets every click through to the game),
// never takes keyboard focus, and exists only while Gaming.hudShown is true:
// shell.qml creates it for the transaction and releases it after the hold.
// The screen is fixed when the panel is shown, so focus moving mid-way does
// not remap the window.
PanelWindow {
    id: root
    screen: Quickshell.screens.find(s => s.name === Gaming.hudScreen) || Quickshell.screens.find(s => s.name === Config.saved.mainDisplay) || Quickshell.screens[0] || null
    anchors.top: true
    margins.top: Math.round((screen ? screen.height : 1080) * 0.3)
    implicitWidth: card.implicitWidth + 24
    implicitHeight: card.implicitHeight + 24
    exclusionMode: ExclusionMode.Ignore
    color: Theme.transparent
    mask: Region {}
    WlrLayershell.namespace: "cedar-gaming"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    visible: Gaming.hudShown
    GamingHudCard { id: card; anchors.centerIn: parent; width: 480 }
}
