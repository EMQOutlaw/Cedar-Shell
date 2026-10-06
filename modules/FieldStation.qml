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
    // Bare: hosted inside a surface that already paints the card and the
    // atmosphere (the bar drop), so the station draws only its instruments.
    property bool bare: false
    readonly property bool narrow: width < 680
    readonly property int inset: narrow ? 22 : 36
    readonly property var player: Media.player
    implicitHeight: content.implicitHeight + inset * 2
    color: bare ? Theme.transparent : Qt.alpha(Theme.background, Config.panelOpacity)
    radius: bare ? 0 : Config.panelRadius
    border.width: bare ? 0 : 1
    border.color: Qt.alpha(Theme.teal, 0.18)
    // Entrance: one linear clock drives every instrument through ease(), so the
    // title settles, the filament lights, the dial blooms and the telemetry
    // sweeps in as a single animation of about a second. Reduced Motion snaps.
    property real reveal: 1
    function ease(start, span) {
        const t = Math.max(0, Math.min(1, (reveal - start) / span));
        return 1 - Math.pow(1 - t, 3);
    }
    function enter() {
        entrance.stop();
        if (Theme.reducedMotion || Config.testMode) { reveal = 1; return; }
        reveal = 0;
        entrance.start();
    }
    NumberAnimation { id: entrance; target: root; property: "reveal"; from: 0; to: 1; duration: 1050 }
    Connections { target: Theme; function onReducedMotionChanged() { if (Theme.reducedMotion) { entrance.stop(); root.reveal = 1; } } }
    onActiveChanged: if (active) enter(); else { entrance.stop(); reveal = 1; }
    Component.onCompleted: if (active) enter()
    SystemClock {
        id: clock
        precision: SystemClock.Minutes
        enabled: root.active
    }
    CedarAtmosphere {
        anchors.fill: parent
        active: root.active && !root.bare && Config.saved.ambientIntensity > 0
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
                opacity: root.ease(0, .45)
                transform: Translate { y: 6 * (1 - root.ease(0, .45)) }
                Text {
                    text: "CEDAR"
                    font.family: Theme.labelFont
                    font.pixelSize: 24
                    // The letters settle in from a wider spread.
                    font.letterSpacing: 4 + 8 * (1 - root.ease(0, .6))
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
                onClicked: Config.saved.canopyEnabled ? Canopy.toggleTopic("go") : Go.toggle("root")
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
                onClicked: Canopy.shown && Canopy.topic === "station" ? Canopy.close() : ShellState.close()
            }
        }
        // The filament lights from the left and a hot green tip runs ahead of it.
        Item {
            Layout.fillWidth: true
            implicitHeight: 1
            Rectangle {
                width: parent.width * root.ease(.08, .5)
                height: 1
                color: Qt.alpha(Theme.teal, .28)
                Rectangle {
                    anchors.right: parent.right
                    width: Math.min(parent.width, 120)
                    height: 1
                    color: Theme.green
                    opacity: .8 * (1 - root.ease(.5, .4))
                }
            }
        }
        GridLayout {
            Layout.fillWidth: true
            columns: root.narrow ? 1 : 2
            columnSpacing: 48
            rowSpacing: 24
            StationCore {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 270
                Layout.preferredHeight: 270
                opacity: root.ease(.05, .5)
                scale: .9 + .1 * root.ease(.05, .6)
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
                    // The live dot breathes at the ambient rate and rests with the user.
                    Rectangle {
                        visible: SystemStats.available
                        width: 6; height: 6; radius: 3
                        color: Theme.green
                        opacity: liveBreath.running ? liveBreath.value : .9
                        Breath { id: liveBreath; running: root.active && SystemStats.available && Motion.active; from: .95; to: .35; rise: 1400; fall: 1800 }
                    }
                    Text {
                        text: SystemStats.available ? "LIVE" : "WAITING"
                        font.family: Theme.dataFont
                        font.pixelSize: 10
                        font.letterSpacing: 1.2
                        color: SystemStats.available ? Theme.green : Theme.muted
                    }
                }
                ActivityTrace {
                    Layout.fillWidth: true
                    active: root.active
                    value: SystemStats.cpu
                    opacity: root.ease(.3, .4)
                }
                Metric {
                    order: 0
                    title: "Processor"
                    value: SystemStats.cpu
                    readout: value < 0 ? "—" : Math.round(value * 100 * sweep) + "%"
                }
                Metric {
                    order: 1
                    title: "Memory"
                    value: SystemStats.ram
                    readout: value < 0 ? "—" : Math.round(value * 100 * sweep) + "%"
                    detail: SystemStats.memoryLabel
                }
                Metric {
                    order: 2
                    title: "Storage"
                    value: SystemStats.disk
                    readout: value < 0 ? "—" : Math.round(value * 100 * sweep) + "%"
                }
                Metric {
                    order: 3
                    title: "Temperature"
                    value: SystemStats.temperature < 0 ? -1 : SystemStats.temperature / 100
                    readout: value < 0 ? "—" : Math.round(SystemStats.temperature * sweep) + "°C"
                }
            }
        }
        // Pills wrap at narrow widths instead of forcing the column wider.
        Flow {
            Layout.fillWidth: true
            spacing: 8
            opacity: root.ease(.4, .4)
            transform: Translate { y: 6 * (1 - root.ease(.4, .4)) }
            StatusPill { text: "Up " + SystemStats.uptime; tone: Theme.teal }
            StatusPill { text: Network.label; tone: Network.state === "connected" ? Theme.green : Theme.muted }
            StatusPill { visible: Network.vpnActive; text: "VPN"; tone: Theme.green }
            StatusPill { visible: SystemStats.available; text: "Telemetry live"; tone: Theme.green }
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
                opacity: root.ease(.48, .4)
                transform: Translate { y: 8 * (1 - root.ease(.48, .4)) }
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
                opacity: root.ease(.56, .4)
                transform: Translate { y: 8 * (1 - root.ease(.56, .4)) }
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
            opacity: root.ease(.64, .36)
            transform: Translate { y: 6 * (1 - root.ease(.64, .36)) }
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
            opacity: root.ease(.68, .36)
            transform: Translate { y: 6 * (1 - root.ease(.68, .36)) }
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
            opacity: root.ease(.74, .3)
            transform: Translate { y: 8 * (1 - root.ease(.74, .3)) }
            SectionLabel {
                text: "ROOTED"
            }
            ReadingText {
                text: Branding.content.rooted
            }
            // The verse sits beside an ember rule that glows up from the bottom.
            RowLayout {
                Layout.fillWidth: true
                spacing: 14
                Item {
                    Layout.fillHeight: true
                    implicitWidth: 3
                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: 2
                        height: parent.height * root.ease(.8, .25)
                        color: Theme.ember
                        opacity: .75
                    }
                    Rectangle {
                        anchors.bottom: parent.bottom
                        x: -3
                        width: 8
                        height: parent.height * root.ease(.8, .25)
                        color: Theme.ember
                        opacity: .08
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8
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
        }
    }
    component Rule: Rectangle {
        Layout.fillWidth: true
        implicitHeight: 1
        color: Qt.alpha(Theme.teal, 0.13)
    }
    component SectionLabel: Item {
        property alias text: label.text
        property alias elide: label.elide
        implicitWidth: 22 + label.implicitWidth
        implicitHeight: label.implicitHeight
        Rectangle { y: Math.round(parent.height / 2); width: 14; height: 1; color: Theme.teal; opacity: .7 }
        Text {
            id: label
            x: 22
            width: Math.max(0, parent.width - 22)
            font.family: Theme.dataFont
            font.pixelSize: 10
            font.letterSpacing: 1.4
            color: Theme.teal
        }
    }
    component Metric: ColumnLayout {
        id: metric
        property string title: ""
        property string readout: ""
        property string detail: ""
        property real value: -1
        property int order: 0
        // Each row settles a beat after the last; its bar and readout sweep up with it.
        readonly property real sweep: root.ease(.32 + order * .07, .45)
        opacity: sweep
        transform: Translate { x: 10 * (1 - sweep) }
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
                width: parent.width * Math.max(0, Math.min(1, metric.value)) * metric.sweep
                height: parent.height
                color: metric.value > 0.85 ? Theme.amber : Theme.teal
                // A hot tip rides the end of the bar while it is lit.
                Rectangle { visible: parent.width > 12; anchors.right: parent.right; width: 10; height: parent.height; color: Theme.green; opacity: metric.value > 0.85 ? 0 : .8 }
                Behavior on width {
                    enabled: root.active && !Theme.reducedMotion && !entrance.running
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
