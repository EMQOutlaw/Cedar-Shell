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
    Component.onCompleted: { Canopy.registerControls(root); if (backingWindowVisible) awakenLater.start(); }
    Component.onDestruction: Canopy.unregisterControls(root)
    // The awakening runs when the compositor has mapped this bar, a beat later, once.
    property bool awakened: false
    onBackingWindowVisibleChanged: if (backingWindowVisible) awakenLater.start()
    Timer { id: awakenLater; interval: 220; onTriggered: root.awakenBar() }
    function awakenBar() {
        if (awakened || Config.testMode || !VisualQuality.effects) return;
        awakened = true;
        rootlines.grow(); sweepRun.start(); settleIn.start();
        VisualQuality.awaken();
    }
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
    mask: Config.barIslands && islands.item ? islands.item.inputRegion : null
    // Only the selected bar style exists: the other tree is never built, per
    // output, so its bindings, animations and tray models cost nothing.
    Loader {
        id: islands
        anchors.fill: parent
        active: Config.barIslands
        sourceComponent: BarIslands { output: root.output }
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
    // Rootlines in the bar's own surface: branching paths along its foot that
    // light when a panel opens from this output, a profile changes, Focus
    // starts or Shield's posture moves. Static otherwise.
    CedarRootlines {
        id: rootlines
        anchors.fill: parent
        anchors.margins: 6
        visible: Config.saved.barRootlines && !Config.barIslands && VisualQuality.effects
        readonly property bool here: Canopy.screen === root.output
        function anchorX() { const a = Canopy.anchorRect; return a ? a.x + a.width / 2 - (Config.barDetached ? Config.barMargin : 0) - 6 : width / 2; }
        // While a panel is open on this output, light streams along the root toward its control.
        flowing: visible && here && Canopy.shown && !Canopy.peeking && Canopy.surfaceState !== "collapsed" && Canopy.surfaceState !== "closing"
        flowTo: anchorX()
        Connections {
            target: Canopy
            function onSurfaceStateChanged() {
                if (!rootlines.visible || !rootlines.here || Canopy.surfaceState !== "opening") return;
                const to = rootlines.anchorX();
                rootlines.trace(to < rootlines.width / 2 ? 8 : rootlines.width - 8, to, Forest.accent);
            }
        }
        Connections { target: Profiles; function onCurrentChanged() { if (rootlines.visible && root.coreHost) { rootlines.pulse("centre", Profiles.current ? Profiles.accentOf(Profiles.current) : Theme.green); rootlines.grow(); } } }
        Connections { target: Focus; function onActiveChanged() { if (rootlines.visible && root.coreHost) rootlines.pulse("centre", Focus.active ? Theme.teal : Theme.green); } }
        Connections { target: Shield; function onPostureChanged() { if (rootlines.visible && root.coreHost && Shield.ready) rootlines.signalTo(rootlines.width / 2, Shield.posture === "protected" ? Theme.green : Theme.amber); } }
    }
    Loader {
        id: contents
        anchors.fill: parent
        anchors.margins: 6
        active: !Config.barIslands
        sourceComponent: BarContents { output: root.output }
        // The controls settle in after the frame has drawn itself; a fallback shows them regardless.
        opacity: Config.testMode || !VisualQuality.effects ? 1 : 0
        SequentialAnimation { id: settleIn; PauseAnimation { duration: 260 } NumberAnimation { target: contents; property: "opacity"; to: 1; duration: VisualQuality.ms(700); easing.type: Easing.OutCubic } }
        Timer { interval: 4000; running: contents.opacity < 1 && !settleIn.running; onTriggered: contents.opacity = 1 }
    }
    // The awakening sweep: a band of light runs the bar's top edge once as the shell starts.
    Rectangle {
        id: sweepBand
        visible: sweepRun.running
        y: 5; height: 2; width: 320
        x: -width
        gradient: Gradient { orientation: Gradient.Horizontal
            GradientStop { position: 0; color: "transparent" }
            GradientStop { position: .5; color: Qt.alpha(Theme.green, Math.min(1, .9 * VisualQuality.effectIntensity)) }
            GradientStop { position: 1; color: "transparent" } }
        NumberAnimation { id: sweepRun; target: sweepBand; property: "x"; from: -sweepBand.width; to: root.width; duration: VisualQuality.ms(1300); easing.type: Easing.InOutQuad }
    }
}
