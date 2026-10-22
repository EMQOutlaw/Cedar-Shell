import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower
import ".."
import "../components"
import "../services"

// The Understory: everything that lives close to the ground, in one rail that
// grows from the bar's left end. An instrument column on the screen edge
// opens CEDAR's own surfaces; beside it the hour, the session, the links
// (CONNECT), the levels, what is on the air, the station's stance and the
// power profile. Every reading is the service's own, the same services the
// Quick Controls drop and the Core pill read; absent hardware is hidden.
// Nothing here has a second owner: tiles call the same toggles as the drop.
Item {
    id: root
    property bool active: false
    property string outputName: ""
    readonly property bool nerd: Theme.availableFonts.includes("JetBrainsMono Nerd Font")
    readonly property var player: Media.player
    readonly property var battery: UPower.displayDevice
    readonly property string person: {
        const name = Quickshell.env("USER") || "";
        return name ? name.charAt(0).toUpperCase() + name.slice(1) : "";
    }
    readonly property string daypart: {
        const h = clock.date.getHours();
        return h < 5 ? "Good night" : h < 12 ? "Good morning" : h < 17 ? "Good afternoon" : h < 22 ? "Good evening" : "Good night";
    }
    function glyph(icon, fallback) { return nerd ? icon : fallback; }
    function beat(order, span = .4) { return Understory.ease(.05 * order, span); }
    onActiveChanged: if (active) { Controls.refresh(); Brightness.drain(); }
    SystemClock { id: clock; precision: SystemClock.Minutes }

    // A rail button: an instrument on the screen edge. Lit when its surface is open.
    component RailButton: StrataButton {
        property real order: 0
        implicitWidth: 36; implicitHeight: 36; iconOnly: true
        opacity: root.beat(order, .3)
    }
    // A tile: glyph and name on the first line, the state dot at the far
    // right, the reading on the second line. Lit along its foot when on.
    component Tile: StrataButton {
        id: tile
        property string mark: ""
        property string label: ""
        property string value: ""
        property bool on: false
        property real order: 0
        readonly property real sweep: root.beat(order)
        Layout.fillWidth: true; Layout.preferredWidth: 1
        implicitHeight: 58
        padding: 11
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
    // A level row: the icon is the mute control, the label names it, the
    // slider is the reading and the number confirms it.
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
        implicitHeight: 34
        opacity: sweep
        transform: Translate { x: 12 * (1 - level.sweep) }
        RowLayout {
            anchors.fill: parent; spacing: 10
            StrataButton {
                implicitWidth: 30; implicitHeight: 30; iconOnly: true
                enabled: level.canMute
                text: level.icon
                hint: level.canMute ? (level.muted ? "Unmute " : "Mute ") + level.label.toLowerCase() : level.label
                accent: level.muted ? Theme.amber : Theme.strataAccent
                checked: level.muted
                onClicked: level.toggled()
            }
            Text {
                Layout.preferredWidth: 84
                text: level.label; textFormat: Text.PlainText
                font.family: Theme.labelFont; font.pixelSize: Math.round(14 * Theme.fontScale)
                color: level.muted ? Theme.amber : Theme.strataText
                elide: Text.ElideRight
            }
            StationSlider {
                objectName: level.sliderName
                Accessible.name: level.label
                Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.minimumWidth: 60
                value: level.value
                onMoved: level.moved(value)
                onCommitted: v => level.committed(v)
            }
            Text {
                Layout.preferredWidth: 44; Layout.minimumWidth: 44; horizontalAlignment: Text.AlignRight
                text: level.muted ? "MUTED" : Math.round(level.value * 100 * level.sweep) + "%"
                textFormat: Text.PlainText
                font.family: Theme.dataFont; font.pixelSize: level.muted ? 9 : Theme.small; font.letterSpacing: level.muted ? 1.2 : 0
                color: level.muted ? Theme.amber : Theme.strataAccent
            }
        }
    }
    // The spaced small heading every section wears.
    component Mark: SectionMark { size: 9; tone: Theme.strataMuted }

    // ---- the instrument column ---------------------------------------------
    Column {
        id: instruments
        x: 10; y: 14; spacing: 6; width: 40
        // CEDAR's mark opens Field Station, as it does on the bar.
        StrataButton {
            objectName: "understoryStation"
            width: 40; height: 40; iconOnly: true
            hint: "Field Station"
            background: Item {}
            contentItem: Item {
                CedarHeartwood { anchors.centerIn: parent; size: 28; active: root.active && Config.saved.barHeartwood; mode: Gaming.active ? "gaming" : Focus.active ? "focus" : "idle" }
            }
            onClicked: { Understory.close(); if (Config.saved.canopyEnabled) Canopy.open("station", root.outputName); else ShellState.open("hud"); }
        }
        Item { width: 1; height: 6 }
        RailButton { order: 0; text: root.glyph("󰂚", "S"); hint: "Signals"; visible: CoreService.enabled; onClicked: { Understory.close(); CoreService.expand(); } }
        RailButton { order: 1; text: root.glyph("󰒃", "⛨"); hint: Shield.ready ? "Shield · " + Shield.headline : "Shield"; accent: Shield.posture === "protected" ? Theme.green : Theme.strataAccent; checked: Shield.posture === "protected"; onClicked: { Understory.close(); Shield.openApp(); } }
        RailButton { order: 2; text: root.glyph("󰓅", "H"); hint: "Station · health and diagnostics"; onClicked: { Understory.close(); Station.openApp(); } }
        RailButton { order: 3; text: root.glyph("󰙅", "P"); hint: Profiles.current ? "Profiles · " + Profiles.currentLabel : "Profiles"; checked: !!Profiles.current; onClicked: { Understory.close(); Profiles.openApp(); } }
        RailButton { order: 4; text: root.glyph("󰔛", "F"); hint: Focus.active ? "Focus · " + Focus.summary : "Focus"; checked: Focus.active; onClicked: { Understory.close(); Focus.openApp(); } }
        RailButton { order: 5; text: root.glyph("󱞁", "N"); hint: "Field Notes"; onClicked: { Understory.close(); FieldNotes.toggle(); } }
    }
    Column {
        x: 10; spacing: 6; width: 40
        anchors.bottom: parent.bottom; anchors.bottomMargin: 22
        RailButton { order: 6; text: root.glyph("󰌌", "K"); hint: "Keymap · the searchable active keymap"; onClicked: { Understory.close(); if (!Config.testMode) Quickshell.execDetached(["qs", "--no-duplicate", "-p", Quickshell.shellPath("keymap.qml")]); } }
        RailButton { order: 7; text: root.glyph("󰒓", "⚙"); hint: "Settings"; onClicked: { Understory.close(); ShellState.toggle("settings"); } }
    }
    Rectangle { x: 58; y: 14; width: 1; height: parent.height - 36; color: Qt.alpha(Theme.border, .5) }

    // ---- content ------------------------------------------------------------
    Flickable {
        id: scroll
        x: 72; y: 16
        width: parent.width - x - 24
        height: parent.height - 32 - foot.height - 20
        contentHeight: content.implicitHeight
        clip: true
        interactive: contentHeight > height + 1
        boundsBehavior: Flickable.StopAtBounds
        ColumnLayout {
            id: content
            width: scroll.width
            spacing: 16

            GlowText {
                visible: Controls.error !== "" || Awake.error !== ""
                text: Controls.error || Awake.error
                Layout.fillWidth: true; wrapMode: Text.WordWrap
                color: Theme.amber; font.pixelSize: Theme.small
            }

            // Header: the greeting, the hour, the day and the session.
            ColumnLayout {
                Layout.fillWidth: true; spacing: 2
                opacity: root.beat(0)
                Mark { text: (root.daypart + (root.person ? ", " + root.person : "")).toUpperCase() }
                RowLayout {
                    Layout.fillWidth: true; spacing: 6
                    Text { objectName: "understoryClock"; text: Config.clock24 ? Qt.formatDateTime(clock.date, "HH:mm") : Qt.formatDateTime(clock.date, "h:mm"); textFormat: Text.PlainText; color: Theme.strataText; font.family: Theme.labelFont; font.pixelSize: 36; font.weight: Font.DemiBold }
                    Text { visible: !Config.clock24; text: Qt.formatDateTime(clock.date, "AP"); textFormat: Text.PlainText; color: Theme.strataMuted; font.family: Theme.dataFont; font.pixelSize: 11; Layout.alignment: Qt.AlignBottom; Layout.bottomMargin: 8 }
                    Item { Layout.fillWidth: true; Layout.minimumWidth: 4 }
                    // Lock and suspend act at once; log out and power off arm the
                    // session drop, which asks before anything ends.
                    StrataButton { Layout.preferredWidth: 30; Layout.preferredHeight: 30; iconOnly: true; text: root.glyph("󰌾", "L"); hint: "Lock · Trailwatch keeps your place"; enabled: !Config.testMode; onClicked: { Understory.close(); ShellState.lock(false); } }
                    StrataButton { Layout.preferredWidth: 30; Layout.preferredHeight: 30; iconOnly: true; text: root.glyph("󰤄", "Z"); hint: "Suspend · lock, then sleep"; enabled: !Config.testMode; onClicked: { Understory.close(); ShellState.lock(true); } }
                    StrataButton { Layout.preferredWidth: 30; Layout.preferredHeight: 30; iconOnly: true; text: root.glyph("󰍃", "⏏"); hint: "Log out · opens Power & session"; onClicked: root.session() }
                    StrataButton { Layout.preferredWidth: 30; Layout.preferredHeight: 30; iconOnly: true; text: root.glyph("󰐥", "⏻"); hint: "Power · opens Power & session"; accent: Theme.ember; onClicked: root.session() }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: Qt.formatDateTime(clock.date, "ddd · MMM d · yyyy").toUpperCase(); textFormat: Text.PlainText; color: Theme.strataMuted; font.family: Theme.dataFont; font.pixelSize: 11; font.letterSpacing: 1.2 }
                    Text {
                        Layout.fillWidth: true; horizontalAlignment: Text.AlignRight; elide: Text.ElideRight
                        visible: root.battery?.isPresent ?? false
                        text: (root.nerd ? (UPower.onBattery ? "󰁹" : "󰂄") + "  " : "") + Math.round((root.battery?.percentage ?? 0) * 100) + "% · " + (UPower.onBattery ? "BATTERY" : "PLUGGED IN")
                        textFormat: Text.PlainText
                        color: UPower.onBattery && (root.battery?.percentage ?? 1) < .2 ? Theme.amber : Theme.strataAccent
                        font.family: Theme.dataFont; font.pixelSize: 10; font.letterSpacing: 1.2
                    }
                }
            }

            // CONNECT: the links and the holds. Real state from NetworkManager,
            // BlueZ, Proton's CLI, the control helper, the notification policy,
            // logind, and the Gaming and Focus transactions.
            ColumnLayout {
                Layout.fillWidth: true; spacing: 8
                Mark { text: "CONNECT"; opacity: root.beat(1) }
                GridLayout {
                    Layout.fillWidth: true; columns: 2; columnSpacing: 8; rowSpacing: 8; uniformCellWidths: true
                    Tile {
                        order: 1
                        mark: root.nerd ? Network.glyph : Network.fallbackGlyph
                        label: Network.kind === "wifi" ? "Wi-Fi" : Network.kind === "wired" ? "Wired" : "Network"
                        value: Network.label
                        on: Network.state === "connected"
                        enabled: Network.data.available && Network.data.hardware && !Network.busy
                        hint: Network.data.hardware ? (Network.data.enabled ? "Wi-Fi on · tap to turn the radio off" : "Wi-Fi off · tap to turn the radio on") : Network.statusDescription
                        onClicked: Network.run({ action: "radio", enabled: !Network.data.enabled })
                    }
                    Tile {
                        order: 1.5
                        visible: BluetoothService.available && BluetoothService.adapter !== null
                        readonly property var connected: BluetoothService.devices.filter(d => d.connected)
                        mark: root.glyph("󰂯", "B")
                        label: "Bluetooth"
                        value: !(BluetoothService.adapter?.enabled ?? false) ? "Off" : connected.length === 0 ? "On · nothing connected" : connected.length === 1 ? (connected[0].name || connected[0].address) : connected.length + " devices connected"
                        on: BluetoothService.adapter?.enabled ?? false
                        enabled: !BluetoothService.busy
                        hint: on ? "Tap to turn Bluetooth off" : "Tap to turn Bluetooth on"
                        onClicked: BluetoothService.setEnabled(BluetoothService.adapter, !BluetoothService.adapter.enabled)
                    }
                    // VPN: Proton when its CLI is here; any other active tunnel is reported, not driven.
                    Tile {
                        order: 2
                        visible: Proton.data.installed || Network.vpnActive
                        mark: root.glyph("󰌾", "V")
                        label: "VPN"
                        value: Proton.working ? Proton.working : Proton.connected ? "Proton · " + (Proton.server || "connected") : Network.vpnActive ? "Tunnel up" : Proton.data.installed ? (Proton.data.signedIn ? "Proton · off" : "Proton · signed out") : "Off"
                        on: Proton.connected || Network.vpnActive
                        enabled: Proton.data.installed && Proton.data.signedIn && !Proton.busy
                        hint: Proton.connected ? "Tap to disconnect Proton VPN" : Proton.data.signedIn ? "Tap to connect to the fastest Proton server" : "Sign in from the Connections drop"
                        onClicked: Proton.connected ? Proton.disconnect() : Proton.connectTo("fastest")
                    }
                    Tile {
                        order: 2.5
                        visible: Controls.data.nightlight !== null
                        mark: root.glyph("󰖔", "N")
                        label: "Night light"; value: Controls.data.nightlight === true ? "On" : "Off"; on: Controls.data.nightlight === true
                        enabled: !Controls.busy
                        onClicked: Controls.run({ action: "nightlight" })
                    }
                    Tile {
                        order: 3
                        mark: Config.saved.doNotDisturb ? root.glyph("󰂛", "Z") : root.glyph("󰂚", "Q")
                        label: "Quiet hours"
                        value: Config.saved.doNotDisturb ? "On · notifications held" : "Off · notifications on"
                        on: Config.saved.doNotDisturb
                        hint: "Do not disturb: hold notifications until you return"
                        onClicked: Config.set("doNotDisturb", !Config.saved.doNotDisturb)
                    }
                    Tile {
                        order: 3.5
                        objectName: "understoryAwake"
                        mark: root.glyph("󰒲", "A")
                        label: "Keep awake"
                        value: Awake.summary
                        on: Awake.held
                        enabled: Awake.available && !Awake.busy
                        hint: Awake.available ? (Awake.held ? "Tap to allow idle lock and sleep again" : "Hold off idle lock and sleep until you tap again") : "Needs systemd-inhibit"
                        onClicked: Awake.toggle()
                    }
                    Tile {
                        order: 4
                        mark: root.glyph("󰊗", "G")
                        label: "Gaming"
                        value: Gaming.busy ? "…" : Gaming.active ? Gaming.activeCount + "/" + Gaming.totalCount + " active" : "Off"
                        on: Gaming.active
                        enabled: !Gaming.busy
                        hint: Gaming.active ? Gaming.summary + (Gaming.detail ? " · " + Gaming.detail : "") : "Super+G · pauses the flair, holds notifications and sleep, performance profile, compositor blur"
                        onClicked: Gaming.toggle()
                    }
                    Tile {
                        order: 4.5
                        mark: root.glyph("󰔛", "F")
                        label: "Focus"
                        value: Focus.busy ? "…" : Focus.active ? (Focus.paused ? "Paused" : Focus.minutes(Focus.remaining) + " left") : "Off"
                        on: Focus.active
                        hint: (Focus.active ? Focus.summary + " · " : "") + "opens CEDAR Focus"
                        onClicked: { Understory.close(); Focus.openApp(); }
                    }
                }
            }

            // LEVELS
            ColumnLayout {
                Layout.fillWidth: true; spacing: 2
                visible: Audio.audio !== null || Brightness.available
                Mark { text: "LEVELS"; opacity: root.beat(5) }
                LevelRow {
                    order: 5
                    label: "Output"; sliderName: "understoryVolume"
                    icon: Audio.muted ? root.glyph("󰝟", "×") : root.glyph("󰕾", "♪")
                    visible: Audio.audio !== null
                    value: Audio.volume; muted: Audio.muted
                    onMoved: value => Audio.setVolume(value)
                    onToggled: Audio.toggleMute()
                }
                LevelRow {
                    order: 5.5
                    label: "Microphone"
                    icon: Audio.microphone?.muted ? root.glyph("󰍭", "×") : root.glyph("󰍬", "M")
                    visible: Audio.microphone !== null
                    value: Audio.microphone?.volume ?? 0; muted: Audio.microphone?.muted ?? false
                    onMoved: value => Audio.setMicrophone(value)
                    onToggled: Audio.toggleMicrophone()
                }
                LevelRow {
                    order: 6
                    label: "Brightness"; canMute: false
                    icon: root.glyph("󰃠", "☼")
                    visible: Brightness.available
                    value: Brightness.value
                    onCommitted: v => Brightness.change(Math.round((v - Brightness.value) * 100))
                }
            }

            // ON THE AIR: the shared MPRIS player, the same one the pill and Field Station follow.
            ColumnLayout {
                Layout.fillWidth: true; spacing: 8
                visible: root.player !== null
                opacity: root.beat(6.5)
                transform: Translate { y: 6 * (1 - root.beat(6.5)) }
                Mark { text: "ON THE AIR" }
                ChamferFrame {
                    Layout.fillWidth: true; implicitHeight: 84
                    cut: Theme.strataCut
                    fill: Qt.alpha(Theme.strataFoundation, .6); stroke: Qt.alpha(Theme.strataAccent, .18)
                    topLine: true; topLineColor: Theme.teal
                    RowLayout {
                        anchors.fill: parent; anchors.margins: 12; spacing: 12
                        ChamferFrame {
                            Layout.preferredWidth: 60; Layout.preferredHeight: 60; cut: 6
                            fill: Qt.alpha(Theme.teal, .18); stroke: Qt.alpha(Theme.teal, .3)
                            clip: true
                            Image {
                                id: art
                                anchors.fill: parent; anchors.margins: 1
                                source: Config.imageSource(root.player?.trackArtUrl || "")
                                sourceSize.width: 80; sourceSize.height: 80
                                fillMode: Image.PreserveAspectCrop; asynchronous: true
                                visible: status === Image.Ready
                            }
                            Text { anchors.centerIn: parent; visible: !art.visible; text: "♫"; color: Theme.teal; font.pixelSize: 22 }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 3
                            Text { Layout.fillWidth: true; text: root.player?.trackTitle || "Nothing playing"; textFormat: Text.PlainText; font.family: Theme.labelFont; font.pixelSize: 16; color: Theme.strataText; elide: Text.ElideRight }
                            Text { Layout.fillWidth: true; text: [root.player?.trackArtist, root.player?.trackAlbum].filter(Boolean).join(" · ") || (root.player?.identity || ""); textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: 10; color: Theme.strataMuted; elide: Text.ElideRight }
                            RowLayout {
                                Layout.fillWidth: true; spacing: 8
                                readonly property bool timed: (root.player?.positionSupported ?? false) && (root.player?.lengthSupported ?? false) && (root.player?.length ?? 0) > 0
                                property real position: 0
                                Timer { interval: 1000; running: root.active && parent.timed; repeat: true; triggeredOnStart: true; onTriggered: parent.position = root.player?.position ?? 0 }
                                visible: timed
                                Text { text: Media.elapsed(parent.position); textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: 10; color: Theme.strataMuted }
                                Rectangle {
                                    Layout.fillWidth: true; height: 2; color: Qt.alpha(Theme.border, .6)
                                    Rectangle { width: parent.width * Math.max(0, Math.min(1, parent.parent.position / Math.max(1, root.player?.length ?? 1))); height: 2; color: Theme.teal }
                                }
                                Text { text: Media.elapsed(root.player?.length); textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: 10; color: Theme.strataMuted }
                            }
                        }
                        Row {
                            spacing: 4
                            StrataButton { width: 28; height: 28; iconOnly: true; text: root.glyph("󰒮", "«"); hint: "Previous track"; enabled: root.player?.canGoPrevious ?? false; onClicked: root.player.previous() }
                            StrataButton { width: 28; height: 28; iconOnly: true; text: root.player?.isPlaying ? root.glyph("󰏤", "‖") : root.glyph("󰐊", "▶"); hint: root.player?.isPlaying ? "Pause" : "Play"; enabled: root.player?.canTogglePlaying ?? false; onClicked: root.player.togglePlaying() }
                            StrataButton { width: 28; height: 28; iconOnly: true; text: root.glyph("󰒭", "»"); hint: "Next track"; enabled: root.player?.canGoNext ?? false; onClicked: root.player.next() }
                        }
                    }
                }
            }

            // STANCE: Desktop Profiles. A tap applies; a tap on the current one leaves it.
            ColumnLayout {
                Layout.fillWidth: true; spacing: 8
                opacity: root.beat(7)
                transform: Translate { y: 6 * (1 - root.beat(7)) }
                Mark { text: "STANCE" + (Profiles.anyBusy ? " · " + Profiles.summary.toUpperCase() : "") }
                GridLayout {
                    Layout.fillWidth: true; columns: 3; columnSpacing: 6; rowSpacing: 6; uniformCellWidths: true
                    Repeater {
                        model: Profiles.definitions
                        StrataButton {
                            id: stance
                            required property var modelData
                            readonly property bool on: Profiles.current === modelData.id
                            Layout.fillWidth: true; Layout.preferredWidth: 1; implicitHeight: 34
                            text: modelData.label
                            checked: on; enabled: !Profiles.anyBusy
                            accent: on ? Profiles.accentOf(modelData.id) : Theme.strataAccent
                            hint: modelData.line + (on ? " · tap to leave" : "")
                            Accessible.name: "Profile " + text + (on ? ", in use" : "")
                            onClicked: Profiles.toggle(modelData.id)
                        }
                    }
                }
            }

            // POWER: the system power profile, one three-way choice.
            ColumnLayout {
                visible: Controls.data.profiles.length > 0
                Layout.fillWidth: true; spacing: 8
                opacity: root.beat(8)
                transform: Translate { y: 6 * (1 - root.beat(8)) }
                Mark { text: "POWER" }
                RowLayout {
                    Layout.fillWidth: true; spacing: 6
                    Repeater {
                        model: Controls.data.profiles
                        StrataButton {
                            id: profile
                            required property string modelData
                            readonly property bool on: Controls.data.profile === modelData
                            Layout.fillWidth: true; implicitHeight: 34
                            checked: on; enabled: !Controls.busy
                            text: ({"power-saver": "Saver", "balanced": "Balanced", "performance": "Performance"})[modelData] || modelData
                            Accessible.name: "Power profile " + text + (on ? ", in use" : "")
                            onClicked: if (!on) Controls.run({ action: "profile", value: modelData })
                        }
                    }
                }
            }
            Item { implicitHeight: 4 }
        }
    }
    // ROOTED: the station's verse, resting in the empty ground at the foot.
    Text {
        id: foot
        x: 72; width: parent.width - 72 - 28
        anchors.bottom: parent.bottom; anchors.bottomMargin: 26
        text: Branding.content.psalm.text + "  ·  " + Branding.content.psalm.reference
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        font.family: Theme.labelFont; font.pixelSize: 12; font.italic: true
        color: Qt.alpha(Theme.strataMuted, .7)
        opacity: root.beat(9, .5)
    }
    function session() {
        Understory.close();
        if (Config.saved.canopyEnabled) Canopy.open("power", root.outputName);
        else ShellState.open("power");
    }
}
