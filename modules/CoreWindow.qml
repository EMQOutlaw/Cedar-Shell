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
    // Covered: a fullscreen window on this output's workspace, a focused window
    // whose geometry is the whole output (borderless games), or Gaming Mode.
    // The quiet pill steps aside; an attention alert, the expanded hub and an
    // open Canopy still bring it back. Recording and microphone/camera use no
    // longer hold the whole pill over a game: they keep one ember dot at the
    // top edge, which takes no input, so the indication is never lost. Dictation
    // counts too (CoreService.capturing) and never announces, so a covered pill
    // shows the dot alone: no whole pill over a game, no second overlay.
    readonly property bool covered: modelData ? ((Hyprland.monitorFor(modelData)?.activeWorkspace?.hasFullscreen ?? false) || (Config.fullscreenFocused && Config.fullscreenScreen === modelData.name) || Gaming.active) : false
    readonly property bool pillShown: !covered || Canopy.shown || CoreService.expanded || surface.alert
    readonly property bool emberDot: covered && !pillShown && CoreService.capturing
    // The dot alone takes no input: the mask is empty whenever the pill is down.
    readonly property bool inputRegionEmpty: !pillShown
    visible: CoreService.available && CoreService.hostScreen === modelData && (pillShown || emberDot)
    // Placement comes from CoreService.placement (StrataGeometry.corePlacement):
    // integrated under the top bar, or floating top-centre of the usable area
    // beside the Understory bar, the reserved bar width and margin respected.
    anchors.top: true
    anchors.left: true
    margins.top: CoreService.placement.top
    margins.left: CoreService.placement.left
    // Wide enough for the network chip's notice label beside an active-width pill; input is masked to the pill and chip.
    implicitWidth: CoreService.placement.width
    implicitHeight: surface.windowHeight
    exclusionMode: ExclusionMode.Ignore
    color: Theme.transparent
    // Only the pill and the network nub take input; the gap between them stays
    // click-through, and the ember dot alone takes nothing.
    mask: inputRegionEmpty ? dotMask : pillMask
    Region {
        id: pillMask
        item: surface.pillItem
        Region {
            item: surface.nubItem.visible ? surface.nubItem : null
            intersection: Intersection.Combine
        }
    }
    Region { id: dotMask }
    WlrLayershell.namespace: "cedar-core"
    // A fixed layer avoids compositor restacking/remapping on volume updates and
    // keeps Core above every bar, including bars created by later monitor hotplug.
    // Only the quiet clock is hidden on covered outputs (see `covered`).
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: CoreService.expanded ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    Rectangle {
        visible: root.emberDot
        anchors.horizontalCenter: parent.horizontalCenter; y: 4
        width: 8; height: 8; radius: 4
        color: Theme.ember
        Accessible.role: Accessible.Indicator
        Accessible.name: CoreService.recording ? "Recording" : Dictation.active ? "Dictation listening" : "Microphone or camera in use"
    }
    CoreSurface {
        id: surface
        visible: root.pillShown
        anchors.horizontalCenter: parent.horizontalCenter
        active: root.visible && root.pillShown
        maximumWidth: root.width - 8
        maximumHeight: CoreService.placement.maxHeight
        focusRequested: CoreService.expanded
    }
}
