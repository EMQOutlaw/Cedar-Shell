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
    readonly property real targetWidth: Math.min(maximumWidth, detailed || peek || CoreService.dropHover ? 440 : volume ? CoreService.reserveWidth : alert ? CoreService.reserveWidth : CoreService.recording || CoreService.privacy.length || CoreService.timer.active || Canopy.shown ? 246 : Forest.whisper ? CoreService.reserveWidth : 170)
    width: targetWidth
    implicitHeight: detailed ? Math.min(maximumHeight, hub.implicitHeight + root.restingHeight + 38) : volume && !Canopy.shown ? root.restingHeight + 56 : peek ? root.restingHeight + Math.min(180, preview.implicitHeight) + 28 : CoreService.dropHover ? root.restingHeight + 60 : root.restingHeight
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
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: 1
            strokeColor: Qt.alpha(root.accent, root.alert ? .36 : .15)
            fillColor: Qt.alpha(Theme.background, Math.max(.94, Config.barOpacity))
            startX: 0
            startY: 9
            PathLine {
                x: 9
                y: 0
            }
            PathLine {
                x: root.width - 16
                y: 0
            }
            PathLine {
                x: root.width
                y: 16
            }
            PathLine {
                x: root.width
                y: root.height - 9
            }
            PathLine {
                x: root.width - 9
                y: root.height
            }
            PathLine {
                x: 16
                y: root.height
            }
            PathLine {
                x: 0
                y: root.height - 16
            }
            PathLine {
                x: 0
                y: 9
            }
        }
    }
    Rectangle {
        id: filament
        anchors.horizontalCenter: parent.horizontalCenter
        y: 0
        width: root.alert ? root.width * .55 : 36
        height: 1
        color: root.accent
        opacity: .5
        SequentialAnimation on opacity {
            running: root.active && !Theme.reducedMotion && Config.saved.ambientIntensity > 0 && Config.saved.forestPulse && Forest.state !== "HUNT" && !root.alert
            loops: Animation.Infinite
            OpacityAnimator {
                to: Math.max(.12, Forest.strength * .5)
                duration: Forest.breathDuration
            }
            OpacityAnimator {
                to: Forest.strength
                duration: Forest.breathDuration + 800
            }
        }
        Behavior on width {
            enabled: !Theme.reducedMotion
            NumberAnimation {
                duration: Theme.transition
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
        width: parent.width - (networkStatus.visible ? networkStatus.width + 6 : 0)
        height: root.restingHeight
        hint: "Quick Controls"
        enabled: !ShellState.locked
        checked: Canopy.shown && Canopy.topic === "quick"
        onClicked: Canopy.toggleQuick()
        Keys.onReturnPressed: event => {
            Canopy.toggleQuick();
            event.accepted = true;
        }
        background: Rectangle {
            radius: 5
            color: header.hovered || header.activeFocus ? Qt.alpha(Theme.teal, .08) : Theme.transparent
            border.width: header.activeFocus ? 1 : 0
            border.color: Theme.teal
        }
        contentItem: RowLayout {
            spacing: 8
            GlowText {
                text: root.activity?.icon || "◈"
                color: root.accent
                font.pixelSize: 16
            }
            GlowText {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
                text: root.detailed ? "CEDAR CORE" : Canopy.shown ? Canopy.title.toUpperCase() : root.alert ? (root.volume ? root.activity.title : root.activity?.title || "") : CoreService.recording ? "REC  " + Media.elapsed((CoreService.now - CoreService.recordings[0].started) / 1000) : CoreService.timer.active ? "TIMER  " + Media.elapsed(CoreService.timer.remaining) : Forest.whisper || (Config.moduleEnabled("clock") ? Config.formatTime(clock.date) : "Quick Controls")
                font.family: root.detailed ? Theme.labelFont : Theme.dataFont
                font.pixelSize: root.detailed ? 19 : Theme.small
                color: Theme.text
            }
            GlowText {
                visible: CoreService.recording && (root.alert || root.detailed)
                text: "●"
                color: Theme.ember
                font.pixelSize: 12
            }
            GlowText {
                visible: CoreService.privacy.length > 0
                text: CoreService.privacy.some(a => a.type === "camera") ? "CAM" : "MIC"
                color: Theme.ember
                font.pixelSize: 10
            }
            GlowText {
                visible: CoreService.rows.length > 1
                text: "+" + (CoreService.rows.length - 1)
                color: Theme.muted
                font.pixelSize: 10
            }
        }
    }
    NetworkIndicator {
        id: networkStatus
        visible: Config.moduleEnabled("network")
        anchors.right: parent.right
        anchors.rightMargin: 4
        anchors.top: parent.top
        height: root.restingHeight
        outputName: CoreService.hostName
    }
    Row {
        anchors.right: parent.right
        anchors.rightMargin: 8
        y: root.restingHeight - 6
        spacing: 4
        visible: Config.saved.forestEchoes && !root.alert && !root.detailed && !root.peek
        Repeater {
            model: Forest.echoes
            GlowText {
                required property var modelData
                text: modelData.icon
                opacity: .3
                font.pixelSize: 8
                color: Theme.teal
            }
        }
    }
    CoreVolume {
        visible: root.volume && !root.detailed && !Canopy.shown
        x: 18
        y: root.restingHeight
        width: parent.width - 36
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
