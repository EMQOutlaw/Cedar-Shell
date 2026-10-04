import QtQuick
import QtQuick.Layouts
import "../.."
import ".."
import "../../services"

ColumnLayout {
    id: root
    property bool detailed: false
    property real position: 0
    readonly property var player: Media.player
    spacing: 10
    RowLayout {
        Layout.fillWidth: true
        spacing: 12
        Image {
            visible: root.detailed && source !== ""
            source: root.detailed ? Config.imageSource(root.player?.trackArtUrl || "") : ""
            sourceSize.width: 80
            sourceSize.height: 80
            Layout.preferredWidth: 64
            Layout.preferredHeight: 64
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }
        ColumnLayout {
            Layout.fillWidth: true
            GlowText {
                text: root.player?.trackTitle || "Nothing playing"
                font.family: Theme.labelFont
                font.pixelSize: 21
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
            GlowText {
                text: root.player?.trackArtist || root.player?.identity || ""
                color: Theme.muted
                font.pixelSize: Theme.small
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
        }
    }
    RowLayout {
        Layout.alignment: Qt.AlignHCenter
        StationButton {
            iconOnly: true
            text: "󰒮"
            hint: "Previous track"
            enabled: root.player?.canGoPrevious ?? false
            onClicked: Media.previous()
        }
        StationButton {
            iconOnly: true
            objectName: "coreMediaPlay"
            text: root.player?.isPlaying ? "󰏤" : "󰐊"
            hint: root.player?.isPlaying ? "Pause" : "Play"
            enabled: root.player?.canTogglePlaying ?? false
            onClicked: Media.toggle()
        }
        StationButton {
            iconOnly: true
            text: "󰒭"
            hint: "Next track"
            enabled: root.player?.canGoNext ?? false
            onClicked: Media.next()
        }
    }
    RowLayout {
        visible: root.detailed && (root.player?.positionSupported ?? false) && (root.player?.lengthSupported ?? false)
        Layout.fillWidth: true
        StationSlider {
            Layout.fillWidth: true
            Accessible.name: "Track position"
            enabled: root.player?.canSeek ?? false
            to: Math.max(1, root.player?.length || 1)
            value: root.position
            onCommitted: value => {
                if (root.player?.canSeek)
                    root.player.position = value;
            }
        }
        GlowText {
            text: Media.elapsed(root.position) + " / " + Media.elapsed(root.player?.length)
            color: Theme.muted
            font.pixelSize: Theme.small
        }
    }
    GlowText {
        visible: root.detailed
        text: (Audio.sink?.description || "No output") + " · " + Audio.label
        color: Theme.muted
        Layout.fillWidth: true
        elide: Text.ElideRight
        font.pixelSize: Theme.small
    }
    Timer {
        interval: 1000
        running: root.visible && root.detailed
        repeat: true
        triggeredOnStart: true
        onTriggered: root.position = root.player?.position ?? 0
    }
}
