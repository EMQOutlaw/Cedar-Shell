pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import ".."
import "../components"
import "../components/core"
import "../services"

// Dictation beside the Understory bar only when the shared presenter policy
// selects it (Core disabled). While Voxtype works its filament grows
// sideways out of the bar beside the microphone mark instead: the same
// CoreDictation line, in the same sideways drop silhouette as every other
// surface that leaves this bar. Mapped only while Voxtype is working; it
// takes no input and casts no shadow on the desktop beneath.
PanelWindow {
    id: root
    required property var modelData
    screen: modelData
    readonly property string outputName: modelData?.name || ""
    readonly property bool covered: (Hyprland.monitorFor(modelData)?.activeWorkspace?.hasFullscreen ?? false)
        || (Config.fullscreenFocused && Config.fullscreenScreen === outputName) || Gaming.active
    readonly property bool allowed: Dictation.presenter === "understory" && Dictation.active && !ShellState.locked && !!modelData
    readonly property bool requested: allowed && !covered
    readonly property bool dotOnly: allowed && covered
    readonly property color indicatorColor: Dictation.recording ? Theme.ember : Theme.amber
    readonly property int dotExtent: Theme.spaceSm + Theme.spaceXs * 2
    function dotLeftFor(outputWidth) { return Math.max(0, Math.min(Config.barWidth + Theme.spaceXs, outputWidth - dotExtent)); }
    readonly property real surfaceLeft: dotOnly ? dotLeftFor(modelData?.width || dotExtent) : Config.barWidth
    readonly property real surfaceTop: dotOnly ? Math.max(0, Math.min(Theme.spaceXs, (modelData?.height || dotExtent) - implicitHeight)) : Math.max(0, Math.min((modelData?.height || 800) - implicitHeight, Math.round(anchorY - span / 2 - Theme.strataCut)))
    readonly property bool closing: closeDelay.running
    readonly property bool animating: widthAnimation.running
    property bool mapped: false
    visible: mapped || dotOnly
    readonly property bool sliding: VisualQuality.functionalMotion && !Config.testMode && mapped && !ShellState.locked && !covered
    function widthFor(outputWidth) { return Math.max(1, Math.min(276, outputWidth - Config.barWidth)); }
    readonly property int reach: Math.max(1, widthFor(modelData?.width || 800) - 4)
    readonly property bool contentLoaded: dictationContent.item !== null
    readonly property int span: 40
    anchors { top: true; left: true }
    margins.left: surfaceLeft
    margins.top: surfaceTop
    implicitWidth: dotOnly ? Math.max(1, Math.min(dotExtent, modelData?.width || dotExtent)) : reach + 4
    implicitHeight: dotOnly ? Math.max(1, Math.min(dotExtent, modelData?.height || dotExtent)) : span + 2 * Theme.strataCut
    color: Theme.transparent
    exclusionMode: ExclusionMode.Ignore
    mask: Region {}
    WlrLayershell.namespace: "cedar-dictation"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    // Where the microphone mark sits on the bar: its screen y, or the bar's middle.
    // Read when the surface opens, not bound: the provider measures the live
    // item and nothing about that measurement is a property to depend on.
    property real anchorY: (modelData?.height || 800) / 2
    function aim() {
        const provider = Canopy.anchorProviders["dictation@" + outputName] || null;
        const rect = provider ? provider() : null;
        if (rect && isFinite(rect.x) && rect.width > 0) anchorY = rect.x + rect.width / 2;
    }
    function moveWidth(value) {
        widthAnimation.stop();
        if (!sliding) { drop.width = value; return; }
        widthAnimation.from = drop.width; widthAnimation.to = value;
        widthAnimation.duration = VisualQuality.ms(value > 0 ? Theme.morphGrow : Theme.morphShrink);
        widthAnimation.start();
    }
    function open() { aim(); closeDelay.stop(); mapped = true; drop.width = 0; moveWidth(reach); }
    function stopPresentation() { closeDelay.stop(); widthAnimation.stop(); mapped = false; drop.width = 0; }
    function shut() { if (!sliding) { stopPresentation(); return; } moveWidth(0); closeDelay.restart(); }
    onCoveredChanged: if (covered) stopPresentation()
    onVisibleChanged: if (!visible) { closeDelay.stop(); widthAnimation.stop(); }
    onRequestedChanged: requested ? open() : shut()
    Component.onCompleted: if (requested) { aim(); mapped = true; drop.width = reach; }
    Connections { target: ShellState; function onLockedChanged() { if (ShellState.locked) root.stopPresentation() } }
    Timer { id: closeDelay; interval: VisualQuality.ms(Theme.morphShrink) + 40; onTriggered: if (!root.requested) root.mapped = false }
    // Covered privacy indicator only: no input, waveform, level consumer or motion.
    Rectangle {
        visible: root.dotOnly
        anchors.centerIn: parent
        width: Math.min(Theme.spaceSm, root.width); height: Math.min(Theme.spaceSm, root.height)
        radius: Math.min(width, height) / 2
        color: root.indicatorColor
        Accessible.role: Accessible.Indicator
        Accessible.name: Dictation.recording ? "Dictation listening" : "Dictation transcribing"
    }
    Item {
        id: drop
        visible: !root.dotOnly
        x: 0; y: Theme.strataCut; height: root.span
        width: 0
        clip: true
        NumberAnimation { id: widthAnimation; target: drop; property: "width"; easing.type: Easing.OutCubic }
        DropFrame {
            anchors.fill: parent
            side: true
            cut: Theme.strataCut
            join: Theme.strataCut
            fill: Qt.alpha(Theme.strataFoundation, Math.max(.96, Config.panelOpacity))
            stroke: Qt.alpha(Dictation.recording ? Theme.ember : Theme.amber, .35)
            grainColor: Theme.strataGrain
            lit: Dictation.recording
            growing: false
        }
        Loader {
            id: dictationContent
            active: root.mapped && root.requested
            x: 14; width: Math.max(0, root.reach - 28)
            height: 26
            anchors.verticalCenter: parent.verticalCenter
            sourceComponent: CoreDictation { objectName: "understoryDictation" }
        }
    }
}
