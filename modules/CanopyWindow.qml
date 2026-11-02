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
    readonly property bool morphing: VisualQuality.functionalMotion && !Config.testMode
    readonly property real sideInset: Config.barDetached ? Config.barMargin : 0
    // The bar frame sits five pixels inside the bar window; the drop joins its bottom edge.
    readonly property real barJoin: side ? 0 : Config.barHeight - (Config.barStyle === "cedar" || Config.barIslands ? 5 : 0)
    // With the bar on the left the drop grows sideways out of it: the geometry
    // below runs along the bar (`along`/`span`) and away from it (`reach`),
    // and these two flags decide which screen axis each one is.
    readonly property bool side: Config.barVertical
    anchors { top: true; left: true; right: !root.side; bottom: root.side }
    margins.top: Config.barDetached ? Config.barMargin : 0
    margins.left: sideInset + Config.barWidth
    margins.right: sideInset
    // Tall enough for Field Station; the surface is transparent and masked to the drop.
    implicitHeight: (modelData?.height || 800) - margins.top - 16
    implicitWidth: (modelData?.width || 1200) - Config.barWidth - 8
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
        const w = Canopy.peeking ? 360 : topic === "workspaces" ? 1040 : topic === "station" ? 760 : topic === "go" ? (Go.dmenuActive && Go.dmenuWidth ? Math.max(480, Math.min(720, Math.round(Go.dmenuWidth * 1.15))) : 480) : topic === "keybinds" ? 700 : topic === "power" ? 520 : drop.standalone ? 400 : ["audio", "system"].includes(topic) ? 760 : topic === "startup" ? 620 : topic === "quick" ? 560 : 520;
        return Math.min(width - (side ? 16 : 24), w);
    }
    // A drop hugs its panel. The only ceiling is what fits under the bar on
    // this output, so an instrument shows whole wherever the screen allows;
    // only a panel taller than that (a long Connections list, every keybind)
    // scrolls inside the drop. A peek stays a glance.
    function topicHeight() {
        const available = side ? height - 24 : height - barJoin - 16;
        const cap = Canopy.peeking ? Math.min(available, 160) : available;
        return Math.max(Canopy.peeking ? 120 : 160, Math.min(cap, panel.preferredHeight));
    }
    // Where the open panel sits: centred on its control, else centred on the
    // screen, decided by the geometry model and then only interpolated.
    // The bar's length, the panel's size along it and away from it.
    readonly property real extent: side ? height : width
    function wantedSpan(topic) { return side ? topicHeight() : topicWidth(topic); }
    function wantedReach(topic) { return side ? topicWidth(topic) : topicHeight(); }
    function targetFor(topic) {
        return Strata.target({ barWidth: extent, anchor: Canopy.anchorRect, wantedWidth: wantedSpan(topic), wantedHeight: wantedReach(topic),
                               availableHeight: side ? width - 16 : height - barJoin - 16, sideInset: side ? 0 : sideInset, edge: 12,
                               minimumHeight: side ? Math.min(width - 16, 320) : Canopy.peeking ? 120 : 160 });
    }
    function panelAlong(s) { return Strata.panelX(extent, Canopy.anchorRect, s, side ? 0 : sideInset, 12); }
    function setState(value) { Canopy.surfaceState = value; }
    function snap(a, s, r) {
        drop.animate = false;
        drop.along = a; drop.span = s; drop.reach = r;
        drop.animate = true;
    }
    // Geometry along the bar settles first; only the reach moves, outwards.
    function aim() {
        const s = wantedSpan(drop.topic);
        snap(panelAlong(s), s, drop.reach);
    }
    property bool switching: false
    function retarget(force = false) {
        if (!root.requested || (switching && !force))
            return;
        const t = targetFor(drop.topic);
        Canopy.surfaceRect = t;
        drop.growing = t.height > drop.reach;
        drop.targetReach = t.height;
        drop.along = t.x; drop.span = t.width; drop.reach = t.height;
    }
    function open() {
        const continuing = mapped && drop.reach > 0;
        closeDelay.stop();
        openReveal.stop(); swap.stop(); morph.stop();
        switching = false;
        mapped = true;
        drop.topic = Canopy.topic;
        drop.standalone = Canopy.standalone;
        const s = wantedSpan(drop.topic);
        if (!continuing) {
            snap(panelAlong(s), s, 0);
            drop.reveal = 0;
        }
        setState("opening");
        // A still-mapped close is reversed from its current size and opacity.
        // Only a completely hidden surface starts at zero. Guard deferred work
        // so an immediate close cannot restart the reveal behind its back.
        Qt.callLater(() => {
            if (!root.requested) return;
            root.retarget(); openReveal.restart(); Canopy.enter();
        });
    }
    // Collapse straight back up into the bar.
    function collapse() {
        openReveal.stop();
        drop.growing = false;
        drop.reveal = 0;
        drop.reach = 0;
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
    Component.onCompleted: if (requested) { mapped = true; drop.topic = Canopy.topic; drop.standalone = Canopy.standalone; drop.reveal = 1; const s = wantedSpan(drop.topic); drop.targetReach = wantedReach(drop.topic); snap(panelAlong(s), s, drop.targetReach); }
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
        openReveal.stop(); morph.stop(); swap.stop();
        if (Strata.sharesOrigin(Canopy.surfaceRect, next)) morph.restart(); else swap.restart();
    }
    Connections {
        target: Canopy
        function onTopicChanged() { root.switchTopic(); }
        function onPeekingChanged() { root.reaim(); }
        function onAnchorRectChanged() { root.reaim(); }
    }
    Connections { target: ShellState; function onLockedChanged() { if (ShellState.locked) { closeDelay.stop(); root.mapped = false; } } }
    // While this output's drop is mapped and drawing the field, the bar leaves
    // its edge stroke to the drop across the frame's padded extent.
    // Published by assignment: a Binding with `when` on the singleton did not
    // restore the empty seam once the drop unmapped (2026-10-29).
    readonly property var seam: mapped && frame.field ? ({ from: drop.along + (side ? 0 : sideInset) - frame.padAlong, to: drop.along + (side ? 0 : sideInset) + drop.span + frame.padAlong }) : ({ from: 0, to: 0 })
    // Only this output's drop publishes, and only the window the singleton
    // records as the seam's owner clears it, so an output finishing its close
    // after another has published cannot erase the new seam.
    onSeamChanged: publishSeam()
    onMappedChanged: publishSeam()
    function publishSeam() {
        if (mapped && Canopy.screen === modelData && seam.to > seam.from) { Canopy.surfaceSeam = seam; Canopy.surfaceSeamOwner = root; }
        else if (Canopy.surfaceSeamOwner === root) { Canopy.surfaceSeam = ({ from: 0, to: 0 }); Canopy.surfaceSeamOwner = null; }
    }
    Component.onDestruction: {
        if (Canopy.surfaceSeamOwner === root) { Canopy.surfaceSeam = ({ from: 0, to: 0 }); Canopy.surfaceSeamOwner = null; }
        if (Canopy.fieldOwner === root) { Canopy.field = null; Canopy.fieldOwner = null; }
    }
    // The bar's plate in drop coordinates, and how far the drop's body reaches
    // up into it: it begins behind the plate's lower cuts, so the first pixels
    // of growth are the plate's edge swelling, not a plate hung beneath it.
    readonly property real plateInset: Config.barStyle === "cedar" || Config.barIslands ? Theme.strataInset : 0
    readonly property real emerge: side ? 0 : Math.max(0, barJoin - plateInset - Theme.strataCut)
    readonly property vector4d plateRect: side ? Qt.vector4d(-1e4, height / 2 - drop.along, 1e4, 1e5)
                                               : Qt.vector4d(width / 2 - drop.along, (plateInset + barJoin) / 2 - barJoin, (width - 2 * plateInset) / 2, (barJoin - plateInset) / 2)
    readonly property vector4d plateCuts: side ? Qt.vector4d(0, 0, 0, 0) : Qt.vector4d(0, Theme.strataCut, 0, Theme.strataCut)
    // The field the bar's window draws its band of, in bar-window px.
    readonly property var field: mapped && frame.field && !side ? ({
        x: drop.along + sideInset, top: barJoin - emerge, width: drop.span, bottom: barJoin + drop.reach,
        m00: frame.m00, m01: frame.m01, m11: frame.m11, ox: drop.along + sideInset + drop.span / 2, oy: barJoin,
        lit: frame.lit
    }) : null
    onFieldChanged: publishField()
    function publishField() {
        if (field && Canopy.screen === modelData) { Canopy.field = field; Canopy.fieldOwner = root; }
        else if (Canopy.fieldOwner === root) { Canopy.field = null; Canopy.fieldOwner = null; }
    }
    onWidthChanged: reaim()
    onHeightChanged: reaim()
    onBarJoinChanged: reaim()

    // ---- the drop ----------------------------------------------------------
    Item {
        id: drop
        property string topic: Canopy.topic
        property bool standalone: Canopy.standalone
        property bool animate: true
        property bool growing: true
        property real reveal: 0
        readonly property real cut: Config.barStyle === "cedar" ? Theme.strataCut : 12
        readonly property real longCut: Math.round(cut * 16 / 9)
        // Position and size along the bar, and how far it has grown out of it.
        property real along: 0
        property real span: 0
        property real reach: 0
        property real targetReach: 0
        x: root.side ? 0 : along
        y: root.side ? along : root.barJoin
        width: root.side ? reach : span
        height: root.side ? span : reach
        // Sideways the panel is laid out at its full reach and uncovered as the
        // surface grows (the wrapper below clips it; the frame's fillets and
        // lean reach outside the drop and must not be clipped).
        // Anchor providers can settle after the window is mapped. Never
        // interpolate that correction during a dropdown entrance: it makes
        // right-side controls sweep across the screen from the old origin.
        // Only an explicit in-place tab morph may animate horizontally.
        readonly property bool animateHorizontal: root.morphing && drop.animate && morph.running
        Behavior on along { enabled: drop.animateHorizontal; NumberAnimation { duration: VisualQuality.ms(Theme.expand * .75); easing.type: Easing.OutCubic } }
        Behavior on span { enabled: drop.animateHorizontal; NumberAnimation { duration: VisualQuality.ms(Theme.expand * .75); easing.type: Easing.OutCubic } }
        Behavior on reach {
            enabled: root.morphing && drop.animate
            NumberAnimation {
                duration: VisualQuality.ms(drop.growing ? Theme.morphGrow : Theme.morphShrink)
                easing.type: Easing.BezierSpline
                easing.bezierCurve: drop.growing ? [0.38, 1.21, 0.22, 1.0, 1, 1] : [0.05, 0.7, 0.1, 1.0, 1, 1]
            }
        }
        // Silhouette: the bar's lower edge bends down through concave fillets
        // and becomes the drop's sides (components/DropFrame.qml). With
        // effects on it is one field with the bar and yields to its own
        // motion; the panel leans with it through `deformMatrix`.
        DropFrame {
            id: frame
            anchors.fill: parent
            side: root.side
            cut: drop.cut
            join: drop.cut
            // The bar's own material at the bar's opacity, so the drop is the
            // bar continuing rather than a second surface hung under it.
            fill: Config.barStyle === "cedar" ? Qt.alpha(Theme.strataFoundation, Config.barOpacity) : Qt.alpha(Theme.background, Math.max(.96, Config.panelOpacity))
            // One line with the bar: the drop's contour is the bar's edge
            // (StrataBarFrame / UnderstoryBar seam) continued.
            stroke: Config.barStyle === "cedar" ? Qt.alpha(Theme.strataGrain, .28) : Qt.alpha(Forest.accent, .25)
            barStroke: stroke
            grainColor: Config.barStyle === "cedar" ? Theme.strataGrain : Qt.alpha(Theme.border, .55)
            lit: Canopy.surfaceState === "opening" || Canopy.surfaceState === "retargeting"
            growing: drop.growing && (Canopy.surfaceState === "opening" || Canopy.surfaceState === "retargeting")
            barRect: root.plateRect
            barCuts: root.plateCuts
            emerge: root.emerge
            // The bar's window paints the field up to its own lower edge.
            paintFrom: root.side ? 0 : Config.barHeight - root.barJoin
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
        Item {
            anchors.fill: parent
            clip: root.side
        CanopyPanel {
            id: panel
            anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.left: parent.left
            width: root.side ? drop.targetReach : drop.width
            framed: false
            topic: drop.topic
            standalone: drop.standalone
            active: root.requested
            visible: drop.reveal > 0 || root.requested
            opacity: drop.reveal
            // The lean is bounded (DropFrame caps the stretch) and exists only
            // while the surface moves; the input mask stays the undeformed drop
            // (clipping to it would cut the fillets), so a pixel of overhang
            // mid-motion falls through to the desktop rather than mis-hitting.
            transform: Matrix4x4 { matrix: frame.deformMatrix }
            onPreferredHeightChanged: root.reaim()
        }
        }
    }
}
