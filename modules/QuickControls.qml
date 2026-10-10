import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Services.Mpris
import Quickshell.Services.UPower
import ".."
import "../components"
import "../services"

// Quick Controls in the Core pill's language: three tiles for the links
// that matter (network, Bluetooth, quiet hours), slim level rows, the
// station's stances as a compact grid, one power choice, and what is
// playing. Every reading is the service's own; absent hardware is hidden.
ColumnLayout {
    id: root
    property bool active: false
    readonly property var player: Media.player
    readonly property bool nerd: Theme.availableFonts.includes("JetBrainsMono Nerd Font")
    function glyph(icon, fallback) { return nerd ? icon : fallback; }
    onActiveChanged: if (active)
        Controls.refresh()
    spacing: 12

    // Each instrument settles a beat after the last; `order` sets the beat.
    // Starts stay under .7 of the entrance clock so every instrument reaches full by its end.
    function beat(order, span = .4) { return Canopy.ease(.06 * order, span); }

    // A level row: the icon is the mute control, the label names it, the
    // slider is the reading and the number confirms it. No frame.
    component LevelRow: Item {
        id: level
        property string icon: ""
        property string label: ""
        property real value: 0
        property bool muted: false
        property bool canMute: true
        property string sliderName: ""
        property real order: 0
        readonly property real sweep: root.beat(order)
        signal moved(real value)
        signal committed(real value)
        signal toggled()
        Layout.fillWidth: true
        implicitHeight: 36
        opacity: sweep
        transform: Translate { x: 12 * (1 - level.sweep) }
        RowLayout {
            anchors.fill: parent; spacing: 10
            StationButton {
                implicitWidth: 32; implicitHeight: 32; iconOnly: true
                enabled: level.canMute
                text: level.icon
                hint: level.canMute ? (level.muted ? "Unmute " : "Mute ") + level.label.toLowerCase() : level.label
                accent: level.muted ? Theme.amber : Theme.teal
                checked: level.muted
                onClicked: level.toggled()
            }
            Text {
                Layout.preferredWidth: 96
                text: level.label; textFormat: Text.PlainText
                font.family: Theme.labelFont; font.pixelSize: Math.round(14 * Theme.fontScale)
                color: level.muted ? Theme.amber : Theme.text
                elide: Text.ElideRight
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

    // A tile: glyph and name on the first line, the state dot at the far
    // right, and the reading on the second line. Lit along its foot when on.
    component Tile: StationButton {
        id: tile
        property string mark: ""
        property string label: ""
        property string value: ""
        property bool on: false
        property real order: 0
        readonly property real sweep: root.beat(order)
        Layout.fillWidth: true; Layout.preferredWidth: 1
        implicitHeight: 60
        padding: 12
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
            spacing: 3
            RowLayout {
                Layout.fillWidth: true; spacing: 8
                Text { visible: tile.mark !== ""; text: tile.mark; textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: 15; color: tile.on ? Theme.green : Theme.muted }
                Text { Layout.fillWidth: true; text: tile.label; textFormat: Text.PlainText; font.family: Theme.labelFont; font.pixelSize: Math.round(15 * Theme.fontScale); color: tile.on ? Theme.green : Theme.text; elide: Text.ElideRight }
                Rectangle { width: 5; height: 5; radius: 3; color: tile.on ? Theme.green : Theme.muted; opacity: tile.on ? 1 : .5; Layout.alignment: Qt.AlignVCenter }
            }
            KineticLabel { Layout.fillWidth: true; height: implicitHeight; text: tile.value; transitionStyle: "resolve"; font.family: Theme.dataFont; font.pixelSize: 10; color: Theme.muted; elide: Text.ElideRight }
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

    // The links: real state from NetworkManager, BlueZ and the notification policy.
    GridLayout {
        Layout.fillWidth: true
        columns: root.width < 420 ? 1 : 3; columnSpacing: 8; rowSpacing: 8
        uniformCellWidths: true
        Tile {
            order: 0
            mark: root.nerd ? Network.glyph : Network.fallbackGlyph
            label: "Network"
            value: Network.label
            on: Network.state === "connected"
            // The tile is the Wi-Fi radio where there is one; otherwise it reports and stays still.
            enabled: Network.data.available && Network.data.hardware && !Network.busy
            hint: Network.data.hardware ? (Network.data.enabled ? "Wi-Fi on · tap to turn the radio off" : "Wi-Fi off · tap to turn the radio on") : Network.statusDescription
            onClicked: Network.run({ action: "radio", enabled: !Network.data.enabled })
        }
        Tile {
            order: 1
            visible: BluetoothService.available && BluetoothService.adapter !== null
            mark: root.glyph("󰂯", "B")
            readonly property var connected: BluetoothService.devices.filter(d => d.connected)
            label: "Bluetooth"
            value: !(BluetoothService.adapter?.enabled ?? false) ? "Off" : connected.length === 0 ? "On · nothing connected" : connected.length === 1 ? (connected[0].name || connected[0].address) + " connected" : connected.length + " devices connected"
            on: BluetoothService.adapter?.enabled ?? false
            enabled: !BluetoothService.busy
            hint: on ? "Tap to turn Bluetooth off" : "Tap to turn Bluetooth on"
            onClicked: BluetoothService.adapter.enabled = !BluetoothService.adapter.enabled
        }
        Tile {
            order: 2
            mark: Config.saved.doNotDisturb ? root.glyph("󰂛", "Z") : root.glyph("󰂚", "N")
            label: "Quiet hours"
            value: Config.saved.doNotDisturb ? "On · notifications held" : "Off · notifications on"
            on: Config.saved.doNotDisturb
            hint: "Do not disturb: hold notifications until you return"
            onClicked: Config.set("doNotDisturb", !Config.saved.doNotDisturb)
        }
    }

    // Levels
    ColumnLayout {
        Layout.fillWidth: true; spacing: 2
        LevelRow {
            order: 3
            label: "Output"; sliderName: "quickVolume"
            icon: Audio.muted ? root.glyph("󰝟", "×") : root.glyph("󰕾", "♪")
            enabled: Audio.audio !== null
            value: Audio.volume; muted: Audio.muted
            onMoved: value => Audio.setVolume(value)
            onToggled: Audio.toggleMute()
        }
        LevelRow {
            order: 4
            label: "Microphone"
            icon: Audio.microphone?.muted ? root.glyph("󰍭", "×") : root.glyph("󰍬", "M")
            visible: Audio.microphone !== null
            value: Audio.microphone?.volume ?? 0; muted: Audio.microphone?.muted ?? false
            onMoved: value => Audio.setMicrophone(value)
            onToggled: Audio.toggleMicrophone()
        }
        LevelRow {
            order: 5
            label: "Brightness"; canMute: false
            icon: root.glyph("󰃠", "☼")
            visible: Brightness.available
            value: Brightness.value
            onCommitted: v => Brightness.change(Math.round((v - Brightness.value) * 100))
        }
    }
    GridLayout {
        Layout.fillWidth: true; columns: root.width < 360 ? 1 : 2; columnSpacing: 8; rowSpacing: 6
        visible: Audio.outputs.length > 1 || Audio.inputs.length > 1
        opacity: root.beat(5)
        transform: Translate { y: 6 * (1 - root.beat(5)) }
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
    Rectangle { Layout.fillWidth: true; height: 1; color: Qt.alpha(Theme.border, .5); opacity: root.beat(5) }

    // The station's stances: each tile is the real state and a way in.
    ColumnLayout {
        Layout.fillWidth: true; spacing: 6
        opacity: root.beat(6)
        transform: Translate { y: 6 * (1 - root.beat(6)) }
        SectionMark { text: "STATION"; size: 9; tone: Theme.muted }
        GridLayout {
            Layout.fillWidth: true
            columns: root.width < 420 ? 2 : 3; columnSpacing: 8; rowSpacing: 8
            uniformCellWidths: true
            Tile {
                order: 6
                visible: Controls.data.nightlight !== null
                mark: root.glyph("󰖔", "N")
                label: "Night light"; value: Controls.data.nightlight === true ? "On" : "Off"; on: Controls.data.nightlight === true
                enabled: !Controls.busy
                onClicked: Controls.run({action: "nightlight"})
            }
            // Shield: status and a way in; the full management lives in its own window.
            Tile {
                order: 6.5
                mark: root.glyph("󰒃", "S")
                label: "Shield"
                value: Shield.ready ? Shield.headline : "Shield"
                on: Shield.posture === "protected"
                hint: Shield.ready ? Shield.subline + " · opens CEDAR Shield" : "Opens CEDAR Shield"
                onClicked: { Shield.openApp(); Canopy.close(); }
            }
            // Desktop Profiles: the current stance and a way in.
            Tile {
                order: 7
                mark: root.glyph("󰙅", "P")
                label: "Profile"
                value: Profiles.anyBusy ? "…" : Profiles.current ? Profiles.currentLabel : "None"
                on: !!Profiles.current
                hint: (Profiles.current ? Profiles.summary + " · " : "") + "opens CEDAR Profiles"
                onClicked: { Profiles.openApp(); Canopy.close(); }
            }
            // Gaming Mode: the desktop quiets itself around the game. The value is
            // the transaction's real result, never an optimistic ON.
            Tile {
                order: 7.5
                mark: root.glyph("󰊗", "G")
                label: "Gaming"
                value: Gaming.busy ? "…" : Gaming.active ? Gaming.activeCount + "/" + Gaming.totalCount + " active" : "Off"
                on: Gaming.active
                enabled: !Gaming.busy
                hint: Gaming.active ? Gaming.summary + (Gaming.detail ? " · " + Gaming.detail : "") : "Super+G · pauses the flair, holds notifications and sleep, performance profile, compositor blur"
                onClicked: Gaming.toggle()
            }
            // Focus: a timed quiet session; the tile shows the time left and opens the window.
            Tile {
                order: 8
                mark: root.glyph("󰔛", "F")
                label: "Focus"
                value: Focus.busy ? "…" : Focus.active ? (Focus.paused ? "Paused" : Focus.minutes(Focus.remaining) + " left") : "Off"
                on: Focus.active
                hint: (Focus.active ? Focus.summary + " · " : "") + "opens CEDAR Focus"
                onClicked: { Focus.openApp(); Canopy.close(); }
            }
            // Performance mode: the basics only. A tap while it is on turns it off
            // (back to Automatic if it was switched on by hand, Off if a game or
            // battery saver turned it on); a tap while off switches it on.
            Tile {
                order: 8.5
                mark: root.glyph("󱐋", "⚡")
                label: "Performance"
                value: Config.performanceActive ? (Config.performanceMode === "on" ? "On" : "Auto · " + (Config.powerSaving ? "battery saver" : "game"))
                     : (Config.performanceMode === "off" ? "Off" : "Auto")
                on: Config.performanceActive
                hint: "Stops the breathing light, spores and entrance sweeps while keeping every control"
                onClicked: Config.set("performanceMode", Config.performanceActive ? (Config.performanceMode === "on" ? "auto" : "off") : "on")
            }
        }
    }
    // Power profile: one three-way choice
    ColumnLayout {
        visible: Controls.data.profiles.length > 0
        Layout.fillWidth: true; spacing: 6
        opacity: root.beat(9)
        transform: Translate { y: 6 * (1 - root.beat(9)) }
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
                    opacity: root.beat(9.5 + index * .5, .35)
                    scale: .94 + .06 * root.beat(9.5 + index * .5, .35)
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
        Layout.fillWidth: true
        implicitHeight: 52
        opacity: root.beat(10.5)
        transform: Translate { y: 8 * (1 - root.beat(10.5)) }
        ChamferFrame { anchors.fill: parent; cut: 7; stroke: Qt.alpha(Theme.teal, .14); line: root.player?.isPlaying ?? false; lineColor: Theme.teal; lineFraction: .5 * root.beat(10.5, .6); lineOpacity: .6 }
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
