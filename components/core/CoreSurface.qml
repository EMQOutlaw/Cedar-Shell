import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import "../.."
import ".."
import "../../services"

Item {
    id: root
    property bool active: true
    property real maximumWidth: 460
    property real maximumHeight: 680
    property bool hovering: false
    property bool focusRequested: false
    readonly property bool integrated: Config.barStyle === "cedar"
    // HudPanel draws its bar frame five pixels inside the native window.
    readonly property int barInset: Config.barStyle === "cedar" || Config.barIslands ? 5 : 0
    readonly property int restingHeight: Config.barHeight - 2 * barInset
    readonly property var activity: CoreService.foreground
    readonly property bool volume: activity?.type === "volume" || activity?.type === "brightness"
    readonly property bool alert: !!activity && (activity.sticky || activity.attentionUntil > CoreService.model.now)
    readonly property bool detailed: CoreService.expanded
    // A standalone Canopy (one hanging from its own bar control) is not the pill's.
    readonly property bool canopyHere: !integrated && Canopy.shown && !Canopy.standalone
    readonly property bool peek: hovering && !!activity && !root.canopyHere
    readonly property color accent: activity?.priority === 3 || ["recording", "camera", "microphone"].includes(activity?.type) ? Theme.ember : activity?.priority === 2 ? Theme.amber : integrated ? Theme.strataAccent : (Config.saved.forestPulse ? Forest.accent : Theme.teal)
    // Cedar keeps this center within the bar's reserved space. Other layouts
    // retain their clock and the network nub with mirrored space on the left.
    readonly property bool panel: detailed || peek || CoreService.dropHover
    // Settled background activity (e.g. media playing) leaves the pill at rest; only
    // something asking for attention, an ongoing capture, or a live control widens it.
    readonly property bool signalling: alert || volume || CoreService.recording || CoreService.privacy.length > 0 || CoreService.timer.active || root.canopyHere || (!integrated && !!Forest.whisper)
    readonly property bool showNetwork: !integrated && Config.moduleEnabled("network") && !panel
    readonly property real nubWidth: showNetwork ? networkStatus.implicitWidth : 0
    readonly property real nubSpace: showNetwork ? nubWidth + 6 : 0
    readonly property real restWidth: integrated ? Math.min(Math.round(150 * Theme.fontScale), CoreService.reserveWidth) : 150
    readonly property real activeWidth: Math.max(restWidth, Math.min(272, CoreService.reserveWidth - 2 * nubSpace))
    readonly property real pillWidth: signalling ? activeWidth : restWidth
    readonly property real targetWidth: Math.min(maximumWidth, panel ? 440 : pillWidth + 2 * nubSpace)
    // Recording and privacy always own the line, even while another signal is in front.
    readonly property color lineColor: CoreService.recording || CoreService.privacy.length ? Theme.ember : accent
    // One dot per signal, three at most. A lone signal already named by the text needs none.
    readonly property var dots: CoreService.rows.length > 1 || (CoreService.rows.length === 1 && !alert) ? CoreService.rows.slice(0, 3) : []
    // Meaning and time have separate renderers: only the meaning resolves in.
    // A clock minute, timer second or recording duration is an ordinary Text update.
    readonly property string labelMode: detailed ? "hub" : canopyHere ? "canopy" : alert ? "alert" : CoreService.recording ? "recording" : CoreService.timer.active ? "timer" : integrated ? "profile" : Forest.whisper ? "whisper" : "clock"
    readonly property string labelTitle: labelMode === "hub" ? (integrated ? "SIGNALS" : "CEDAR CORE")
        : labelMode === "canopy" ? Canopy.title.toUpperCase()
        : labelMode === "alert" ? (activity?.title || "")
        : labelMode === "recording" ? "REC"
        : labelMode === "timer" ? "TIMER"
        : labelMode === "profile" ? (Gaming.active ? "GAMING" : Focus.active ? "FOCUS" : Profiles.current ? Profiles.currentLabel.toUpperCase() : "CEDAR")
        : labelMode === "whisper" ? Forest.whisper : ""
    readonly property string labelValue: labelMode === "recording" ? Media.elapsed((CoreService.now - CoreService.recordings[0].started) / 1000)
        : labelMode === "timer" ? Media.elapsed(CoreService.timer.remaining)
        : labelMode === "clock" ? (Config.moduleEnabled("clock") ? Config.formatTime(clock.date) : "◈") : ""
    property alias pillItem: pill
    property alias nubItem: networkStatus
    // Cedar's right rail owns Quick Controls and Power. Other layouts retain
    // the Core anchor; clearing is conditional on this provider still owning it.
    readonly property string anchorOutput: CoreService.hostName
    function pillRect() {
        const win = root.QsWindow ? root.QsWindow.window : null;
        if (!win || !win.screen)
            return null;
        const p = pill.mapToItem(null, 0, 0);
        return { x: (win.screen.width - win.width) / 2 + p.x, width: pill.width };
    }
    function publishAnchor() {
        for (const topic of ["quick", "power"]) {
            if (root.active && !root.integrated)
                Canopy.setAnchorProvider(topic, anchorOutput, root.pillRect);
            else
                Canopy.clearAnchorProvider(topic, anchorOutput, root.pillRect);
        }
    }
    Component.onDestruction: { Canopy.clearAnchorProvider("quick", anchorOutput, root.pillRect); Canopy.clearAnchorProvider("power", anchorOutput, root.pillRect); }
    onAnchorOutputChanged: publishAnchor()
    onIntegratedChanged: publishAnchor()
    width: targetWidth
    implicitHeight: detailed ? Math.min(maximumHeight, hub.implicitHeight + root.restingHeight + 38) : peek ? root.restingHeight + Math.min(180, preview.implicitHeight) + 28 : CoreService.dropHover ? root.restingHeight + 60 : root.restingHeight
    // Morph rather than scale: width leads on a short curve, height follows on a
    // longer expressive curve with a hint of overshoot on the way out and a plain
    // decelerate on the way back. Content is staged by `reveal`. Reduced Motion
    // and an inactive surface snap every one of these.
    readonly property bool morphing: root.active && VisualQuality.functionalMotion
    property bool growing: true
    // Allocate the end size once (plus the overshoot while growing), animate
    // inside it, then shrink after settling. Avoid negotiating a new Wayland
    // surface size on every animation frame.
    property int windowHeight: Math.ceil(implicitHeight) + 2
    onImplicitHeightChanged: {
        growing = implicitHeight > height;
        windowHeight = Math.max(windowHeight, Math.ceil(implicitHeight * (morphing && growing ? 1.03 : 1)) + 2);
        height = implicitHeight;
    }
    Component.onCompleted: {
        height = implicitHeight;
        publishAnchor();
    }
    onHeightChanged: {
        if (!heightAnimation.running)
            windowHeight = Math.ceil(height) + 2;
    }
    Behavior on width {
        enabled: root.morphing
        NumberAnimation {
            duration: VisualQuality.ms(Theme.expand * .7)
            easing.type: Easing.OutCubic
        }
    }
    Behavior on height {
        enabled: root.morphing
        NumberAnimation {
            id: heightAnimation
            duration: VisualQuality.ms(root.growing ? Theme.morphGrow : Theme.morphShrink)
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root.growing ? [0.38, 1.21, 0.22, 1.0, 1, 1] : [0.05, 0.7, 0.1, 1.0, 1, 1]
            onRunningChanged: if (!running)
                root.windowHeight = Math.ceil(root.height) + 2
        }
    }
    // 0 while the pill rests, 1 once a panel is open. Content settles in after the
    // geometry has started moving and leaves quickly, ahead of the shrink.
    property real reveal: panel ? 1 : 0
    Behavior on reveal {
        enabled: root.morphing
        SequentialAnimation {
            PauseAnimation { duration: root.panel ? VisualQuality.ms(Theme.revealDelay) : 0 }
            NumberAnimation { duration: VisualQuality.ms(root.panel ? Theme.reveal : Theme.conceal); easing.type: Easing.OutCubic }
        }
    }
    // The hub has its own reveal so its scroll view never sits over a hover peek.
    property real hubReveal: detailed ? 1 : 0
    Behavior on hubReveal {
        enabled: root.morphing
        SequentialAnimation {
            PauseAnimation { duration: root.detailed ? VisualQuality.ms(Theme.revealDelay) : 0 }
            NumberAnimation { duration: VisualQuality.ms(root.detailed ? Theme.reveal : Theme.conceal); easing.type: Easing.OutCubic }
        }
    }
    // The chamfers open up a little with the panel, so the silhouette flows rather than stretches.
    property real chamfer: panel ? 1.35 : 1
    Behavior on chamfer {
        enabled: root.morphing
        NumberAnimation { duration: VisualQuality.ms(Theme.morphGrow); easing.type: Easing.OutCubic }
    }
    // Keep the native surface and its controls mapped; geometry grows from the center.
    Item {
        id: pill
        x: root.panel ? 0 : root.nubSpace
        width: root.panel ? root.width : root.width - 2 * root.nubSpace
        height: root.height
        Shape {
            anchors.fill: parent
            // The cedar center belongs to the bar. Its own boundary appears only
            // when Signals, a peek or a file action grows below that foundation.
            visible: !root.integrated || root.height > root.restingHeight + .5
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeWidth: 1
                // Seated in the bar at rest: the outline nearly disappears and the shape
                // and ember line carry the identity; it lights with a signal or a panel.
                strokeColor: Qt.alpha(root.lineColor, root.alert ? .36 : root.panel || root.signalling || hover.hovered ? .22 : .09)
                fillColor: Qt.alpha(root.integrated ? Theme.strataFoundation : Theme.background, Math.max(.94, Config.barOpacity))
                startX: 0; startY: (root.integrated ? Theme.strataCut : 9) * root.chamfer
                PathLine { x: (root.integrated ? Theme.strataCut : 9) * root.chamfer; y: 0 }
                PathLine { x: pill.width - (root.integrated ? Theme.strataCut : 16) * root.chamfer; y: 0 }
                PathLine { x: pill.width; y: (root.integrated ? Theme.strataCut : 16) * root.chamfer }
                PathLine { x: pill.width; y: pill.height - (root.integrated ? Theme.strataCut : 9) * root.chamfer }
                PathLine { x: pill.width - (root.integrated ? Theme.strataCut : 9) * root.chamfer; y: pill.height }
                PathLine { x: (root.integrated ? Theme.strataCut : 16) * root.chamfer; y: pill.height }
                PathLine { x: 0; y: pill.height - (root.integrated ? Theme.strataCut : 16) * root.chamfer }
                PathLine { x: 0; y: (root.integrated ? Theme.strataCut : 9) * root.chamfer }
            }
        }
        // The ember line: the only signal indicator. It rests as a faint filament,
        // lingers briefly after a signal (Echoes), and spans the pill while active.
        Rectangle {
            id: emberLine
            objectName: "coreLine"
            readonly property bool lit: root.signalling || root.alert
            readonly property bool echo: !lit && Config.saved.forestEchoes && Forest.echoes.length > 0
            anchors.horizontalCenter: parent.horizontalCenter
            // At rest it is the pill's foot; with a panel open it rides up to the seam with the bar.
            y: root.panel ? 0 : root.restingHeight - 2
            width: root.panel ? pill.width * .55 : lit ? pill.width - 40 : echo ? pill.width * .4 : 28
            height: lit && !root.panel ? 2 : 1
            radius: 1
            color: lit || root.panel ? root.lineColor : root.integrated ? Theme.strataAccent : Theme.teal
            // Breathing steps at Motion.ambientFps and rests with the user; the
            // line is always mapped, so a vsync animator here never stopped.
            readonly property bool breathing: !root.integrated && root.active && Motion.active && Config.saved.ambientIntensity > 0 && Config.saved.forestPulse && Forest.state !== "HUNT" && !lit && !echo && !root.panel
            opacity: root.panel ? .5 : lit ? .85 : echo ? .3 : breathing ? breath.value : root.integrated ? .22 : .45
            Behavior on y { enabled: root.morphing; NumberAnimation { duration: VisualQuality.ms(260); easing.type: Easing.OutCubic } }
            Behavior on width { enabled: root.morphing; NumberAnimation { duration: VisualQuality.ms(Theme.transition); easing.type: Easing.OutCubic } }
            Behavior on opacity { enabled: !Theme.reducedMotion && !emberLine.breathing; NumberAnimation { duration: 600 } }
            Breath {
                id: breath
                running: emberLine.breathing
                from: Forest.strength
                to: Math.max(.12, Forest.strength * .5)
                rise: Forest.breathDuration
                fall: Forest.breathDuration + 800
            }
        }
    }
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
    }
    HoverHandler {
        id: hover
        onHoveredChanged: {
            if (hovered)
                hoverDelay.restart();
            else {
                hoverDelay.stop();
                leaveDelay.restart();
            }
            root.syncHold();
        }
    }
    function syncHold() {
        const held = root.active && (hover.hovered || ShellState.osdCoreDragging);
        CoreService.hold(held ? root.activity?.id || "" : "");
        ShellState.osdCoreInteracting = held && root.volume;
    }
    // Foreground depends on heldId: defer its update out of the binding evaluation.
    onActivityChanged: Qt.callLater(root.syncHold)
    onActiveChanged: {
        publishAnchor();
        if (!active) {
            hovering = false;
            CoreService.hold("");
            ShellState.osdCoreInteracting = false;
        }
    }
    onFocusRequestedChanged: if (focusRequested)
        Qt.callLater(() => header.forceActiveFocus())
    Timer {
        id: hoverDelay
        interval: 330
        onTriggered: if (hover.hovered)
            root.hovering = true
    }
    Timer {
        id: leaveDelay
        interval: 240
        onTriggered: if (!hover.hovered)
            root.hovering = false
    }
    SystemClock {
        id: clock
        enabled: root.active && !root.integrated
        precision: SystemClock.Minutes
    }
    function toggleHeader() {
        if (root.integrated) {
            Canopy.close();
            CoreService.toggle();
        } else {
            Canopy.toggleQuick();
        }
    }
    StationButton {
        id: header
        objectName: "coreHeader"
        x: pill.x
        width: pill.width
        height: root.restingHeight
        hint: root.integrated ? "Signals" : "Quick Controls"
        enabled: !ShellState.locked
        checked: root.integrated ? root.detailed : Canopy.shown && Canopy.topic === "quick"
        onClicked: { heartwood.pulse(); root.toggleHeader(); }
        Keys.onReturnPressed: event => {
            heartwood.pulse();
            root.toggleHeader();
            event.accepted = true;
        }
        // A mouse click must not leave a highlight; only keyboard focus draws one.
        focusPolicy: Qt.TabFocus
        background: Rectangle {
            anchors.fill: parent; anchors.margins: 3
            radius: 5
            color: header.hovered || header.visualFocus ? Qt.alpha(root.integrated ? Theme.strataAccent : Theme.teal, .07) : Theme.transparent
            border.width: header.visualFocus ? 1 : 0
            border.color: root.integrated ? Theme.strataAccent : Theme.teal
        }
        contentItem: Item {
            // The Heartwood: CEDAR's instrument, seated at the pill's left. It
            // reads the desktop (Gaming Mode, Focus, Shield's posture, a panel
            // unfolding) and answers the pointer; still otherwise.
            CedarHeartwood {
                id: heartwood
                visible: Config.saved.barHeartwood
                active: root.active
                x: 8
                anchors.verticalCenter: parent.verticalCenter
                // A small center mark at rest; it grows with the Signals hub.
                size: root.detailed ? 44 : Math.min(24, root.restingHeight - 10)
                hovered: header.hovered
                unfolding: root.integrated ? root.detailed : Canopy.surfaceState === "opening" && root.canopyHere
                mode: Gaming.active ? "gaming" : Focus.active ? "focus" : "idle"
                warning: Shield.ready && Shield.posture !== "protected"
                accent: root.alert ? root.accent : root.integrated && !(VisualQuality.preset > 1 && (hovered || animating)) ? Theme.strataAccent : Theme.green
                intensity: VisualQuality.effectIntensity
                Behavior on size { enabled: root.morphing; NumberAnimation { duration: VisualQuality.ms(Theme.morphGrow); easing.type: Easing.OutCubic } }
                Connections { target: VisualQuality; function onAwakened() { heartwood.awaken(); } }
                // A signal arriving ripples outward from the heart.
                Connections { target: root; function onAlertChanged() { if (root.alert) heartwood.ripple(); } }
                Connections { target: Profiles; function onCurrentChanged() { if (root.integrated) heartwood.ripple(); } }
            }
            Row {
                id: statusLabel
                readonly property real leftInset: heartwood.visible ? heartwood.x + heartwood.width + 6 : 12
                readonly property real availableWidth: Math.max(0, parent.width - leftInset - 12 - (root.dots.length ? dotRow.width + 8 : 0))
                x: leftInset + Math.max(0, (parent.width - leftInset - 12 - (root.dots.length ? dotRow.width + 8 : 0) - width) / 2)
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, availableWidth)
                spacing: title.visible && value.visible ? 7 : 0
                clip: true
                visible: !(root.volume && !root.panel && !root.canopyHere)
                KineticLabel {
                    id: title
                    visible: root.labelTitle !== ""
                    width: Math.max(0, Math.min(implicitWidth, statusLabel.availableWidth - (value.visible ? value.width + statusLabel.spacing : 0)))
                    height: implicitHeight
                    text: root.labelTitle
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignHCenter
                    transitionStyle: "resolve"
                    minimumInterval: 400
                    maximumAnimatedLength: 24
                    font.family: root.detailed ? Theme.labelFont : Theme.dataFont
                    font.pixelSize: root.detailed ? 19 : root.integrated ? Theme.small : Theme.small + 1
                    font.letterSpacing: root.detailed ? 0 : root.integrated ? 1.1 : .6
                    color: root.alert && !root.detailed && root.activity?.priority >= 2 ? root.accent : root.integrated ? Theme.strataText : Theme.text
                }
                Text {
                    id: value
                    visible: root.labelValue !== ""
                    text: root.labelValue
                    textFormat: Text.PlainText
                    font.family: Theme.dataFont
                    font.pixelSize: Theme.small + 1
                    color: root.integrated ? Theme.strataText : Theme.text
                    elide: Text.ElideRight
                    width: Math.min(implicitWidth, statusLabel.availableWidth)
                    renderType: Text.QtRendering
                }
            }
            Row {
                id: dotRow
                objectName: "coreDots"
                anchors.right: parent.right; anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                visible: !root.panel && !(root.volume && !root.canopyHere) && root.dots.length > 0
                Accessible.role: Accessible.StaticText
                Accessible.name: CoreService.rows.length + " active signals"
                Repeater {
                    model: root.dots
                    Rectangle {
                        required property var modelData
                        width: 5; height: 5; radius: 3
                        color: modelData.priority >= 3 || ["recording", "microphone", "camera"].includes(modelData.type) ? Theme.ember : modelData.priority === 2 ? Theme.amber : Theme.teal
                        opacity: modelData.id === root.activity?.id ? 1 : .55
                    }
                }
            }
        }
    }
    NetworkIndicator {
        id: networkStatus
        visible: root.showNetwork
        x: pill.x + pill.width + 6
        y: (root.restingHeight - height) / 2
        height: root.restingHeight
        outputName: CoreService.hostName
        background: Shape {
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeWidth: networkStatus.visualFocus ? 2 : 1
                // A bare glyph beside the pill at rest; the frame appears on hover or focus.
                strokeColor: networkStatus.visualFocus ? Theme.green : Qt.alpha(networkStatus.accent, networkStatus.hovered ? .45 : 0)
                fillColor: networkStatus.hovered || networkStatus.visualFocus ? Qt.alpha(Theme.background, Math.max(.94, Config.barOpacity)) : Theme.transparent
                startX: 0; startY: 6
                PathLine { x: 6; y: 0 }
                PathLine { x: networkStatus.width; y: 0 }
                PathLine { x: networkStatus.width; y: networkStatus.height - 6 }
                PathLine { x: networkStatus.width - 6; y: networkStatus.height }
                PathLine { x: 0; y: networkStatus.height }
                PathLine { x: 0; y: 6 }
            }
        }
    }
    // Volume and brightness replace the text inside the pill; no second row.
    CoreVolume {
        visible: root.volume && !root.panel && !root.canopyHere
        compact: true
        x: pill.x + 10
        width: pill.width - 20
        height: root.restingHeight
        volume: root.activity?.type === "volume"
    }
    Loader {
        id: preview
        active: root.peek && !root.volume && !root.detailed
        visible: active
        x: 18
        y: root.restingHeight + 8 + 10 * (1 - root.reveal)
        opacity: root.reveal
        width: parent.width - 36
        sourceComponent: root.activity?.type === "media" ? mediaPreview : detailPreview
    }
    Component {
        id: mediaPreview
        CoreMedia {}
    }
    Component {
        id: detailPreview
        CoreDetails {
            activity: root.activity
        }
    }
    ScrollView {
        id: fullScroll
        visible: root.detailed || root.hubReveal > 0
        x: 18
        y: root.restingHeight + 8 + 10 * (1 - root.hubReveal)
        opacity: root.hubReveal
        width: parent.width - 36
        height: parent.height - y - 18
        contentWidth: availableWidth
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        CoreHub {
            id: hub
            width: fullScroll.availableWidth
        }
    }
    GlowText {
        visible: CoreService.dropHover && !root.detailed
        y: root.restingHeight + 12
        opacity: root.reveal
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: "Drop a file for actions"
        color: Theme.teal
    }
    DropArea {
        anchors.fill: parent
        onEntered: drag => {
            drag.accepted = !CoreService.actionBusy && drag.hasUrls && drag.urls.length === 1 && String(drag.urls[0]).startsWith("file:");
            CoreService.dropHover = drag.accepted;
        }
        onExited: CoreService.dropHover = false
        onDropped: drop => {
            CoreService.dropHover = false;
            if (drop.hasUrls && drop.urls.length === 1 && String(drop.urls[0]).startsWith("file:")) {
                drop.acceptProposedAction();
                CoreService.run({
                    action: "inspect-file",
                    path: String(drop.urls[0])
                });
            }
        }
    }
    Keys.onEscapePressed: {
        CoreService.collapse();
        Canopy.close();
    }
    Keys.onDownPressed: event => {
        const items = CoreService.rows;
        const i = items.findIndex(a => a.id === CoreService.model.selectedId);
        if (items.length)
            CoreService.model.selectedId = items[(i + 1) % items.length].id;
        event.accepted = true;
    }
    Keys.onUpPressed: event => {
        const items = CoreService.rows;
        const i = items.findIndex(a => a.id === CoreService.model.selectedId);
        if (items.length)
            CoreService.model.selectedId = items[(i + items.length - 1) % items.length].id;
        event.accepted = true;
    }
}
