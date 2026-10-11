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
        grainAwaken.start();
        rootlines.grow();
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
    exclusiveZone: Config.barHeight
    color: Theme.transparent
    WlrLayershell.namespace: "cedar-bar"
    WlrLayershell.layer: WlrLayer.Top
    readonly property bool coreHost: CoreService.enabled && CoreService.hostName === output.name
    readonly property var monitor: Hyprland.monitorFor(screen)
    readonly property var battery: UPower.displayDevice
    StrataBarFrame {
        id: strata
        anchors.fill: parent
        materialOpacity: Config.barOpacity
        centerWidth: contents.centerWidth
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
            if (!VisualQuality.effects) { grainAwaken.stop(); strata.awakening = 0; }
        }
    }
    // Strata retains CEDAR's instrument language: event-driven roots grow,
    // pulse or carry a signal, then disappear into the grain at rest.
    CedarRootlines {
        id: rootlines
        anchors.fill: parent
        anchors.margins: 6
        visible: Config.saved.barRootlines && VisualQuality.effects
        tone: VisualQuality.preset > 1 ? Theme.green : Theme.strataAccent
        intensity: VisualQuality.effectIntensity * (VisualQuality.preset <= 1 ? .8 : 1)
        eventOnly: true
        growth: 1
        readonly property bool here: Canopy.screen === root.output
        function anchorX() { const a = Canopy.anchorRect; return a ? a.x + a.width / 2 - 6 : width / 2; }
        function eventAccent(color) { return VisualQuality.preset <= 1 ? Qt.tint(Theme.strataAccent, Qt.alpha(color, .36)) : color; }
        Connections {
            target: Canopy
            function onSurfaceStateChanged() {
                if (!rootlines.visible || !rootlines.here || Canopy.surfaceState !== "opening") return;
                const to = rootlines.anchorX();
                rootlines.trace(to < rootlines.width / 2 ? 8 : rootlines.width - 8, to, rootlines.tone);
            }
        }
        Connections {
            target: Profiles
            function onCurrentChanged() {
                if (!rootlines.visible || !root.coreHost) return;
                rootlines.pulse("centre", rootlines.eventAccent(Profiles.current ? Profiles.accentOf(Profiles.current) : Theme.green));
                if (VisualQuality.preset > 1) rootlines.grow();
            }
        }
        Connections { target: Focus; function onActiveChanged() { if (rootlines.visible && root.coreHost) rootlines.pulse("centre", rootlines.eventAccent(Focus.active ? Theme.teal : Theme.green)); } }
        Connections { target: Shield; function onPostureChanged() { if (rootlines.visible && root.coreHost && Shield.ready) rootlines.signalTo(rootlines.width / 2, Shield.posture === "protected" ? rootlines.eventAccent(Theme.green) : Theme.amber); } }
    }
    StrataBarContents {
        id: contents
        anchors.fill: parent
        anchors.margins: 6
        output: root.output
    }
}
