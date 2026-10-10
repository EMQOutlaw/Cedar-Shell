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
    // The awakening only lifts the material's light once after mapping. The
    // controls are already visible and usable before any decoration starts.
    property bool awakened: false
    onBackingWindowVisibleChanged: if (backingWindowVisible) awakenLater.start()
    Timer { id: awakenLater; interval: 220; onTriggered: root.awakenBar() }
    function awakenBar() {
        if (awakened || Config.testMode || !VisualQuality.effects) return;
        awakened = true;
        if (cedarBar) { grainAwaken.start(); rootlines.grow(); }
        else { rootlines.grow(); sweepRun.start(); }
        VisualQuality.awaken();
    }
    required property var output
    readonly property bool cedarBar: Config.barStyle === "cedar"
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
    StrataBarFrame {
        id: strata
        anchors.fill: parent
        visible: root.cedarBar
        materialOpacity: Config.barOpacity
        centerWidth: contents.item ? contents.item.centerWidth : 0
        eventAccent: VisualQuality.preset > 1 ? Theme.green : Theme.strataAccent
        SequentialAnimation {
            id: grainAwaken
            NumberAnimation { target: strata; property: "awakening"; from: 0; to: 1; duration: VisualQuality.ms(160); easing.type: Easing.OutCubic }
            NumberAnimation { target: strata; property: "awakening"; to: 0; duration: VisualQuality.ms(480); easing.type: Easing.OutCubic }
        }
    }
    Connections {
        target: VisualQuality
        function onEffectsChanged() {
            if (!VisualQuality.effects) { grainAwaken.stop(); strata.awakening = 0; sweepRun.stop(); }
        }
    }
    Rectangle {
        anchors.fill: parent
        visible: Config.barStyle !== "cedar" && !Config.barIslands
        radius: Config.barStyle === "floating" ? Config.barRadius : 0
        color: Qt.alpha(Theme.background, Config.barOpacity)
        border.width: Config.barStyle === "floating" ? 1 : 0
        border.color: Theme.border
    }
    // Strata retains CEDAR's instrument language: event-driven roots grow,
    // pulse or carry a signal, then disappear into the grain at rest.
    CedarRootlines {
        id: rootlines
        anchors.fill: parent
        anchors.margins: 6
        visible: Config.saved.barRootlines && !Config.barIslands && VisualQuality.effects
        tone: root.cedarBar ? (VisualQuality.preset > 1 ? Theme.green : Theme.strataAccent) : Theme.green
        intensity: VisualQuality.effectIntensity * (root.cedarBar && VisualQuality.preset <= 1 ? .8 : 1)
        eventOnly: root.cedarBar
        growth: 1
        readonly property bool here: Canopy.screen === root.output
        function anchorX() { const a = Canopy.anchorRect; return a ? a.x + a.width / 2 - (Config.barDetached ? Config.barMargin : 0) - 6 : width / 2; }
        function eventAccent(color) { return root.cedarBar && VisualQuality.preset <= 1 ? Qt.tint(Theme.strataAccent, Qt.alpha(color, .36)) : color; }
        // Other bar styles retain their existing current while a panel is open.
        flowing: !root.cedarBar && visible && here && Canopy.shown && !Canopy.peeking && Canopy.surfaceState !== "collapsed" && Canopy.surfaceState !== "closing"
        flowTo: anchorX()
        Connections {
            target: Canopy
            function onSurfaceStateChanged() {
                if (!rootlines.visible || !rootlines.here || Canopy.surfaceState !== "opening") return;
                const to = rootlines.anchorX();
                rootlines.trace(to < rootlines.width / 2 ? 8 : rootlines.width - 8, to, root.cedarBar ? rootlines.tone : Forest.accent);
            }
        }
        Connections {
            target: Profiles
            function onCurrentChanged() {
                if (!rootlines.visible || !root.coreHost) return;
                rootlines.pulse("centre", rootlines.eventAccent(Profiles.current ? Profiles.accentOf(Profiles.current) : Theme.green));
                if (!root.cedarBar || VisualQuality.preset > 1) rootlines.grow();
            }
        }
        Connections { target: Focus; function onActiveChanged() { if (rootlines.visible && root.coreHost) rootlines.pulse("centre", rootlines.eventAccent(Focus.active ? Theme.teal : Theme.green)); } }
        Connections { target: Shield; function onPostureChanged() { if (rootlines.visible && root.coreHost && Shield.ready) rootlines.signalTo(rootlines.width / 2, Shield.posture === "protected" ? rootlines.eventAccent(Theme.green) : Theme.amber); } }
    }
    Loader {
        id: contents
        anchors.fill: parent
        anchors.margins: 6
        active: !Config.barIslands
        sourceComponent: root.cedarBar ? strataContents : legacyContents
        opacity: 1
    }
    Component { id: strataContents; StrataBarContents { output: root.output } }
    Component { id: legacyContents; BarContents { output: root.output } }
    // The awakening sweep: a band of light runs the bar's top edge once as the shell starts.
    Rectangle {
        id: sweepBand
        visible: !root.cedarBar && sweepRun.running
        y: 5; height: 2; width: 320
        x: -width
        gradient: Gradient { orientation: Gradient.Horizontal
            GradientStop { position: 0; color: "transparent" }
            GradientStop { position: .5; color: Qt.alpha(Theme.green, Math.min(1, .9 * VisualQuality.effectIntensity)) }
            GradientStop { position: 1; color: "transparent" } }
        NumberAnimation { id: sweepRun; target: sweepBand; property: "x"; from: -sweepBand.width; to: root.width; duration: VisualQuality.ms(1300); easing.type: Easing.InOutQuad }
    }
}
