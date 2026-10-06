import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import ".."
import "../components"
import "../services"

// The one surface that drops from the bar. A full-width transparent window
// holds a single "drop" whose geometry is assigned, never bound: it grows out
// of the control that opened it, joins the bar with inverted chamfers, morphs
// to the next topic's size and position, and shrinks back into its control
// when closed. Input is masked to the drop, so the rest of the bar stays live.
PanelWindow {
    id: root
    required property var modelData
    screen: modelData
    readonly property bool requested: Canopy.shown && Canopy.screen === modelData
    property bool mapped: false
    visible: mapped
    readonly property bool morphing: !Theme.reducedMotion && !Config.testMode
    readonly property real sideInset: Config.barDetached ? Config.barMargin : 0
    // The bar frame sits five pixels inside the bar window; the drop joins its bottom edge.
    readonly property real barJoin: Config.barHeight - (Config.barStyle === "cedar" || Config.barIslands ? 5 : 0)
    anchors { top: true; left: true; right: true }
    margins.top: Config.barDetached ? Config.barMargin : 0
    margins.left: sideInset
    margins.right: sideInset
    // Tall enough for Field Station; the surface is transparent and masked to the drop.
    implicitHeight: (modelData?.height || 800) - margins.top - 16
    color: Theme.transparent
    exclusionMode: ExclusionMode.Ignore
    mask: Region { item: drop }
    WlrLayershell.namespace: "cedar-canopy"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: requested && !Canopy.pinned && !Canopy.peeking ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    HyprlandFocusGrab {
        windows: [root].concat(Canopy.controlWindows.filter(window => window.visible))
        active: root.requested && !Canopy.pinned && !Canopy.peeking && !Config.testMode
        onCleared: if (root.visible && !Canopy.pinned && !Canopy.peeking)
            Canopy.close()
    }
    contentItem.focus: true
    contentItem.Keys.onEscapePressed: Canopy.close()

    // ---- targets -----------------------------------------------------------
    function topicWidth(topic) {
        const w = Canopy.peeking ? 360 : topic === "station" ? 760 : topic === "go" ? 480 : topic === "power" ? 520 : drop.standalone ? 400 : ["audio", "system"].includes(topic) ? 760 : topic === "quick" ? 420 : 520;
        return Math.min(width - 24, w);
    }
    function topicHeight(topic) {
        const cap = Math.min(height - barJoin - 16, Canopy.peeking ? 160 : topic === "station" ? 1200 : topic === "go" ? 760 : topic === "quick" ? 660 : 700);
        return Math.max(Canopy.peeking ? 120 : 160, Math.min(cap, panel.preferredHeight));
    }
    // Where the open panel sits: centred on its control, else centred on the screen.
    function topicX(w) {
        const a = Canopy.anchorRect;
        const centre = a ? a.x + a.width / 2 - sideInset : width / 2;
        return Math.round(Math.max(12, Math.min(centre - w / 2, width - w - 12)));
    }
    function snap(x, w, h) {
        drop.animate = false;
        drop.x = x; drop.width = w; drop.height = h;
        drop.animate = true;
    }
    // Horizontal geometry settles first; only the height moves, top-down.
    function aim() {
        const w = topicWidth(drop.topic);
        snap(topicX(w), w, drop.height);
    }
    property bool switching: false
    function retarget(force = false) {
        if (!root.requested || (switching && !force))
            return;
        const w = topicWidth(drop.topic);
        drop.growing = topicHeight(drop.topic) > drop.height;
        drop.x = topicX(w); drop.width = w; drop.height = topicHeight(drop.topic);
    }
    function open() {
        closeDelay.stop();
        swap.stop();
        switching = false;
        mapped = true;
        drop.topic = Canopy.topic;
        drop.standalone = Canopy.standalone;
        const w = topicWidth(drop.topic);
        snap(topicX(w), w, 0);
        drop.reveal = 0;
        Qt.callLater(() => { root.retarget(); openReveal.restart(); Canopy.enter(); });
    }
    // Collapse straight back up into the bar.
    function collapse() {
        openReveal.stop();
        drop.growing = false;
        drop.reveal = 0;
        drop.height = 0;
    }
    function shut() {
        swap.stop();
        switching = false;
        collapse();
        if (morphing)
            closeDelay.restart();
        else
            mapped = false;
    }
    onRequestedChanged: requested ? open() : shut()
    Component.onCompleted: if (requested) { mapped = true; drop.topic = Canopy.topic; drop.standalone = Canopy.standalone; drop.reveal = 1; snap(topicX(topicWidth(drop.topic)), topicWidth(drop.topic), topicHeight(drop.topic)); }
    // Follow late content heights and anchor moves, but never during a switch
    // or a close: deferred so `requested` has settled before it is read.
    function reaim() { Qt.callLater(root.retargetIfOpen); }
    function retargetIfOpen() { if (root.requested && !switching) root.retarget(); }
    Timer { id: closeDelay; interval: 240; onTriggered: if (!root.requested) root.mapped = false }
    Connections {
        target: Canopy
        function onTopicChanged() { if (root.requested && drop.topic !== Canopy.topic) swap.restart(); }
        function onPeekingChanged() { root.reaim(); }
        function onAnchorRectChanged() { root.reaim(); }
    }
    Connections { target: ShellState; function onLockedChanged() { if (ShellState.locked) { closeDelay.stop(); root.mapped = false; } } }
    onWidthChanged: reaim()

    // ---- the drop ----------------------------------------------------------
    Item {
        id: drop
        property string topic: Canopy.topic
        property bool standalone: Canopy.standalone
        property bool animate: true
        property bool growing: true
        property real reveal: 0
        readonly property real cut: 12
        readonly property real longCut: Math.round(cut * 16 / 9)
        y: root.barJoin
        Behavior on x { enabled: root.morphing && drop.animate; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on width { enabled: root.morphing && drop.animate; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on height {
            enabled: root.morphing && drop.animate
            NumberAnimation {
                duration: drop.growing ? 320 : 200
                easing.type: Easing.BezierSpline
                easing.bezierCurve: drop.growing ? [0.38, 1.21, 0.22, 1.0, 1, 1] : [0.05, 0.7, 0.1, 1.0, 1, 1]
            }
        }
        // Silhouette: flat top that flares into the bar with 45° wedges on both
        // sides, the long cut bottom-left and the short cut bottom-right.
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeWidth: 0
                strokeColor: "transparent"
                fillColor: Qt.alpha(Theme.background, Math.max(.96, Config.panelOpacity))
                startX: -drop.cut; startY: -1
                PathLine { x: drop.width + drop.cut; y: -1 }
                PathLine { x: drop.width; y: drop.cut }
                PathLine { x: drop.width; y: drop.height - drop.cut }
                PathLine { x: drop.width - drop.cut; y: drop.height }
                PathLine { x: drop.longCut; y: drop.height }
                PathLine { x: 0; y: drop.height - drop.longCut }
                PathLine { x: 0; y: drop.cut }
                PathLine { x: -drop.cut; y: -1 }
            }
            // The outline leaves the top open, so the surface reads as the bar itself.
            ShapePath {
                strokeWidth: 1
                strokeColor: Qt.alpha(Forest.accent, .25)
                fillColor: "transparent"
                startX: -drop.cut; startY: -1
                PathLine { x: 0; y: drop.cut }
                PathLine { x: 0; y: drop.height - drop.longCut }
                PathLine { x: drop.longCut; y: drop.height }
                PathLine { x: drop.width - drop.cut; y: drop.height }
                PathLine { x: drop.width; y: drop.height - drop.cut }
                PathLine { x: drop.width; y: drop.cut }
                PathLine { x: drop.width + drop.cut; y: -1 }
            }
        }
        // Content fades in once the shape is on its way, and out ahead of the shrink.
        SequentialAnimation {
            id: openReveal
            PauseAnimation { duration: root.morphing ? 110 : 0 }
            NumberAnimation { target: drop; property: "reveal"; to: 1; duration: root.morphing ? 220 : 0; easing.type: Easing.OutCubic }
        }
        // Topic change: every panel is its own. The open one collapses back up
        // into the bar, then the next one drops from its own control.
        SequentialAnimation {
            id: swap
            ScriptAction { script: { root.switching = true; root.collapse(); } }
            PauseAnimation { duration: root.morphing ? 210 : 0 }
            ScriptAction { script: { drop.topic = Canopy.topic; drop.standalone = Canopy.standalone; root.aim(); } }
            PauseAnimation { duration: root.morphing ? 40 : 0 }
            ScriptAction { script: { root.switching = false; root.retarget(); Canopy.enter(); } }
            PauseAnimation { duration: root.morphing ? 110 : 0 }
            NumberAnimation { target: drop; property: "reveal"; to: 1; duration: root.morphing ? 220 : 0; easing.type: Easing.OutCubic }
        }
        Behavior on reveal { enabled: root.morphing && !openReveal.running && !swap.running; NumberAnimation { duration: 90 } }
        CanopyPanel {
            id: panel
            anchors.fill: parent
            framed: false
            topic: drop.topic
            standalone: drop.standalone
            active: root.requested
            visible: drop.reveal > 0 || root.requested
            opacity: drop.reveal
            onPreferredHeightChanged: root.reaim()
        }
    }
}
