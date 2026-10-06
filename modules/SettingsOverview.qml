import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower
import ".."
import "../components"
import "../services"
// The desktop at a glance. Read-only: every destination lives in the sidebar.
ColumnLayout {
    id: root
    spacing: 16
    readonly property var battery: UPower.displayDevice
    readonly property var services: SettingsInfo.data.services || []
    readonly property int failing: services.filter(s => s.status === "Failed").length
    readonly property int healthy: services.filter(s => s.status === "Healthy").length
    readonly property var monitors: (DesktopSettings.data.monitors || []).filter(m => !m.disabled)
    readonly property var joined: (Network.data.networks || []).find(n => n.active) || null
    readonly property int btConnected: BluetoothService.devices.filter(d => d.connected).length
    SystemClock { id: clock; precision: SystemClock.Minutes }
    function percent(v) { return v < 0 ? "—" : Math.round(v * 100) + "%"; }

    // Station identity
    Rectangle {
        Layout.fillWidth: true; implicitHeight: hero.implicitHeight + 40; radius: Theme.cardRadius
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Qt.alpha(Theme.green, .08) }
            GradientStop { position: 1; color: Qt.alpha(Theme.teal, .02) }
        }
        border.color: Qt.alpha(Theme.green, .22)
        GridLayout {
            id: hero
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 20
            columns: root.width < 640 ? 1 : 2; columnSpacing: 24; rowSpacing: 12
            ColumnLayout {
                Layout.fillWidth: true; spacing: 4
                GlowText { text: "STATION"; color: Theme.teal; font.pixelSize: 10; font.letterSpacing: 1.8 }
                GlowText { text: SettingsInfo.data.hostname || "This computer"; font.family: Theme.labelFont; font.pixelSize: Math.round(36 * Theme.fontScale); color: Theme.green; Layout.fillWidth: true; elide: Text.ElideRight }
                GlowText { text: [SettingsInfo.data.os, SettingsInfo.data.kernel].filter(Boolean).join("  ·  ") || "System details unavailable"; color: Theme.muted; font.pixelSize: Theme.small; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                Flow {
                    Layout.fillWidth: true; Layout.topMargin: 6; spacing: 8
                    StatusPill { text: "Up " + SystemStats.uptime; tone: Theme.teal }
                    StatusPill { text: "CEDAR " + (SettingsInfo.data.version || "version unknown"); tone: Theme.teal }
                    StatusPill { visible: root.services.length > 0; text: root.failing ? root.failing + " service" + (root.failing === 1 ? "" : "s") + " failing" : "Services healthy"; tone: root.failing ? Theme.amber : Theme.green }
                }
            }
            ColumnLayout {
                spacing: 0
                GlowText { Layout.alignment: root.width < 640 ? Qt.AlignLeft : Qt.AlignRight; text: Config.formatTime(clock.date); font.family: Theme.labelFont; font.pixelSize: Math.round(44 * Theme.fontScale); color: Theme.text }
                GlowText { Layout.alignment: root.width < 640 ? Qt.AlignLeft : Qt.AlignRight; text: Config.formatDate(clock.date); color: Theme.muted; font.pixelSize: Theme.small }
            }
        }
    }

    // Live telemetry
    SettingsSection {
        heading: "Right now"; caption: "Measured on this computer. A dash means the reading is unavailable, not zero."
        GridLayout {
            Layout.fillWidth: true; columns: root.width < 640 ? 2 : 4; columnSpacing: 8; rowSpacing: 8
            Repeater {
                model: [
                    {label:"CPU", value:SystemStats.cpu, text:root.percent(SystemStats.cpu), accent:Theme.green},
                    {label:"Memory", value:SystemStats.ram, text:root.percent(SystemStats.ram), accent:Theme.teal},
                    {label:"Storage", value:SystemStats.disk, text:root.percent(SystemStats.disk), accent:SystemStats.disk * 100 >= Config.saved.coreDiskLimit ? Theme.amber : Theme.teal},
                    {label:"Temperature", value:SystemStats.temperature < 0 ? -1 : SystemStats.temperature / Math.max(1, Config.saved.coreTemperatureLimit), text:SystemStats.temperature < 0 ? "—" : Math.round(SystemStats.temperature) + "°C", accent:SystemStats.temperature >= Config.saved.coreTemperatureLimit ? Theme.ember : Theme.amber}
                ]
                ColumnLayout {
                    required property var modelData
                    Layout.fillWidth: true; Layout.preferredWidth: 120; spacing: 0
                    ArcGauge {
                        Layout.alignment: Qt.AlignHCenter; implicitWidth: 112; implicitHeight: 112
                        value: Math.max(0, Math.min(1, modelData.value)); valueText: modelData.text; accent: modelData.accent
                        active: root.visible && modelData.value >= 0
                    }
                    GlowText { Layout.alignment: Qt.AlignHCenter; text: modelData.label.toUpperCase(); color: Theme.muted; font.pixelSize: 9; font.letterSpacing: 1.6 }
                }
            }
        }
    }

    // State of each area
    GridLayout {
        Layout.fillWidth: true; columns: root.width < 640 ? 1 : root.width < 900 ? 2 : 3; columnSpacing: 12; rowSpacing: 12
        Readout {
            label: "Displays"; lit: root.monitors.length > 0
            value: root.monitors.length === 1 ? "1 display" : root.monitors.length + " displays"
            detail: root.monitors.map(m => m.name + "  " + m.width + "×" + m.height + " @ " + Math.round(m.refreshRate) + " Hz").join("\n") || "Display information unavailable"
        }
        Readout {
            label: "Network"; lit: Network.state === "connected"
            value: !Network.data.available ? "Unavailable" : Network.state === "connected" ? Network.label : Network.state === "connecting" ? "Connecting…" : "Offline"
            detail: Network.data.available ? Network.statusDescription : "NetworkManager is not reachable."
        }
        Readout {
            label: "Bluetooth"; lit: BluetoothService.adapter?.enabled === true
            value: !BluetoothService.adapter ? "No adapter" : !BluetoothService.adapter.enabled ? "Off" : root.btConnected ? root.btConnected + " connected" : "On"
            detail: BluetoothService.devices.filter(d => d.connected).map(d => d.name || d.address).join(", ")
        }
        Readout {
            label: "Sound"; lit: !!Audio.audio && !Audio.muted
            value: !Audio.audio ? "No output" : Audio.muted ? "Muted" : Math.round(Audio.volume * 100) + "%"
            detail: Audio.sink?.description || ""
        }
        Readout {
            label: "Power"; lit: Controls.data.profile !== "" || (root.battery?.isPresent ?? false)
            tone: (root.battery?.isPresent ?? false) && UPower.onBattery && root.battery.percentage < .2 ? Theme.amber : Theme.green
            value: (root.battery?.isPresent ?? false) ? Math.round(root.battery.percentage * 100) + "% · " + (UPower.onBattery ? "battery" : "plugged in") : (Controls.data.profile ? Controls.data.profile.replace("-", " ") : "Profiles unavailable")
            detail: (root.battery?.isPresent ?? false) && Controls.data.profile ? "Profile: " + Controls.data.profile.replace("-", " ") : ""
        }
        Readout {
            label: "Attention"; lit: Config.saved.notificationsEnabled && !Config.saved.doNotDisturb
            tone: Theme.green
            value: !Config.saved.notificationsEnabled ? "Popups off" : Config.saved.doNotDisturb ? "Do Not Disturb" : "Popups on"
            detail: NoticeStore.history.length + " in notification history"
        }
        Readout {
            label: "Look"; lit: true; tone: Theme.teal
            value: SettingsInfo.data.theme || "CEDAR"
            detail: ({cedar:"CEDAR", floating:"Floating", minimal:"Full Width", islands:"Islands", center:"Center", split:"Split"})[Config.barStyle] + " bar  ·  " + (Config.saved.reducedMotion ? "Reduced Motion" : "Ambient " + Math.round(Config.saved.ambientIntensity * 100) + "%")
        }
        Readout {
            label: "Privacy"; lit: Config.localOnly; tone: Theme.green
            value: Config.localOnly ? "Local only" : "External allowed"
            detail: [Config.saved.weatherEnabled && !Config.localOnly ? "weather on" : "", Config.saved.clipboardHistory ? "clipboard history on" : "", Config.saved.forestTrails ? "Trails on" : ""].filter(Boolean).join(" · ") || "No history or external requests"
        }
        Readout {
            label: "Shortcuts"; lit: (DesktopSettings.data.bindings || []).length > 0; tone: Theme.teal
            value: (DesktopSettings.data.bindings || []).length + " active"
            detail: (DesktopSettings.data.owned?.bindings || []).length + " added in CEDAR"
        }
    }
}
