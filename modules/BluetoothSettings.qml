import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."
import "../components"
import "../services"
ColumnLayout {
    id: root
    property bool active:visible
    onActiveChanged:if(!active){BluetoothService.cancelPairing();BluetoothService.stopScan();}
    Component.onDestruction:{BluetoothService.cancelPairing();BluetoothService.stopScan();}
    property string confirmForget: ""
    property bool showTitle: true
    onVisibleChanged: if (!visible) { code.text=""; BluetoothService.cancelPairing(); BluetoothService.stopScan(); }
    spacing: 12
    GlowText { visible: root.showTitle; text: "BLUETOOTH / NEARBY"; color: Theme.teal; font.pixelSize: 19 }
    Repeater {
        model: BluetoothService.adapters
        StationToggle {
            required property var modelData
            Layout.fillWidth: true; label: modelData.name; checked: modelData.enabled
            description: modelData.adapterId; busy: BluetoothService.busy
            onToggled: value => modelData.enabled=value
        }
    }
    GlowText { visible: BluetoothService.adapters.length===0; text: "No Bluetooth adapter available."; color: Theme.muted }
    RowLayout {
        StationButton { text: BluetoothService.adapter?.discovering ? "Stop scanning" : "Scan for 30 seconds"; enabled: (BluetoothService.adapter?.enabled ?? false) && !BluetoothService.busy; onClicked: BluetoothService.scan(!BluetoothService.adapter.discovering) }
        GlowText { visible: BluetoothService.busy; text: "Working…"; color: Theme.muted }
    }
    GlowText { visible: BluetoothService.error!==""; text: BluetoothService.error; color: Theme.amber; Layout.fillWidth: true; wrapMode: Text.WordWrap }
    ColumnLayout {
        visible: BluetoothService.prompt!==""; Layout.fillWidth: true
        GlowText { text: BluetoothService.message; color: Theme.green; Layout.fillWidth: true; wrapMode: Text.WordWrap }
        StationField { id: code; visible: ["pin","passkey"].includes(BluetoothService.prompt); Layout.fillWidth: true; placeholderText: "Device code"; echoMode: TextInput.Password }
        RowLayout {
            StationButton { visible: BluetoothService.prompt!=="display"; text: "Confirm pairing"; onClicked: { BluetoothService.reply(true,code.text); code.text=""; } }
            StationButton { visible: BluetoothService.prompt!=="display"; text: "Reject"; onClicked: { BluetoothService.reply(false,""); code.text=""; } }
        }
    }
    Repeater {
        model: BluetoothService.devices
        ColumnLayout {
            required property var modelData
            Layout.fillWidth: true
            readonly property bool working: BluetoothService.busy && BluetoothService.activePath === modelData.dbusPath
            // The state is what BlueZ reports, or the action in flight for this device; never an optimistic "connected".
            readonly property string state: working ? ({ connect: "Connecting…", disconnect: "Disconnecting…", pair: "Pairing…", trust: "Updating…", forget: "Removing…" })[BluetoothService.activeAction] || "Working…" : modelData.pairing ? "Pairing…" : modelData.connected ? "Connected" : modelData.paired ? "Paired" : "Available"
            RowLayout {
                Layout.fillWidth: true; spacing: 10
                Rectangle { width: 8; height: 8; radius: 4; color: modelData.connected ? Theme.green : working || modelData.pairing ? Theme.teal : Theme.muted }
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 1
                    GlowText { text: modelData.name || modelData.address; Layout.fillWidth: true; elide: Text.ElideRight; color: modelData.connected ? Theme.green : Theme.text }
                    GlowText { text: modelData.address + (modelData.trusted ? " · trusted" : "") + (modelData.icon ? " · " + modelData.icon.replace(/-/g, " ") : ""); color: Theme.muted; font.pixelSize: 10; Layout.fillWidth: true; elide: Text.ElideRight }
                }
                StatusPill { visible: modelData.batteryAvailable; text: Math.round(modelData.battery * 100) + "%"; tone: modelData.battery < .2 ? Theme.amber : Theme.teal }
                StatusPill { text: state; tone: modelData.connected ? Theme.green : working || modelData.pairing ? Theme.teal : Theme.muted }
                StationButton { text: working ? "Working…" : modelData.connected ? "Disconnect" : modelData.paired ? "Connect" : "Pair"; enabled: !BluetoothService.busy && !modelData.pairing; onClicked: BluetoothService.run(modelData.connected ? "disconnect" : modelData.paired ? "connect" : "pair",modelData.dbusPath) }
            }
            RowLayout {
                visible: modelData.paired
                StationButton { text: modelData.trusted ? "Trusted" : "Trust"; checked: modelData.trusted; enabled: !BluetoothService.busy; onClicked: BluetoothService.run("trust",modelData.dbusPath,!modelData.trusted) }
                StationButton { text: "Forget"; enabled: !BluetoothService.busy; onClicked: root.confirmForget=modelData.dbusPath }
            }
            RowLayout {
                visible: root.confirmForget===modelData.dbusPath
                StationButton { text: "Confirm removal"; accent: Theme.amber; onClicked: { BluetoothService.run("forget",modelData.dbusPath); root.confirmForget=""; } }
                StationButton { text: "Cancel"; onClicked: root.confirmForget="" }
            }
        }
    }
}
