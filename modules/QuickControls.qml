import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Services.Mpris
import Quickshell.Services.UPower
import ".."
import "../components"
import "../services"

ColumnLayout {
    id: root
    property bool active: false
    readonly property var player: Media.player
    onActiveChanged: if (active)
        Controls.refresh()
    spacing: 16
    GlowText {
        visible: Controls.error !== ""
        text: Controls.error
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        color: Theme.amber
    }
    GlowText {
        text: "SOUND"
        color: Theme.teal
    }
    RowLayout {
        GlowText {
            text: "Output"
            Layout.preferredWidth: 80
        }
        StationCombo {
            Layout.fillWidth: true
            model: Audio.outputs
            textRole: "description"
            currentIndex: Audio.outputs.indexOf(Audio.sink)
            onActivated: Audio.selectOutput(Audio.outputs[currentIndex])
        }
    }
    RowLayout {
        StationSlider {
            objectName: "quickVolume"
            Accessible.name: "Output volume"
            Layout.fillWidth: true
            enabled: Audio.audio !== null
            value: Audio.volume
            onMoved: Audio.setVolume(value)
        }
        GlowText {
            text: Audio.audio ? Audio.label : "—"
            Layout.preferredWidth: 62
            elide: Text.ElideRight
        }
        StationButton {
            text: Audio.muted ? "Unmute" : "Mute"
            enabled: Audio.audio !== null
            onClicked: Audio.toggleMute()
        }
    }
    RowLayout {
        GlowText {
            text: "Microphone"
            Layout.preferredWidth: 80
        }
        StationCombo {
            Layout.fillWidth: true
            model: Audio.inputs
            textRole: "description"
            currentIndex: Audio.inputs.indexOf(Audio.source)
            onActivated: Audio.selectInput(Audio.inputs[currentIndex])
        }
    }
    RowLayout {
        StationSlider {
            Layout.fillWidth: true
            enabled: Audio.microphone !== null
            value: Audio.microphone?.volume ?? 0
            onMoved: Audio.setMicrophone(value)
        }
        StationButton {
            text: Audio.microphone?.muted ? "Unmute mic" : "Mute mic"
            enabled: Audio.microphone !== null
            onClicked: Audio.toggleMicrophone()
        }
    }
    GlowText {
        text: "LIGHT"
        color: Theme.teal
        Layout.topMargin: 8
    }
    RowLayout {
        GlowText {
            text: "Brightness"
        }
        StationSlider {
            Layout.fillWidth: true
            enabled: Brightness.available
            value: Brightness.value
            onCommitted: v => Brightness.change(Math.round((v - Brightness.value) * 100))
        }
        GlowText {
            text: Brightness.available ? Math.round(Brightness.value * 100) + "%" : "Unavailable"
            color: Theme.muted
        }
    }
    StationToggle {
        Layout.fillWidth: true
        label: "Night light"
        checked: Controls.data.nightlight === true
        enabled: Controls.data.nightlight !== null
        busy: Controls.busy
        description: Controls.data.errors.nightlight || "Warmer light for the evening"
        onToggled: Controls.run({
            action: "nightlight"
        })
    }
    StationToggle {
        Layout.fillWidth: true
        label: "Do Not Disturb"
        checked: Config.saved.doNotDisturb
        description: "Quiet popups; critical alerts still appear. History keeps every notification."
        onToggled: value => Config.set("doNotDisturb", value)
    }
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 8
        GlowText {
            text: "ENERGY"
            color: Theme.teal
            Layout.fillWidth: true
        }
        StationButton {
            visible: !Config.saved.canopyEnabled
            text: "Power & session"
            onClicked: ShellState.toggle("power")
        }
    }
    GlowText {
        visible: UPower.displayDevice?.isPresent ?? false
        text: Math.round((UPower.displayDevice?.percentage ?? 0) * 100) + "% battery"
        color: Theme.green
    }
    Flow {
        Layout.fillWidth: true
        spacing: 8
        Repeater {
            model: Controls.data.profiles
            StationButton {
                required property string modelData
                text: modelData
                checked: Controls.data.profile === modelData
                enabled: !Controls.busy
                onClicked: Controls.run({
                    action: "profile",
                    value: modelData
                })
            }
        }
    }
    GlowText {
        visible: !Controls.data.profiles.length
        text: Controls.data.errors.power || "Power profiles unavailable"
        color: Theme.muted
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        font.pixelSize: 11
    }
    GlowText {
        text: "ON THE AIR"
        color: Theme.teal
        Layout.topMargin: 8
    }
    GlowText {
        text: root.player?.trackTitle || "The woods are quiet"
        Layout.fillWidth: true
        elide: Text.ElideRight
    }
    GlowText {
        text: root.player?.trackArtist || ""
        Layout.fillWidth: true
        elide: Text.ElideRight
        color: Theme.muted
    }
    RowLayout {
        StationButton {
            text: "Previous"
            enabled: root.player?.canGoPrevious ?? false
            onClicked: root.player.previous()
        }
        StationButton {
            text: root.player?.isPlaying ? "Pause" : "Play"
            enabled: root.player?.canTogglePlaying ?? false
            onClicked: root.player.togglePlaying()
        }
        StationButton {
            text: "Next"
            enabled: root.player?.canGoNext ?? false
            onClicked: root.player.next()
        }
        Item {
            Layout.fillWidth: true
        }
    }
}
