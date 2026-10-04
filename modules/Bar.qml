import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.SystemTray
import Quickshell.Services.UPower
import ".."
import "../components"
import "../services"

PanelWindow {
    id: root
    Component.onCompleted: Canopy.registerControls(root)
    Component.onDestruction: Canopy.unregisterControls(root)
    required property var output
    screen: output
    anchors {
        top: true
        left: true
        right: true
    }
    implicitHeight: Config.barHeight
    margins.top: Config.barDetached ? Config.barMargin : 0
    margins.left: Config.barDetached ? Config.barMargin : 0
    margins.right: Config.barDetached ? Config.barMargin : 0
    exclusiveZone: Config.barHeight + (Config.barDetached ? Config.barMargin : 0)
    color: Theme.transparent
    WlrLayershell.namespace: "cedar-bar"
    WlrLayershell.layer: WlrLayer.Top
    mask: Config.barIslands ? islands.inputRegion : null
    BarIslands {
        id: islands
        anchors.fill: parent
        output: root.output
        visible: Config.barIslands
    }
    readonly property bool coreHost: CoreService.enabled && CoreService.hostName === output.name
    readonly property var monitor: Hyprland.monitorFor(screen)
    readonly property var battery: UPower.displayDevice
    HudPanel {
        anchors.fill: parent
        visible: Config.barStyle === "cedar"
        fillColor: Qt.alpha(Theme.background, Config.barOpacity)
        padding: 0
    }
    Rectangle {
        anchors.fill: parent
        visible: Config.barStyle !== "cedar" && !Config.barIslands
        radius: Config.barStyle === "floating" ? Config.barRadius : 0
        color: Qt.alpha(Theme.background, Config.barOpacity)
        border.width: Config.barStyle === "floating" ? 1 : 0
        border.color: Theme.border
    }
    BarContents {
        visible: !Config.barIslands
        anchors.fill: parent
        anchors.margins: 6
        output: root.output
    }
}
