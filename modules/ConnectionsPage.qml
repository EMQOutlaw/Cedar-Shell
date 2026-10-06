import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../services"
// Wi-Fi, Bluetooth and hotspot in one place. The sections reuse the same
// controls as Canopy, so both surfaces stay in agreement.
ColumnLayout {
    id: root
    property bool active: false
    property string highlightKey: ""
    readonly property var joined: (Network.data.networks || []).find(n => n.active) || null
    readonly property int bluetoothConnected: BluetoothService.devices.filter(d => d.connected).length
    readonly property var tiles: [
        {key:"wifi", title:"Wi-Fi",
         on:Network.data.available && Network.data.enabled && Network.data.hardware,
         state:!Network.data.available ? "Unavailable" : !Network.data.hardware ? "No adapter" : !Network.data.enabled ? "Off" : joined ? joined.ssid : Network.state === "connecting" ? "Connecting…" : "On · not joined",
         detail:Network.data.available ? Network.statusDescription : "NetworkManager is not reachable."},
        {key:"bluetooth", title:"Bluetooth",
         on:BluetoothService.adapter?.enabled === true,
         state:!BluetoothService.adapter ? "No adapter" : !BluetoothService.adapter.enabled ? "Off" : bluetoothConnected ? bluetoothConnected + " connected" : "On",
         detail:!BluetoothService.adapter ? "Bluetooth is not available here" : BluetoothService.devices.filter(d => d.connected).map(d => d.name || d.address).join(", ") || (BluetoothService.adapter.enabled ? "No devices connected" : "Turn on to find devices")},
        {key:"hotspot", title:"Hotspot",
         on:Network.hotspot !== null,
         state:Network.hotspot ? "Sharing" : "Off",
         detail:Network.hotspot ? "“" + (Network.hotspot.ssid || Network.hotspot.name) + "”" : "Share this connection over Wi-Fi"}
    ]
    spacing: 16
    GridLayout {
        Layout.fillWidth: true; columns: root.width < 560 ? 1 : 3; columnSpacing: 12; rowSpacing: 12
        Repeater {
            model: root.tiles
            Readout { required property var modelData; label: modelData.title; value: modelData.state; detail: modelData.detail; lit: modelData.on }
        }
    }
    SettingsSection {
        objectName: "wifi"
        heading: "Wi-Fi & VPN"; caption: "Networks in range, saved connections and VPN profiles."
        ConnectionSettings { Layout.fillWidth: true; active: root.active; showTitle: false; showHotspot: false }
    }
    SettingsSection {
        objectName: "bluetooth"
        heading: "Bluetooth"; caption: "Pair, connect and trust nearby devices. Scanning stops when you leave."
        BluetoothSettings { Layout.fillWidth: true; active: root.active; showTitle: false }
    }
    SettingsSection {
        objectName: "hotspot"
        heading: "Hotspot"; caption: "Let a phone or laptop use this computer’s connection."
        HotspotSettings { Layout.fillWidth: true }
    }
}
