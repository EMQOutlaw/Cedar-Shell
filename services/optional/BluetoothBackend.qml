import QtQml
import Quickshell.Bluetooth
// Loaded by URL so a Quickshell build without Bluetooth can still start CEDAR.
QtObject {
    readonly property var adapters: Bluetooth.adapters.values
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var devices: Bluetooth.devices.values
}
