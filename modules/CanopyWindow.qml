import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import ".."
import "../components"
import "../services"
import "../components/core/StrataGeometry.js" as Strata

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
        const w = Canopy.peeking ? 360 : topic === "workspaces" ? 1040 : topic === "station" ? 760 : topic === "go" ? 480 : topic === "power" ? 520 : drop.standalone ? 400 : ["audio", "system"].includes(topic) ? 760 : topic === "startup" ? 620 : topic === "quick" ? 560 : 520;
        return Math.min(width - 24, w);
    }
    function topicHeight(topic) {
        const cap = Math.min(height - barJoin - 16, Canopy.peeking ? 160 : topic === "station" ? 1200 : topic === "workspaces" ? 900 : topic === "go" ? 760 : topic === "quick" ? 660 : 700);
        return Math.max(Canopy.peeking ? 120 : 160, Math.min(cap, panel.preferredHeight));
    }
    // Where the open panel sits: centred on its control, else centred on the
    // screen, decided by the geometry model and then only interpolated.
    function targetFor(topic) {
        return Strata.target({ barWidth: width, anchor: Canopy.anchorRect, wantedWidth: topicWidth(topic), wantedHeight: topicHeight(topic),
                               availableHeight: height - barJoin - 16, sideInset: sideInset, edge: 12, minimumHeight: Canopy.peeking ? 120 : 160 });
    }
    function topicX(w) { return Strata.panelX(width, Canopy.anchorRect, w, sideInset, 12); }
    function setState(value) { Canopy.surfaceState = value; }
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
        const t = targetFor(drop.topic);
        Canopy.surfaceRect = t;
        drop.growing = t.height > drop.height;
        drop.x = t.x; drop.width = t.width; drop.height = t.height;
    }
    function open() {
        closeDelay.stop();
        swap.stop(); morph.stop();
        switching = false;
        mapped = true;
        drop.topic = Canopy.topic;
        drop.standalone = Canopy.standalone;
        const w = topicWidth(drop.topic);
        snap(topicX(w), w, 0);
        drop.reveal = 0;
        setState("opening");
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
        swap.stop(); morph.stop();
        switching = false;
        setState("closing");
        collapse();
        if (morphing)
            closeDelay.restart();
        else { mapped = false; setState("collapsed"); }
    }
    onRequestedChanged: requested ? open() : shut()
    Component.onCompleted: if (requested) { mapped = true; drop.topic = Canopy.topic; drop.standalone = Canopy.standalone; drop.reveal = 1; snap(topicX(topicWidth(drop.topic)), topicWidth(drop.topic), topicHeight(drop.topic)); }
    // Follow late content heights and anchor moves, but never during a switch
    // or a close: deferred so `requested` has settled before it is read.
    function reaim() { Qt.callLater(root.retargetIfOpen); }
    function retargetIfOpen() { if (root.requested && !switching) root.retarget(); }
    Timer { id: closeDelay; interval: VisualQuality.ms(Theme.morphShrink) + 40; onTriggered: if (!root.requested) { root.mapped = false; root.setState("collapsed"); } }
    // A topic change while open: a tab that shares the open drop's origin
    // morphs in place from wherever the geometry is; a different control
    // folds the drop back into the bar and grows it again from there.
    function switchTopic() {
        if (!root.requested || drop.topic === Canopy.topic) return;
        const next = targetFor(Canopy.topic);
        if (Strata.sharesOrigin(Canopy.surfaceRect, next)) morph.restart(); else swap.restart();
    }
    Connections {
        target: Canopy
        function onTopicChanged() { root.switchTopic(); }
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
        Behavior on x { enabled: root.morphing && drop.animate; NumberAnimation { duration: VisualQuality.ms(Theme.expand * .75); easing.type: Easing.OutCubic } }
        Behavior on width { enabled: root.morphing && drop.animate; NumberAnimation { duration: VisualQuality.ms(Theme.expand * .75); easing.type: Easing.OutCubic } }
        Behavior on height {
            enabled: root.morphing && drop.animate
            NumberAnimation {
                duration: VisualQuality.ms(drop.growing ? Theme.morphGrow : Theme.morphShrink)
                easing.type: Easing.BezierSpline
                easing.bezierCurve: drop.growing ? [0.38, 1.21, 0.22, 1.0, 1, 1] : [0.05, 0.7, 0.1, 1.0, 1, 1]
            }
        }
        // Silhouette: the bar's lower edge bends down through concave fillets
        // and becomes the drop's sides (components/DropFrame.qml).
        DropFrame {
            anchors.fill: parent
            cut: drop.cut
            join: drop.cut
            fill: Qt.alpha(Theme.background, Math.max(.96, Config.panelOpacity))
            stroke: Qt.alpha(Forest.accent, .25)
            lit: Canopy.surfaceState === "opening" || Canopy.surfaceState === "retargeting"
            growing: drop.growing && (Canopy.surfaceState === "opening" || Canopy.surfaceState === "retargeting")
        }
        // Content fades in once the shape is on its way, and out ahead of the shrink.
        SequentialAnimation {
            id: openReveal
            PauseAnimation { duration: root.morphing ? VisualQuality.ms(Theme.revealDelay) : 0 }
            NumberAnimation { target: drop; property: "reveal"; to: 1; duration: root.morphing ? VisualQuality.ms(Theme.reveal) : 0; easing.type: Easing.OutCubic }
            ScriptAction { script: if (root.requested) root.setState("expanded") }
        }
        // In-place retarget: content leaves, the surface moves to the next
        // geometry from where it is, the next content arrives.
        SequentialAnimation {
            id: morph
            ScriptAction { script: { root.switching = true; root.setState("retargeting"); } }
            NumberAnimation { target: drop; property: "reveal"; to: 0; duration: root.morphing ? VisualQuality.ms(Theme.conceal) : 0 }
            ScriptAction { script: { drop.topic = Canopy.topic; drop.standalone = Canopy.standalone; root.switching = false; root.retarget(); Canopy.enter(); } }
            PauseAnimation { duration: root.morphing ? VisualQuality.ms(Theme.revealDelay) : 0 }
            NumberAnimation { target: drop; property: "reveal"; to: 1; duration: root.morphing ? VisualQuality.ms(Theme.reveal) : 0; easing.type: Easing.OutCubic }
            ScriptAction { script: if (root.requested) root.setState("expanded") }
        }
        // Topic change: every panel is its own. The open one collapses back up
        // into the bar, then the next one drops from its own control.
        SequentialAnimation {
            id: swap
            ScriptAction { script: { root.switching = true; root.setState("retargeting"); root.collapse(); } }
            PauseAnimation { duration: root.morphing ? VisualQuality.ms(Theme.morphShrink) + 10 : 0 }
            ScriptAction { script: { drop.topic = Canopy.topic; drop.standalone = Canopy.standalone; root.aim(); } }
            PauseAnimation { duration: root.morphing ? 40 : 0 }
            ScriptAction { script: { root.switching = false; root.retarget(); Canopy.enter(); } }
            PauseAnimation { duration: root.morphing ? VisualQuality.ms(Theme.revealDelay) : 0 }
            NumberAnimation { target: drop; property: "reveal"; to: 1; duration: root.morphing ? VisualQuality.ms(Theme.reveal) : 0; easing.type: Easing.OutCubic }
            ScriptAction { script: if (root.requested) root.setState("expanded") }
        }
        Behavior on reveal { enabled: root.morphing && !openReveal.running && !swap.running && !morph.running; NumberAnimation { duration: VisualQuality.ms(Theme.conceal) } }
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
