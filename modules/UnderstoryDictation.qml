import QtQuick
import Quickshell
import Quickshell.Wayland
import ".."
import "../components"
import "../components/core"
import "../services"

// Dictation beside the Understory bar. The Core pill rests while the bar is
// on the left, so while Voxtype listens or transcribes its filament grows
// sideways out of the bar beside the microphone mark instead: the same
// CoreDictation line, in the same sideways drop silhouette as every other
// surface that leaves this bar. Mapped only while Voxtype is working; it
// takes no input and casts no shadow on the desktop beneath.
PanelWindow {
    id: root
    required property var modelData
    screen: modelData
    readonly property string outputName: modelData?.name || ""
    readonly property bool requested: Config.barVertical && Dictation.active && Config.saved.coreDictation && !ShellState.locked
    property bool mapped: false
    visible: mapped
    readonly property bool sliding: VisualQuality.functionalMotion && !Config.testMode
    readonly property int reach: 272
    readonly property int span: 40
    anchors { top: true; left: true }
    margins.left: Config.barWidth
    margins.top: Math.max(0, Math.round(anchorY - span / 2 - Theme.strataCut))
    implicitWidth: reach + 4
    implicitHeight: span + 2 * Theme.strataCut
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
    function open() { aim(); closeDelay.stop(); mapped = true; if (!sliding) { drop.width = reach; return; } drop.width = 0; Qt.callLater(() => { if (root.requested) drop.width = root.reach; }); }
    function shut() { if (!sliding) { mapped = false; return; } drop.width = 0; closeDelay.restart(); }
    onRequestedChanged: requested ? open() : shut()
    Component.onCompleted: if (requested) { aim(); mapped = true; drop.width = reach; }
    Timer { id: closeDelay; interval: VisualQuality.ms(Theme.morphShrink) + 40; onTriggered: if (!root.requested) root.mapped = false }
    Item {
        id: drop
        x: 0; y: Theme.strataCut; height: root.span
        width: 0
        clip: true
        Behavior on width { enabled: root.sliding; NumberAnimation { duration: VisualQuality.ms(drop.width > 0 ? Theme.morphGrow : Theme.morphShrink); easing.type: Easing.OutCubic } }
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
        CoreDictation {
            objectName: "understoryDictation"
            x: 14; width: root.reach - 28
            height: 26
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
