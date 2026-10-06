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
    implicitHeight: Math.min((modelData?.height || 800) - margins.top - 16, Config.barHeight + 724)
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
        const w = Canopy.peeking ? 360 : Canopy.standalone ? 400 : ["audio", "system"].includes(topic) ? 760 : topic === "quick" ? 420 : 520;
        return Math.min(width - 24, w);
    }
    function topicHeight(topic) {
        const cap = Math.min(height - barJoin - 16, Canopy.peeking ? 160 : topic === "quick" ? 660 : 700);
        return Math.max(Canopy.peeking ? 120 : 160, Math.min(cap, panel.preferredHeight));
    }
    // Where the open panel sits: centred on its control, else centred on the screen.
    function topicX(w) {
        const a = Canopy.anchorRect;
        const centre = a ? a.x + a.width / 2 - sideInset : width / 2;
        return Math.round(Math.max(12, Math.min(centre - w / 2, width - w - 12)));
    }
    // The control's rect in window coordinates, the shape the drop grows from and shrinks to.
    function controlRect() {
        const a = Canopy.anchorRect;
        if (a)
            return { x: a.x - sideInset, width: a.width };
        return { x: (width - 150) / 2, width: 150 };
    }
    function snap(x, w, h) {
        drop.animate = false;
        drop.x = x; drop.width = w; drop.height = h;
        drop.animate = true;
    }
    function retarget() {
        if (!root.requested)
            return;
        const w = topicWidth(drop.topic);
        drop.growing = topicHeight(drop.topic) > drop.height;
        drop.x = topicX(w); drop.width = w; drop.height = topicHeight(drop.topic);
    }
    function open() {
        closeDelay.stop();
        swap.stop();
        const c = controlRect();
        mapped = true;
        drop.topic = Canopy.topic;
        snap(c.x, c.width, 0);
        drop.reveal = 0;
        Qt.callLater(() => { root.retarget(); openReveal.restart(); });
    }
    function shut() {
        openReveal.stop();
        swap.stop();
        const c = controlRect();
        drop.growing = false;
        drop.reveal = 0;
        drop.x = c.x; drop.width = c.width; drop.height = 0;
        if (morphing)
            closeDelay.restart();
        else
            mapped = false;
    }
    onRequestedChanged: requested ? open() : shut()
    Component.onCompleted: if (requested) { mapped = true; drop.topic = Canopy.topic; drop.reveal = 1; snap(topicX(topicWidth(drop.topic)), topicWidth(drop.topic), topicHeight(drop.topic)); }
    Timer { id: closeDelay; interval: 240; onTriggered: if (!root.requested) root.mapped = false }
    Connections {
        target: Canopy
        function onTopicChanged() { if (root.requested && drop.topic !== Canopy.topic) swap.restart(); }
        function onPeekingChanged() { root.retarget(); }
        function onAnchorRectChanged() { root.retarget(); }
    }
    Connections { target: ShellState; function onLockedChanged() { if (ShellState.locked) { closeDelay.stop(); root.mapped = false; } } }
    onWidthChanged: retarget()

    // ---- the drop ----------------------------------------------------------
    Item {
        id: drop
        property string topic: Canopy.topic
        property bool animate: true
        property bool growing: true
        property real reveal: 0
        readonly property real cut: 12
        readonly property real longCut: Math.round(cut * 16 / 9)
        y: root.barJoin
        Behavior on x { enabled: root.morphing && drop.animate; NumberAnimation { duration: 260; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.38, 1.21, 0.22, 1.0, 1, 1] } }
        Behavior on width { enabled: root.morphing && drop.animate; NumberAnimation { duration: 260; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.38, 1.21, 0.22, 1.0, 1, 1] } }
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
        // Topic change: fade, swap the content, re-aim the shape, fade back in.
        SequentialAnimation {
            id: swap
            NumberAnimation { target: drop; property: "reveal"; to: 0; duration: root.morphing ? 90 : 0 }
            ScriptAction { script: { drop.topic = Canopy.topic; root.retarget(); } }
            PauseAnimation { duration: root.morphing ? 80 : 0 }
            NumberAnimation { target: drop; property: "reveal"; to: 1; duration: root.morphing ? 220 : 0; easing.type: Easing.OutCubic }
        }
        Behavior on reveal { enabled: root.morphing && !openReveal.running && !swap.running; NumberAnimation { duration: 90 } }
        CanopyPanel {
            id: panel
            anchors.fill: parent
            framed: false
            topic: drop.topic
            active: root.requested
            visible: drop.reveal > 0 || root.requested
            opacity: drop.reveal
            onPreferredHeightChanged: root.retarget()
        }
    }
}
