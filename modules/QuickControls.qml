import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Services.UPower
import ".."
import "../components"
import "../services"

// Quick Controls in the Core pill's language: three tiles for the links
// that matter (network, Bluetooth, quiet hours), slim level rows, the
// station's stances as a compact grid and one power choice. Every reading
// is the service's own; absent hardware is hidden. Nothing here repeats a
// control the bar or the Field Station already has: media transport lives in
// the Field Station and the Core pill, and when the bar carries its own audio
// control (Strata) the volume rows and device choices stay with it.
ColumnLayout {
    id: root
    property bool active: false
    readonly property bool nerd: Theme.availableFonts.includes("JetBrainsMono Nerd Font")
    // The bar's audio control (Strata) scrolls the volume and opens the audio
    // instrument, so the level rows are only drawn where the bar has none.
    readonly property bool barAudio: Canopy.barRoute("audio")
    // Strata's battery/power control opens Power and session; the legacy bars have none.
    readonly property bool barPower: Config.barStyle === "cedar" && Config.moduleEnabled("battery")
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
            StrataButton {
                implicitWidth: 32; implicitHeight: 32; iconOnly: true
                enabled: level.canMute
                text: level.icon
                hint: level.canMute ? (level.muted ? "Unmute " : "Mute ") + level.label.toLowerCase() : level.label
                accent: level.muted ? Theme.amber : Theme.strataAccent
                checked: level.muted
                onClicked: level.toggled()
            }
            Text {
                Layout.preferredWidth: 96
                text: level.label; textFormat: Text.PlainText
                font.family: Theme.labelFont; font.pixelSize: Math.round(14 * Theme.fontScale)
                color: level.muted ? Theme.amber : Theme.strataText
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
                color: level.muted ? Theme.amber : Theme.strataAccent
            }
        }
    }

    // A tile: glyph and name on the first line, the state dot at the far
    // right, and the reading on the second line. Lit along its foot when on.
    component Tile: StrataButton {
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
            cut: Theme.strataCut
            fill: tile.on ? Qt.alpha(Theme.strataAccent, .06) : Qt.alpha(Theme.strataFoundation, .6)
            stroke: tile.visualFocus ? Theme.strataAccent : tile.on ? Qt.alpha(Theme.strataAccent, .45) : tile.hovered ? Qt.alpha(Theme.strataAccent, .35) : Qt.alpha(Theme.strataAccent, .14)
            strokeWidth: tile.visualFocus ? 2 : 1
            line: tile.on; lineColor: Theme.strataAccent; lineFraction: .6
        }
        contentItem: ColumnLayout {
            spacing: 3
            RowLayout {
                Layout.fillWidth: true; spacing: 8
                Text { visible: tile.mark !== ""; text: tile.mark; textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: 15; color: tile.on ? Theme.strataAccent : Theme.strataMuted }
                Text { Layout.fillWidth: true; text: tile.label; textFormat: Text.PlainText; font.family: Theme.labelFont; font.pixelSize: Math.round(15 * Theme.fontScale); color: tile.on ? Theme.strataAccent : Theme.strataText; elide: Text.ElideRight }
                Rectangle { width: 5; height: 5; radius: 3; color: tile.on ? Theme.strataAccent : Theme.strataMuted; opacity: tile.on ? 1 : .5; Layout.alignment: Qt.AlignVCenter }
            }
            KineticLabel { Layout.fillWidth: true; height: implicitHeight; text: tile.value; transitionStyle: "resolve"; font.family: Theme.dataFont; font.pixelSize: 10; color: Theme.strataMuted; elide: Text.ElideRight }
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
            visible: !root.barAudio
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
            visible: !root.barAudio && Audio.microphone !== null
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
        visible: !root.barAudio && (Audio.outputs.length > 1 || Audio.inputs.length > 1)
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
        SectionMark { text: "STATION"; size: 9; tone: Theme.strataMuted }
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
        SectionMark { text: "POWER"; size: 9; tone: Theme.strataMuted }
        GridLayout {
            Layout.fillWidth: true
            columns: Math.max(1, Controls.data.profiles.length); columnSpacing: 8
            uniformCellWidths: true
            Repeater {
                model: Controls.data.profiles
                StrataButton {
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
                        cut: Theme.strataCut / 2
                        fill: profile.on ? Qt.alpha(Theme.strataAccent, .06) : Qt.alpha(Theme.strataFoundation, .6)
                        stroke: profile.visualFocus ? Theme.strataAccent : profile.on ? Qt.alpha(Theme.strataAccent, .45) : profile.hovered ? Qt.alpha(Theme.strataAccent, .35) : Qt.alpha(Theme.strataAccent, .14)
                        strokeWidth: profile.visualFocus ? 2 : 1
                        line: profile.on; lineColor: Theme.strataAccent; lineFraction: .5
                    }
                    contentItem: Text { text: profile.text; textFormat: Text.PlainText; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; font.family: Theme.labelFont; font.pixelSize: Math.round(16 * Theme.fontScale); color: profile.on ? Theme.strataAccent : Theme.strataText; elide: Text.ElideRight }
                }
            }
        }
    }
    RowLayout {
        Layout.fillWidth: true
        visible: (UPower.displayDevice?.isPresent ?? false) || (!Config.saved.canopyEnabled && !root.barPower)
        opacity: root.beat(10)
        StatusPill {
            visible: UPower.displayDevice?.isPresent ?? false
            text: Math.round((UPower.displayDevice?.percentage ?? 0) * 100) + "% · " + (UPower.onBattery ? "battery" : "plugged in")
            tone: UPower.onBattery && (UPower.displayDevice?.percentage ?? 1) < .2 ? Theme.amber : Theme.strataAccent
        }
        Item { Layout.fillWidth: true }
        StrataButton {
            visible: !Config.saved.canopyEnabled && !root.barPower
            text: "Power & session"
            onClicked: ShellState.toggle("power")
        }
    }
}
