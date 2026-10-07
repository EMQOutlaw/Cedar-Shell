import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Services.Mpris
import Quickshell.Services.UPower
import ".."
import "../components"
import "../services"

// Quick Controls in the Core pill's language: slim chamfered level rows,
// lit tiles for toggles, and one row for what is playing.
ColumnLayout {
    id: root
    property bool active: false
    readonly property var player: Media.player
    readonly property bool nerd: Theme.availableFonts.includes("JetBrainsMono Nerd Font")
    function glyph(icon, fallback) { return nerd ? icon : fallback; }
    onActiveChanged: if (active)
        Controls.refresh()
    spacing: 10

    // Each instrument settles a beat after the last; `order` sets the beat.
    function beat(order, span = .4) { return Canopy.ease(.06 * order, span); }

    component LevelPill: Item {
        id: level
        property string icon: ""
        property string label: ""
        property real value: 0
        property bool muted: false
        property bool canMute: true
        property string sliderName: ""
        property int order: 0
        readonly property real sweep: root.beat(order)
        signal moved(real value)
        signal committed(real value)
        signal toggled()
        Layout.fillWidth: true
        implicitHeight: 44
        opacity: sweep
        transform: Translate { x: 12 * (1 - level.sweep) }
        // A filament lights along the foot of the row as it arrives.
        ChamferFrame { anchors.fill: parent; cut: 7; stroke: Qt.alpha(level.muted ? Theme.amber : Theme.teal, level.muted ? .35 : .16); line: true; lineColor: level.muted ? Theme.amber : Theme.teal; lineFraction: .55 * level.sweep; lineOpacity: .45 }
        RowLayout {
            anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 14; spacing: 8
            StationButton {
                implicitWidth: 34; implicitHeight: 32; iconOnly: true
                enabled: level.canMute
                text: level.icon
                hint: level.canMute ? (level.muted ? "Unmute " : "Mute ") + level.label.toLowerCase() : level.label
                accent: level.muted ? Theme.amber : Theme.teal
                checked: level.muted
                onClicked: level.toggled()
            }
            StationSlider {
                objectName: level.sliderName
                Accessible.name: level.label
                Layout.fillWidth: true
                value: level.value
                onMoved: level.moved(value)
                onCommitted: v => level.committed(v)
            }
            Text {
                Layout.preferredWidth: 46; horizontalAlignment: Text.AlignRight
                text: level.muted ? "MUTED" : Math.round(level.value * 100 * level.sweep) + "%"
                textFormat: Text.PlainText
                font.family: Theme.dataFont; font.pixelSize: level.muted ? 9 : Theme.small; font.letterSpacing: level.muted ? 1.2 : 0
                color: level.muted ? Theme.amber : Theme.green
            }
        }
    }

    component Tile: StationButton {
        id: tile
        property string label: ""
        property string value: ""
        property bool on: false
        property int order: 0
        readonly property real sweep: root.beat(order)
        Layout.fillWidth: true; Layout.preferredWidth: 1
        implicitHeight: 58
        opacity: sweep
        scale: .94 + .06 * sweep
        checked: on
        Accessible.name: label + ": " + value
        background: ChamferFrame {
            cut: 7
            fill: tile.on ? Qt.alpha(Theme.green, .06) : Qt.alpha(Theme.background, .6)
            stroke: tile.visualFocus ? Theme.green : tile.on ? Qt.alpha(Theme.green, .45) : tile.hovered ? Qt.alpha(Theme.teal, .35) : Qt.alpha(Theme.teal, .14)
            strokeWidth: tile.visualFocus ? 2 : 1
            line: tile.on; lineColor: Theme.green; lineFraction: .6
        }
        contentItem: ColumnLayout {
            spacing: 1
            Text { text: tile.label.toUpperCase(); textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: 9; font.letterSpacing: 1.3; color: Theme.muted }
            Text { Layout.fillWidth: true; text: tile.value; textFormat: Text.PlainText; font.family: Theme.labelFont; font.pixelSize: Math.round(17 * Theme.fontScale); color: tile.on ? Theme.green : Theme.text; elide: Text.ElideRight }
        }
    }

    GlowText {
        visible: Controls.error !== ""
        text: Controls.error
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        color: Theme.amber
        font.pixelSize: Theme.small
    }

    // Levels
    LevelPill {
        order: 0
        label: "Volume"; sliderName: "quickVolume"
        icon: Audio.muted ? root.glyph("󰝟", "×") : root.glyph("󰕾", "♪")
        enabled: Audio.audio !== null
        value: Audio.volume; muted: Audio.muted
        onMoved: value => Audio.setVolume(value)
        onToggled: Audio.toggleMute()
    }
    LevelPill {
        order: 1
        label: "Microphone"
        icon: Audio.microphone?.muted ? root.glyph("󰍭", "×") : root.glyph("󰍬", "M")
        visible: Audio.microphone !== null
        value: Audio.microphone?.volume ?? 0; muted: Audio.microphone?.muted ?? false
        onMoved: value => Audio.setMicrophone(value)
        onToggled: Audio.toggleMicrophone()
    }
    LevelPill {
        order: 2
        label: "Brightness"; canMute: false
        icon: root.glyph("󰃠", "☼")
        visible: Brightness.available
        value: Brightness.value
        onCommitted: v => Brightness.change(Math.round((v - Brightness.value) * 100))
    }
    GridLayout {
        Layout.fillWidth: true; columns: root.width < 360 ? 1 : 2; columnSpacing: 8; rowSpacing: 6
        opacity: root.beat(3)
        transform: Translate { y: 6 * (1 - root.beat(3)) }
        StationCombo {
            Layout.fillWidth: true; Layout.preferredWidth: 1; implicitHeight: 30
            visible: Audio.outputs.length > 1
            model: Audio.outputs; textRole: "description"; Accessible.name: "Output device"
            displayText: "OUT  ·  " + currentText
            currentIndex: Audio.outputs.indexOf(Audio.sink)
            onActivated: Audio.selectOutput(Audio.outputs[currentIndex])
        }
        StationCombo {
            Layout.fillWidth: true; Layout.preferredWidth: 1; implicitHeight: 30
            visible: Audio.inputs.length > 1
            model: Audio.inputs; textRole: "description"; Accessible.name: "Microphone device"
            displayText: "MIC  ·  " + currentText
            currentIndex: Audio.inputs.indexOf(Audio.source)
            onActivated: Audio.selectInput(Audio.inputs[currentIndex])
        }
    }

    // Toggles
    GridLayout {
        Layout.fillWidth: true; Layout.topMargin: 4
        columns: 2; columnSpacing: 8; rowSpacing: 8
        uniformCellWidths: true
        Tile {
            order: 4
            visible: Controls.data.nightlight !== null
            label: "Night light"; value: Controls.data.nightlight === true ? "On" : "Off"; on: Controls.data.nightlight === true
            enabled: !Controls.busy
            onClicked: Controls.run({action: "nightlight"})
        }
        Tile {
            order: 5
            label: "Do not disturb"; value: Config.saved.doNotDisturb ? "Quiet" : "Off"; on: Config.saved.doNotDisturb
            onClicked: Config.set("doNotDisturb", !Config.saved.doNotDisturb)
        }
        // Shield: status and a way in; the full management lives in its own window.
        Tile {
            order: 6
            label: "Shield"
            value: Shield.ready ? Shield.headline : "Shield"
            on: Shield.posture === "protected"
            hint: Shield.ready ? Shield.subline + " · opens CEDAR Shield" : "Opens CEDAR Shield"
            onClicked: { Shield.openApp(); Canopy.close(); }
        }
        // Gaming Mode: the desktop quiets itself around the game. The value is
        // the transaction's real result, never an optimistic ON.
        Tile {
            order: 7
            label: "Gaming"
            value: Gaming.busy ? "…" : Gaming.active ? Gaming.activeCount + "/" + Gaming.totalCount + " active" : "Off"
            on: Gaming.active
            enabled: !Gaming.busy
            hint: Gaming.active ? Gaming.summary + (Gaming.detail ? " · " + Gaming.detail : "") : "Super+G · pauses the flair, holds notifications and sleep, performance profile, compositor blur"
            onClicked: Gaming.toggle()
        }
        // Performance mode: the basics only. A tap while it is on turns it off
        // (back to Automatic if it was switched on by hand, Off if a game or
        // battery saver turned it on); a tap while off switches it on.
        Tile {
            order: 8
            label: "Performance"
            value: Config.performanceActive ? (Config.performanceMode === "on" ? "On" : "Auto · " + (Config.powerSaving ? "battery saver" : "game"))
                 : (Config.performanceMode === "off" ? "Off" : "Auto")
            on: Config.performanceActive
            hint: "Stops the breathing light, spores and entrance sweeps while keeping every control"
            onClicked: Config.set("performanceMode", Config.performanceActive ? (Config.performanceMode === "on" ? "auto" : "off") : "on")
        }
    }
    // Power profile: one three-way choice
    ColumnLayout {
        visible: Controls.data.profiles.length > 0
        Layout.fillWidth: true; spacing: 6
        opacity: root.beat(6)
        transform: Translate { y: 6 * (1 - root.beat(6)) }
        SectionMark { text: "POWER"; size: 9; tone: Theme.muted }
        GridLayout {
            Layout.fillWidth: true
            columns: Math.max(1, Controls.data.profiles.length); columnSpacing: 8
            uniformCellWidths: true
            Repeater {
                model: Controls.data.profiles
                StationButton {
                    id: profile
                    required property string modelData
                    required property int index
                    readonly property bool on: Controls.data.profile === modelData
                    Layout.fillWidth: true; implicitHeight: 40
                    opacity: root.beat(7 + index, .35)
                    scale: .94 + .06 * root.beat(7 + index, .35)
                    checked: on; enabled: !Controls.busy
                    text: ({"power-saver": "Saver", "balanced": "Balanced", "performance": "Performance"})[modelData] || modelData
                    Accessible.name: "Power profile " + text + (on ? ", in use" : "")
                    onClicked: if (!on) Controls.run({action: "profile", value: modelData})
                    background: ChamferFrame {
                        cut: 6
                        fill: profile.on ? Qt.alpha(Theme.green, .06) : Qt.alpha(Theme.background, .6)
                        stroke: profile.visualFocus ? Theme.green : profile.on ? Qt.alpha(Theme.green, .45) : profile.hovered ? Qt.alpha(Theme.teal, .35) : Qt.alpha(Theme.teal, .14)
                        strokeWidth: profile.visualFocus ? 2 : 1
                        line: profile.on; lineColor: Theme.green; lineFraction: .5
                    }
                    contentItem: Text { text: profile.text; textFormat: Text.PlainText; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; font.family: Theme.labelFont; font.pixelSize: Math.round(16 * Theme.fontScale); color: profile.on ? Theme.green : Theme.text; elide: Text.ElideRight }
                }
            }
        }
    }
    RowLayout {
        Layout.fillWidth: true
        visible: (UPower.displayDevice?.isPresent ?? false) || !Config.saved.canopyEnabled
        opacity: root.beat(10)
        StatusPill {
            visible: UPower.displayDevice?.isPresent ?? false
            text: Math.round((UPower.displayDevice?.percentage ?? 0) * 100) + "% · " + (UPower.onBattery ? "battery" : "plugged in")
            tone: UPower.onBattery && (UPower.displayDevice?.percentage ?? 1) < .2 ? Theme.amber : Theme.green
        }
        Item { Layout.fillWidth: true }
        StationButton {
            visible: !Config.saved.canopyEnabled
            text: "Power & session"
            onClicked: ShellState.toggle("power")
        }
    }

    // On the air
    Item {
        Layout.fillWidth: true; Layout.topMargin: 4
        implicitHeight: 52
        opacity: root.beat(11)
        transform: Translate { y: 8 * (1 - root.beat(11)) }
        ChamferFrame { anchors.fill: parent; cut: 7; stroke: Qt.alpha(Theme.teal, .14); line: root.player?.isPlaying ?? false; lineColor: Theme.teal; lineFraction: .5 * root.beat(11, .6); lineOpacity: .6 }
        RowLayout {
            anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 8; spacing: 6
            ColumnLayout {
                Layout.fillWidth: true; spacing: 1
                Text { Layout.fillWidth: true; text: root.player?.trackTitle || "The woods are quiet"; textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: Theme.small; color: root.player ? Theme.text : Theme.muted; elide: Text.ElideRight }
                Text { Layout.fillWidth: true; visible: text !== ""; text: root.player?.trackArtist || ""; textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: 10; color: Theme.muted; elide: Text.ElideRight }
            }
            StationButton { visible: !!root.player; iconOnly: true; implicitWidth: 32; text: root.glyph("󰒮", "‹"); hint: "Previous"; enabled: root.player?.canGoPrevious ?? false; onClicked: root.player.previous() }
            StationButton { visible: !!root.player; iconOnly: true; implicitWidth: 32; text: root.player?.isPlaying ? root.glyph("󰏤", "Ⅱ") : root.glyph("󰐊", "▶"); hint: root.player?.isPlaying ? "Pause" : "Play"; enabled: root.player?.canTogglePlaying ?? false; onClicked: root.player.togglePlaying() }
            StationButton { visible: !!root.player; iconOnly: true; implicitWidth: 32; text: root.glyph("󰒭", "›"); hint: "Next"; enabled: root.player?.canGoNext ?? false; onClicked: root.player.next() }
        }
    }
}
