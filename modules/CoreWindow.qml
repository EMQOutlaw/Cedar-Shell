import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import ".."
import "../services"
import "../components/core"

PanelWindow {
    id: root
    Component.onCompleted: Canopy.registerControls(root)
    Component.onDestruction: Canopy.unregisterControls(root)
    required property var modelData
    screen: modelData
    readonly property bool covered: modelData ? (Hyprland.monitorFor(modelData)?.activeWorkspace?.hasFullscreen ?? false) : false
    visible: CoreService.available && CoreService.hostScreen === modelData && (!covered || Canopy.shown || CoreService.expanded || surface.alert || CoreService.recording || CoreService.privacy.length > 0)
    anchors.top: true
    margins.top: (Config.barDetached ? Config.barMargin : 0) + surface.barInset
    implicitWidth: Math.min(480, modelData?.width || 480)
    implicitHeight: surface.windowHeight
    exclusionMode: ExclusionMode.Ignore
    color: Theme.transparent
    mask: Region {
        item: surface
    }
    WlrLayershell.namespace: "cedar-core"
    // A fixed layer avoids compositor restacking/remapping on volume updates and
    // keeps Core above every bar, including bars created by later monitor hotplug.
    // Only the quiet clock is hidden on fullscreen workspaces.
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: CoreService.expanded ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    CoreSurface {
        id: surface
        anchors.horizontalCenter: parent.horizontalCenter
        active: root.visible
        maximumWidth: root.width - 8
        maximumHeight: Math.max(200, (root.modelData?.height || 800) - Config.barHeight - 60)
        focusRequested: CoreService.expanded
    }
}
