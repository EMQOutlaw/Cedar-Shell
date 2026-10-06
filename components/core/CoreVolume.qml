import QtQuick
import QtQuick.Layouts
import "../.."
import ".."
import "../../services"

ColumnLayout {
    id: root
    property bool volume: true
    // Compact: a single centered row that fits inside the resting pill.
    property bool compact: false
    readonly property bool dragging: slider.pressed
    spacing: 6
    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: root.compact
        StationButton {
            implicitHeight: root.compact ? 28 : Theme.controlHeight
            visible: root.volume
            text: Audio.muted ? "󰝟" : "󰕾"
            iconOnly: true
            hint: Audio.muted ? "Unmute" : "Mute"
            onClicked: Audio.toggleMute()
        }
        StationSlider {
            id: slider
            objectName: "coreVolumeSlider"
            Layout.fillWidth: true
            enabled: root.volume ? !!Audio.audio : Brightness.available
            value: root.volume ? Audio.volume : Brightness.value
            Accessible.name: root.volume ? "Volume" : "Brightness"
            onMoved: if (root.volume) {
                Audio.setVolume(value);
                Audio.show();
            }
            onCommitted: value => {
                if (!root.volume)
                    Brightness.change(Math.round(value * 100) - Math.round(Brightness.value * 100));
            }
            onPressedChanged: ShellState.osdCoreDragging = pressed
            Component.onDestruction: ShellState.osdCoreDragging = false
            WheelHandler {
                onWheel: event => {
                    if (root.volume && event.angleDelta.y)
                        Audio.change(event.angleDelta.y > 0 ? 5 : -5);
                    event.accepted = true;
                }
            }
        }
        GlowText {
            text: Math.round((root.volume ? Audio.volume : Brightness.value) * 100) + "%"
            color: Theme.green
            font.pixelSize: root.compact ? Theme.small : Theme.normal
            Layout.preferredWidth: root.compact ? 40 : 48
            horizontalAlignment: Text.AlignRight
        }
    }
    GlowText {
        visible: CoreService.expanded && !root.compact
        text: root.volume ? (Audio.sink?.description || "No output device") : "Display backlight"
        color: Theme.muted
        Layout.fillWidth: true
        elide: Text.ElideRight
        font.pixelSize: Theme.small
    }
}
