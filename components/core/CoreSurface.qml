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
    // HudPanel draws its bar frame five pixels inside the native window.
    readonly property int barInset: Config.barStyle === "cedar" || Config.barIslands ? 5 : 0
    readonly property int restingHeight: Config.barHeight - 2 * barInset
    readonly property var activity: CoreService.foreground
    readonly property bool volume: activity?.type === "volume" || activity?.type === "brightness"
    readonly property bool alert: !!activity && (activity.sticky || activity.attentionUntil > CoreService.model.now)
    readonly property bool detailed: CoreService.expanded
    readonly property bool peek: hovering && !!activity && !Canopy.shown
    readonly property color accent: activity?.priority === 3 || ["recording", "camera", "microphone"].includes(activity?.type) ? Theme.ember : activity?.priority === 2 ? Theme.amber : (Config.saved.forestPulse ? Forest.accent : Theme.teal)
    // The pill has two widths: resting (clock) and active (one signal). The network
    // nub sits outside it, mirrored by equal space on the left so the pill stays centered.
    readonly property bool panel: detailed || peek || CoreService.dropHover
    // Settled background activity (e.g. media playing) leaves the pill at rest; only
    // something asking for attention, an ongoing capture, or a live control widens it.
    readonly property bool signalling: alert || volume || CoreService.recording || CoreService.privacy.length > 0 || CoreService.timer.active || Canopy.shown || !!Forest.whisper
    readonly property bool showNetwork: Config.moduleEnabled("network") && !panel
    readonly property real nubWidth: showNetwork ? networkStatus.implicitWidth : 0
    readonly property real nubSpace: showNetwork ? nubWidth + 6 : 0
    readonly property real restWidth: 150
    readonly property real activeWidth: Math.max(restWidth, Math.min(272, CoreService.reserveWidth - 2 * nubSpace))
    readonly property real pillWidth: signalling ? activeWidth : restWidth
    readonly property real targetWidth: Math.min(maximumWidth, panel ? 440 : pillWidth + 2 * nubSpace)
    // Recording and privacy always own the line, even while another signal is in front.
    readonly property color lineColor: CoreService.recording || CoreService.privacy.length ? Theme.ember : accent
    // One dot per signal, three at most. A lone signal already named by the text needs none.
    readonly property var dots: CoreService.rows.length > 1 || (CoreService.rows.length === 1 && !alert) ? CoreService.rows.slice(0, 3) : []
    property alias pillItem: pill
    property alias nubItem: networkStatus
    width: targetWidth
    implicitHeight: detailed ? Math.min(maximumHeight, hub.implicitHeight + root.restingHeight + 38) : peek ? root.restingHeight + Math.min(180, preview.implicitHeight) + 28 : CoreService.dropHover ? root.restingHeight + 60 : root.restingHeight
    height: implicitHeight
    // Allocate the end size once, animate inside it, then shrink after settling.
    // Avoid negotiating a new Wayland surface size on every animation frame.
    property int windowHeight: Math.ceil(implicitHeight) + 2
    onImplicitHeightChanged: windowHeight = Math.max(windowHeight, Math.ceil(implicitHeight) + 2)
    onHeightChanged: {
        if (!heightAnimation.running)
            windowHeight = Math.ceil(height) + 2;
    }
    Behavior on width {
        enabled: root.active && !Theme.reducedMotion
        NumberAnimation {
            duration: Theme.transition
            easing.type: Easing.OutCubic
        }
    }
    Behavior on height {
        enabled: root.active && !Theme.reducedMotion
        NumberAnimation {
            id: heightAnimation
            duration: Theme.transition
            onRunningChanged: if (!running)
                root.windowHeight = Math.ceil(root.height) + 2
            easing.type: Easing.OutCubic
        }
    }
    // Keep the native surface and its controls mapped; geometry grows from the center.
    Item {
        id: pill
        x: root.panel ? 0 : root.nubSpace
        width: root.panel ? root.width : root.width - 2 * root.nubSpace
        height: root.height
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeWidth: 1
                strokeColor: Qt.alpha(root.lineColor, root.alert ? .36 : .15)
                fillColor: Qt.alpha(Theme.background, Math.max(.94, Config.barOpacity))
                startX: 0; startY: 9
                PathLine { x: 9; y: 0 }
                PathLine { x: pill.width - 16; y: 0 }
                PathLine { x: pill.width; y: 16 }
                PathLine { x: pill.width; y: pill.height - 9 }
                PathLine { x: pill.width - 9; y: pill.height }
                PathLine { x: 16; y: pill.height }
                PathLine { x: 0; y: pill.height - 16 }
                PathLine { x: 0; y: 9 }
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
            y: root.restingHeight - 2
            visible: !root.panel
            width: lit ? pill.width - 40 : echo ? pill.width * .4 : 28
            height: lit ? 2 : 1
            radius: 1
            color: lit ? root.lineColor : Theme.teal
            // Breathing steps at Motion.ambientFps and rests with the user; the
            // line is always mapped, so a vsync animator here never stopped.
            readonly property bool breathing: root.active && Motion.active && Config.saved.ambientIntensity > 0 && Config.saved.forestPulse && Forest.state !== "HUNT" && !lit && !echo
            opacity: lit ? .85 : echo ? .3 : breathing ? breath.value : .45
            Behavior on width { enabled: !Theme.reducedMotion; NumberAnimation { duration: Theme.transition; easing.type: Easing.OutCubic } }
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
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 0; visible: root.panel; width: root.width * .55; height: 1; color: root.lineColor; opacity: .5
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
        precision: SystemClock.Minutes
    }
    StationButton {
        id: header
        objectName: "coreHeader"
        x: pill.x
        width: pill.width
        height: root.restingHeight
        hint: "Quick Controls"
        enabled: !ShellState.locked
        checked: Canopy.shown && Canopy.topic === "quick"
        onClicked: Canopy.toggleQuick()
        Keys.onReturnPressed: event => {
            Canopy.toggleQuick();
            event.accepted = true;
        }
        // A mouse click must not leave a highlight; only keyboard focus draws one.
        focusPolicy: Qt.TabFocus
        background: Rectangle {
            anchors.fill: parent; anchors.margins: 3
            radius: 5
            color: header.hovered || header.visualFocus ? Qt.alpha(Theme.teal, .07) : Theme.transparent
            border.width: header.visualFocus ? 1 : 0
            border.color: Theme.teal
        }
        contentItem: Item {
            GlowText {
                // Centered in the space left of the dots.
                x: 12 + Math.max(0, (parent.width - 24 - (root.dots.length ? dotRow.width + 8 : 0) - width) / 2)
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, parent.width - 24 - (root.dots.length ? dotRow.width + 8 : 0))
                visible: !(root.volume && !root.panel && !Canopy.shown)
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
                text: root.detailed ? "CEDAR CORE" : Canopy.shown ? Canopy.title.toUpperCase() : root.alert ? (root.activity?.title || "") : CoreService.recording ? "REC  " + Media.elapsed((CoreService.now - CoreService.recordings[0].started) / 1000) : CoreService.timer.active ? "TIMER  " + Media.elapsed(CoreService.timer.remaining) : Forest.whisper || (Config.moduleEnabled("clock") ? Config.formatTime(clock.date) : "◈")
                font.family: root.detailed ? Theme.labelFont : Theme.dataFont
                font.pixelSize: root.detailed ? 19 : Theme.small
                color: root.alert && !root.detailed && root.activity?.priority >= 2 ? root.accent : Theme.text
            }
            Row {
                id: dotRow
                objectName: "coreDots"
                anchors.right: parent.right; anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                visible: !root.panel && !(root.volume && !Canopy.shown) && root.dots.length > 0
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
                strokeColor: networkStatus.visualFocus ? Theme.green : Qt.alpha(networkStatus.accent, networkStatus.hovered ? .45 : .15)
                fillColor: Qt.alpha(Theme.background, Math.max(.94, Config.barOpacity))
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
        visible: root.volume && !root.panel && !Canopy.shown
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
        y: root.restingHeight + 8
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
        visible: root.detailed
        x: 18
        y: root.restingHeight + 8
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
