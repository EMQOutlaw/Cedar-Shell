import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import ".."
import "../components"
import "../services"

PanelWindow {
    id: root
    required property var output
    readonly property bool volumeMode: ShellState.osdKind === "VOLUME"
    readonly property bool interacting: visible && (hover.hovered || slider.pressed)
    onInteractingChanged: {
        if (ShellState.osdOutput === output.name) ShellState.osdLegacyInteracting = interacting;
    }
    screen: output
    visible: ShellState.osdVisible && ShellState.osdOutput === output.name && !CoreService.ownsOsd
    anchors { bottom: true }
    margins.bottom: 70
    implicitWidth: volumeMode ? 380 : 220
    implicitHeight: volumeMode ? 126 : 210
    exclusionMode: ExclusionMode.Ignore
    color: Theme.transparent
    WlrLayershell.namespace: "cedar-osd"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    HudPanel {
        anchors.fill: parent
        highlighted: true
        accent: Theme.amber
        padding: 24
        HoverHandler { id: hover }

        Item {
            anchors.fill: parent
            visible: root.volumeMode
            Text {
                x: 0; y: 0
                text: Audio.muted ? "VOLUME / MUTED" : "VOLUME"
                color: Audio.muted ? Theme.muted : Theme.amber
                font.family: Theme.labelFont
                font.pixelSize: 20
                font.bold: true
            }
            Text {
                anchors.right: parent.right
                y: 0
                text: Audio.audio ? Math.round(Audio.volume * 100) + "%" : "NO DEVICE"
                color: Theme.text
                font.family: Theme.dataFont
                font.pixelSize: 18
            }
            Slider {
                id: slider
                x: 0; y: 34
                width: parent.width; height: 34
                from: 0; to: 1
                enabled: Audio.audio !== null
                value: Audio.volume
                // Every drag movement writes immediately; no delayed commit.
                onMoved: { Audio.setVolume(value); Audio.show(); }
                background: Rectangle {
                    x: slider.leftPadding
                    y: slider.topPadding + slider.availableHeight / 2 - height / 2
                    width: slider.availableWidth; height: 6; radius: 3
                    color: Theme.border
                    Rectangle {
                        width: parent.width * slider.visualPosition
                        height: parent.height; radius: 3
                        color: Audio.muted ? Theme.muted : Theme.amber
                    }
                }
                handle: Rectangle {
                    x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
                    y: slider.topPadding + slider.availableHeight / 2 - height / 2
                    width: 18; height: 18; radius: 9
                    color: slider.pressed ? Theme.brightAmber : Theme.amber
                    border.width: 2; border.color: Theme.surface
                }
                WheelHandler {
                    onWheel: event => {
                        if (event.angleDelta.y !== 0) Audio.change(event.angleDelta.y > 0 ? 5 : -5);
                        event.accepted = true;
                    }
                }
            }
            MouseArea {
                x: 0; y: 0; width: 190; height: 28
                cursorShape: Qt.PointingHandCursor
                onClicked: Audio.toggleMute()
            }
        }
        ArcGauge {
            visible: !root.volumeMode
            active: root.visible && visible
            anchors.centerIn: parent
            width: 170; height: 170
            value: ShellState.osdValue
            valueText: ShellState.osdLabel
            label: ShellState.osdKind
            accent: Theme.amber
        }
    }
}
