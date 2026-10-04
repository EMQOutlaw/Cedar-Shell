pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../.."
import ".."
import "../../services"
import "Policy.js" as Policy

Instrument {
    id: root
    required property string kind
    required property date date
    property bool privateMode: true
    readonly property bool evening: date.getHours() >= 17
    readonly property var sun: Policy.solar(date, Config.latitude, Config.longitude)
    readonly property var nextEvent: Trailwatch.extraFresh ? Policy.upcoming(Trailwatch.extra.agenda.events, date.getTime(), false) : null
    readonly property var tomorrowEvent: Trailwatch.extraFresh ? Policy.upcoming(Trailwatch.extra.agenda.events, date.getTime(), true) : null
    readonly property var reminder: Trailwatch.extraFresh ? Policy.upcoming(Trailwatch.extra.reminders, date.getTime(), false) : null
    readonly property bool mediaPrivate: privateMode || !Config.saved.lockMediaDetails
    readonly property bool agendaPrivate: privateMode || !Config.saved.lockAgendaDetails
    readonly property var update: CoreService.rows.find(r => r.type === "update")
    title: ({
            sky: "SKY WATCH",
            trail: "TRAIL BOARD",
            signal: "SIGNAL BEACON",
            power: "CAMP POWER",
            media: "ON THE AIR",
            system: "WATCHTOWER"
        })[kind]
    index: ({
            sky: "01",
            trail: "02",
            signal: "03",
            power: "04",
            media: "05",
            system: "06"
        })[kind]
    badge: kind === "sky" ? (Trailwatch.weatherStale ? "NO LIVE READING" : "FORECAST") : kind === "trail" ? "UP NEXT" : kind === "system" ? "LIVE" : ""
    accent: kind === "power" && Trailwatch.lowPower ? Theme.amber : kind === "sky" ? Theme.amber : Theme.teal
    function stamp(at) {
        return at === null || at === undefined ? "—" : Config.formatTime(new Date(at));
    }
    function pct(value) {
        return value < 0 ? "—" : Math.round(value * 100) + "%";
    }
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 10
        visible: root.kind === "sky"
        RowLayout {
            Layout.fillWidth: true
            FieldText {
                text: Weather.temperature
                font.pixelSize: 48
                font.family: Theme.labelFont
                font.bold: true
                color: Theme.green
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                FieldText {
                    Layout.fillWidth: true
                    text: Weather.updatedAt ? Weather.condition : Weather.configured ? "Weather unavailable" : "Location not set"
                    wrapMode: Text.WordWrap
                    elide: Text.ElideNone
                    font.pixelSize: Theme.small
                }
                FieldText {
                    Layout.fillWidth: true
                    text: Weather.updatedAt ? "Feels like " + Weather.feelsLike : "Set coordinates in Settings"
                    font.pixelSize: 11
                    color: Theme.muted
                }
            }
        }
        Metric {
            label: "WIND"
            value: Weather.wind || "—"
        }
        Metric {
            label: "RAIN · THIS HOUR"
            value: Weather.rain === null ? "—" : Weather.rain + "%"
            accent: Weather.rain >= 60 ? Theme.amber : Theme.text
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Theme.border
        }
        Metric {
            label: root.evening ? "LAST LIGHT" : "FIRST LIGHT"
            value: root.stamp(root.sun ? (root.evening ? root.sun.dusk : root.sun.dawn) : null)
            accent: Theme.amber
        }
        Metric {
            label: "SUNRISE / SUNSET"
            value: root.stamp(root.sun?.sunrise) + " / " + root.stamp(root.sun?.sunset)
        }
        FieldText {
            Layout.fillWidth: true
            text: Weather.updatedAt ? (Trailwatch.weatherStale ? "STALE · " : "") + "Open-Meteo · " + Weather.updated + "  /  Light times ≈ local" : "Weather awaits a location and connection"
            color: Theme.muted
            font.pixelSize: 10
        }
    }
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 10
        visible: root.kind === "trail"
        FieldText {
            Layout.fillWidth: true
            text: root.nextEvent ? (new Date(root.nextEvent.at).toDateString() === root.date.toDateString() ? "" : Qt.formatDateTime(new Date(root.nextEvent.at), "ddd ")) + root.stamp(root.nextEvent.at) : "CLEAR HORIZON"
            font.pixelSize: 25
            font.family: Theme.labelFont
            color: Theme.green
        }
        FieldText {
            Layout.fillWidth: true
            text: root.nextEvent ? (root.agendaPrivate ? "Calendar event · details hidden" : root.nextEvent.title) : !Trailwatch.extraFresh ? "Agenda unavailable" : Trailwatch.extra.agenda.status === "ready" ? "No upcoming events" : Trailwatch.extra.agenda.status === "unconfigured" ? "Calendar not connected" : "Calendar feed " + Trailwatch.extra.agenda.status
            wrapMode: Text.WordWrap
            elide: Text.ElideNone
            font.pixelSize: Theme.small
            color: Theme.muted
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Theme.border
        }
        Metric {
            visible: root.evening && !!root.tomorrowEvent && root.tomorrowEvent.at !== root.nextEvent?.at
            label: "TOMORROW / NEXT"
            value: root.tomorrowEvent ? root.stamp(root.tomorrowEvent.at) : ""
            accent: Theme.teal
        }
        Metric {
            label: "REMINDER"
            value: root.reminder ? root.stamp(root.reminder.at) : Trailwatch.extraFresh && Trailwatch.extra.reminders !== null ? "None scheduled" : "Unavailable"
        }
        FieldText {
            visible: !!root.reminder && !root.agendaPrivate
            Layout.fillWidth: true
            text: root.reminder?.title || ""
            font.pixelSize: Theme.small
        }
        Metric {
            label: "TIMER"
            value: CoreService.timer.active ? Media.elapsed(CoreService.timer.remaining) + (CoreService.timer.paused ? " · paused" : "") : CoreService.timer.completed ? "Complete" : "No active timer"
            accent: CoreService.timer.completed ? Theme.amber : Theme.teal
        }
        FieldText {
            visible: CoreService.timer.active && !root.agendaPrivate
            Layout.fillWidth: true
            text: CoreService.timer.label
            font.pixelSize: Theme.small
            color: Theme.muted
        }
    }
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 10
        visible: root.kind === "signal"
        FieldText {
            Layout.fillWidth: true
            text: Trailwatch.link.toUpperCase()
            font.family: Theme.labelFont
            font.pixelSize: 27
            color: Trailwatch.linked ? Theme.green : Theme.muted
        }
        FieldText {
            Layout.fillWidth: true
            text: Trailwatch.internet
            wrapMode: Text.WordWrap
            elide: Text.ElideNone
            font.pixelSize: Theme.small
            color: Theme.muted
        }
        Metric {
            label: "VPN"
            value: !Trailwatch.netKnown ? "Unavailable" : Trailwatch.vpn ? "Connected" : "Not connected"
            accent: Trailwatch.vpn ? Theme.teal : Theme.muted
        }
        Metric {
            label: "BLUETOOTH"
            value: !BluetoothService.adapter ? "Unavailable" : BluetoothService.adapter.enabled ? "On" : "Off"
        }
        Metric {
            label: "CONNECTED DEVICES"
            value: BluetoothService.adapter ? String(Trailwatch.connected.length) : "—"
        }
    }
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 10
        visible: root.kind === "power"
        RowLayout {
            Layout.fillWidth: true
            FieldText {
                text: Trailwatch.power
                font.pixelSize: 40
                font.family: Theme.labelFont
                font.bold: true
                color: Trailwatch.lowPower ? Theme.amber : Theme.green
            }
            FieldText {
                Layout.fillWidth: true
                text: Trailwatch.powerState
                font.pixelSize: Theme.small
                color: Theme.muted
                horizontalAlignment: Text.AlignRight
            }
        }
        Row {
            visible: Trailwatch.hasBattery
            Layout.fillWidth: true
            spacing: 3
            Repeater {
                model: 20
                Rectangle {
                    required property int index
                    width: (parent.width - 57) / 20
                    height: 5
                    radius: 1
                    color: index < Trailwatch.battery.percentage * 20 ? (Trailwatch.lowPower ? Theme.amber : Theme.green) : Theme.border
                }
            }
        }
        Metric {
            label: "PROFILE"
            value: Trailwatch.profile
        }
        Repeater {
            model: Trailwatch.deviceBatteries.slice(0, 3)
            Metric {
                required property var modelData
                required property int index
                label: root.privateMode ? "DEVICE " + (index + 1) : (modelData.name || "Device")
                value: Math.round(modelData.battery * 100) + "%"
            }
        }
        FieldText {
            visible: !Trailwatch.deviceBatteries.length
            Layout.fillWidth: true
            text: "No peripheral battery reports"
            font.pixelSize: 10
            color: Theme.muted
        }
    }
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 10
        visible: root.kind === "media"
        FieldText {
            Layout.fillWidth: true
            text: !Media.player ? "THE AIR IS QUIET" : root.mediaPrivate ? (Media.player.isPlaying ? "MEDIA PLAYING" : "MEDIA PAUSED") : (Media.player.trackTitle || "Untitled media")
            font.family: Theme.labelFont
            font.pixelSize: 24
            maximumLineCount: 2
            wrapMode: Text.Wrap
            elide: Text.ElideRight
            color: Theme.green
        }
        FieldText {
            Layout.fillWidth: true
            text: !Media.player ? "No active player" : root.mediaPrivate ? "Track details are hidden" : Media.player.trackArtist || "Unknown artist"
            font.pixelSize: Theme.small
            color: Theme.muted
        }
        RowLayout {
            visible: Config.saved.lockMediaControls
            Layout.fillWidth: true
            StationButton {
                text: "Ⅰ‹"
                hint: "Previous track"
                enabled: !!Media.player?.canGoPrevious
                onClicked: Media.previous()
            }
            StationButton {
                text: Media.player?.isPlaying ? "PAUSE" : "PLAY"
                Layout.fillWidth: true
                enabled: !!Media.player?.canTogglePlaying
                onClicked: Media.toggle()
            }
            StationButton {
                text: "›Ⅰ"
                hint: "Next track"
                enabled: !!Media.player?.canGoNext
                onClicked: Media.next()
            }
        }
        Metric {
            label: "OUTPUT"
            value: !Audio.sink ? "Unavailable" : root.privateMode ? "Connected" : Audio.sink.description || "Default output"
        }
        RowLayout {
            Layout.fillWidth: true
            FieldText {
                text: "VOLUME"
                color: Theme.muted
                font.pixelSize: Theme.small
                Layout.fillWidth: true
            }
            StationButton {
                visible: Config.saved.lockMediaControls
                text: "−"
                hint: "Lower volume"
                enabled: !!Audio.audio
                implicitWidth: 32
                onClicked: Audio.setVolume(Audio.volume - .05)
            }
            FieldText {
                text: Audio.label
                font.pixelSize: Theme.small
            }
            StationButton {
                visible: Config.saved.lockMediaControls
                text: "+"
                hint: "Raise volume"
                enabled: !!Audio.audio
                implicitWidth: 32
                onClicked: Audio.setVolume(Audio.volume + .05)
            }
        }
    }
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 10
        visible: root.kind === "system"
        RowLayout {
            Layout.fillWidth: true
            spacing: 18
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3
                FieldText {
                    text: "CPU"
                    font.pixelSize: 10
                    color: Theme.muted
                }
                FieldText {
                    text: root.pct(SystemStats.cpu)
                    font.family: Theme.labelFont
                    font.pixelSize: 30
                    color: Theme.green
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3
                FieldText {
                    text: "RAM"
                    font.pixelSize: 10
                    color: Theme.muted
                }
                FieldText {
                    text: root.pct(SystemStats.ram)
                    font.family: Theme.labelFont
                    font.pixelSize: 30
                    color: Theme.teal
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3
                FieldText {
                    text: "SENSOR"
                    font.pixelSize: 10
                    color: Theme.muted
                }
                FieldText {
                    text: SystemStats.temperature < 0 ? "—" : Math.round(SystemStats.temperature) + "°"
                    font.family: Theme.labelFont
                    font.pixelSize: 30
                    color: SystemStats.temperature >= Config.saved.coreTemperatureLimit ? Theme.amber : Theme.text
                }
            }
        }
        Metric {
            label: "MEMORY"
            value: SystemStats.available ? SystemStats.memoryLabel : "Unavailable"
        }
        Metric {
            label: "DISK USED"
            value: root.pct(SystemStats.disk)
            accent: SystemStats.disk * 100 >= Config.saved.coreDiskLimit ? Theme.amber : Theme.text
        }
        Metric {
            visible: Trailwatch.extraFresh && Trailwatch.extra.gpus.length > 0
            label: "GPU"
            value: Trailwatch.extra.gpus.map(g => g.load + "%").join(" / ")
        }
        Metric {
            label: "UPDATES"
            value: root.update ? root.update.title : "Not checked"
        }
        Metric {
            label: "FAILED SERVICES"
            value: !Trailwatch.extraFresh || Trailwatch.extra.failed === null ? "Unavailable" : String(Trailwatch.extra.failed)
            accent: Trailwatch.extra.failed > 0 ? Theme.amber : Theme.muted
        }
    }
}
