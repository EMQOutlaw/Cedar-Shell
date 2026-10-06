import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris
import ".."
import "../components"
import "../services"

Rectangle {
    id: root
    property bool active: true
    readonly property bool narrow: width < 680
    readonly property int inset: narrow ? 22 : 36
    readonly property var player: Media.player
    implicitHeight: content.implicitHeight + inset * 2
    color: Qt.alpha(Theme.background, Config.panelOpacity)
    radius: Config.panelRadius
    border.width: 1
    border.color: Qt.alpha(Theme.teal, 0.18)
    SystemClock {
        id: clock
        precision: SystemClock.Minutes
        enabled: root.active
    }
    CedarAtmosphere {
        anchors.fill: parent
        active: root.active && Config.saved.ambientIntensity > 0
        opacity: Config.saved.ambientIntensity
    }
    // Absorb card clicks; the overlay outside remains the dismiss target.
    MouseArea {
        anchors.fill: parent
    }

    ColumnLayout {
        id: content
        x: root.inset
        y: root.inset
        width: root.width - root.inset * 2
        spacing: 24
        RowLayout {
            Layout.fillWidth: true
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                Text {
                    text: "CEDAR"
                    font.family: Theme.labelFont
                    font.pixelSize: 24
                    font.letterSpacing: 4
                    color: Theme.text
                }
                Text {
                    text: "FIELD STATION"
                    font.family: Theme.dataFont
                    font.pixelSize: 10
                    font.letterSpacing: 2
                    color: Theme.teal
                }
            }
            Item {
                Layout.fillWidth: true
            }
            // Go already has a bar button; offer it here only when that is hidden.
            StationButton {
                iconOnly: true
                visible: Config.stage >= 3 && !Config.moduleEnabled("go")
                text: "󰀻"
                hint: "Applications"
                onClicked: Go.toggle("root")
            }
            StationButton {
                iconOnly: true
                visible: Config.stage >= 3
                text: "󰸉"
                hint: "Wallpapers"
                onClicked: ShellState.toggle("wallpapers")
            }
            StationButton {
                iconOnly: true
                visible: Config.stage >= 3
                text: "󰏘"
                hint: "Themes"
                onClicked: ShellState.toggle("themes")
            }
            StationButton {
                iconOnly: true
                text: "×"
                hint: "Close Field Station"
                onClicked: ShellState.close()
            }
        }
        Rule {}
        GridLayout {
            Layout.fillWidth: true
            columns: root.narrow ? 1 : 2
            columnSpacing: 48
            rowSpacing: 24
            StationCore {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 270
                Layout.preferredHeight: 270
                active: root.active
                time: Config.timeDigits(clock.date)
                period: Config.clock24 ? "" : Qt.formatDateTime(clock.date, "AP")
                activity: SystemStats.cpu
                date: Config.formatDate(clock.date, true).toUpperCase()
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 18
                RowLayout {
                    Layout.fillWidth: true
                    SectionLabel {
                        text: "SYSTEM TELEMETRY"
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                    Text {
                        text: SystemStats.available ? "LIVE" : "WAITING"
                        font.family: Theme.dataFont
                        font.pixelSize: 10
                        color: SystemStats.available ? Theme.green : Theme.muted
                    }
                }
                ActivityTrace {
                    Layout.fillWidth: true
                    active: root.active
                    value: SystemStats.cpu
                }
                Metric {
                    title: "Processor"
                    value: SystemStats.cpu
                    readout: value < 0 ? "—" : Math.round(value * 100) + "%"
                }
                Metric {
                    title: "Memory"
                    value: SystemStats.ram
                    readout: value < 0 ? "—" : Math.round(value * 100) + "%"
                    detail: SystemStats.memoryLabel
                }
                Metric {
                    title: "Storage"
                    value: SystemStats.disk
                    readout: value < 0 ? "—" : Math.round(value * 100) + "%"
                }
                Metric {
                    title: "Temperature"
                    value: SystemStats.temperature < 0 ? -1 : SystemStats.temperature / 100
                    readout: value < 0 ? "—" : Math.round(SystemStats.temperature) + "°C"
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            Text {
                text: "UP " + SystemStats.uptime
                font.family: Theme.dataFont
                font.pixelSize: 11
                color: Theme.muted
            }
            Item {
                Layout.fillWidth: true
            }
            Text {
                Layout.fillWidth: true
                text: Network.label
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
                font.family: Theme.dataFont
                font.pixelSize: 11
                color: Theme.muted
            }
        }
        Rule {}
        GridLayout {
            Layout.fillWidth: true
            columns: root.narrow ? 1 : 2
            columnSpacing: 40
            rowSpacing: 24
            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                spacing: 10
                SectionLabel {
                    text: "ON THE AIR"
                }
                Text {
                    Layout.fillWidth: true
                    text: root.player?.trackTitle || "The woods are quiet"
                    elide: Text.ElideRight
                    font.family: Theme.labelFont
                    font.pixelSize: 23
                    color: Theme.text
                }
                Text {
                    Layout.fillWidth: true
                    text: root.player?.trackArtist || "A little light. A little room to listen."
                    elide: Text.ElideRight
                    font.family: Theme.dataFont
                    font.pixelSize: 11
                    color: Theme.muted
                }
                RowLayout {
                    spacing: 4
                    StationButton {
                        iconOnly: true
                        text: "󰒮"
                        hint: "Previous track"
                        enabled: root.player?.canGoPrevious ?? false
                        onClicked: root.player.previous()
                    }
                    StationButton {
                        iconOnly: true
                        text: root.player?.isPlaying ? "󰏤" : "󰐊"
                        hint: root.player?.isPlaying ? "Pause" : "Play"
                        enabled: root.player?.canTogglePlaying ?? false
                        onClicked: root.player.togglePlaying()
                    }
                    StationButton {
                        iconOnly: true
                        text: "󰒭"
                        hint: "Next track"
                        enabled: root.player?.canGoNext ?? false
                        onClicked: root.player.next()
                    }
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                spacing: 10
                SectionLabel {
                    Layout.fillWidth: true
                    text: "SKY WATCH / " + WeatherLocation.label.toUpperCase()
                    elide: Text.ElideRight
                }
                RowLayout {
                    Text {
                        text: Weather.temperature
                        font.family: Theme.labelFont
                        font.pixelSize: 32
                        color: Theme.text
                    }
                    Text {
                        Layout.fillWidth: true
                        text: Weather.condition
                        wrapMode: Text.WordWrap
                        font.family: Theme.dataFont
                        font.pixelSize: 11
                        color: Theme.muted
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: Weather.wind || (Weather.configured ? "Waiting for weather" : "Set your location in Settings")
                    wrapMode: Text.WordWrap
                    font.family: Theme.dataFont
                    font.pixelSize: 11
                    color: Theme.muted
                }
                Text {
                    Layout.fillWidth: true
                    text: "Open-Meteo" + (Weather.updated ? " · " + (Weather.stale ? "STALE " : "") + Weather.updated : "")
                    wrapMode: Text.WordWrap
                    font.family: Theme.dataFont
                    font.pixelSize: 10
                    color: Weather.stale ? Theme.amber : Theme.muted
                }
            }
        }
        Rule {}
        RowLayout {
            Layout.fillWidth: true
            Rectangle {
                implicitWidth: 4
                implicitHeight: 4
                radius: 2
                color: Theme.green
                opacity: root.active ? 0.7 : 0.3
            }
            Text {
                Layout.fillWidth: true
                text: ShellState.greeting
                elide: Text.ElideRight
                font.family: Theme.dataFont
                font.pixelSize: 11
                color: Theme.muted
            }
        }
        Flow {
            Layout.fillWidth: true
            spacing: 8
            Repeater {
                model: [
                    {
                        name: "Terminal",
                        cmd: Config.terminal
                    },
                    {
                        name: "Browser",
                        cmd: Config.browser
                    },
                    {
                        name: "Files",
                        cmd: Config.files
                    }
                ]
                StationButton {
                    required property var modelData
                    text: modelData.name
                    onClicked: {
                        Quickshell.execDetached(["systemd-run", "--user", "--scope", "--quiet", "--collect", "--"].concat(modelData.cmd));
                        ShellState.close();
                    }
                }
            }
        }
        Rule {}
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 12
            SectionLabel {
                text: "ROOTED"
            }
            ReadingText {
                text: Branding.content.rooted
            }
            ReadingText {
                text: "“" + Branding.content.psalm.text + "”"
            }
            ReadingText {
                text: Branding.content.psalm.reference + " · " + Branding.content.psalm.translation
                color: Theme.muted
                font.pixelSize: Theme.normal
            }
        }
    }
    component Rule: Rectangle {
        Layout.fillWidth: true
        implicitHeight: 1
        color: Qt.alpha(Theme.teal, 0.13)
    }
    component SectionLabel: Text {
        font.family: Theme.dataFont
        font.pixelSize: 10
        font.letterSpacing: 1.4
        color: Theme.teal
    }
    component Metric: ColumnLayout {
        id: metric
        property string title: ""
        property string readout: ""
        property string detail: ""
        property real value: -1
        Layout.fillWidth: true
        spacing: 6
        RowLayout {
            Layout.fillWidth: true
            Text {
                text: metric.title
                font.family: Theme.dataFont
                font.pixelSize: 12
                color: Theme.muted
            }
            Item {
                Layout.fillWidth: true
            }
            Text {
                text: metric.readout
                font.family: Theme.dataFont
                font.pixelSize: 13
                color: metric.value > 0.85 ? Theme.amber : Theme.text
            }
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 2
            color: Qt.alpha(Theme.teal, 0.12)
            Rectangle {
                width: parent.width * Math.max(0, Math.min(1, metric.value))
                height: parent.height
                color: metric.value > 0.85 ? Theme.amber : Theme.teal
                Behavior on width {
                    enabled: root.active && !Theme.reducedMotion
                    NumberAnimation {
                        duration: Theme.transition
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }
        Text {
            visible: metric.detail !== ""
            text: metric.detail
            font.family: Theme.dataFont
            font.pixelSize: 10
            color: Theme.muted
        }
    }
}
