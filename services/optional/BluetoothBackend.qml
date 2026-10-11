import QtQml
import Quickshell.Bluetooth
// Loaded by URL so a Quickshell build without Bluetooth can still start CEDAR.
QtObject {
    readonly property var adapters: Bluetooth.adapters.values
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var devices: Bluetooth.devices.values
    // rfkill's soft block: BlueZ refuses to power an adapter while it holds.
    function blocked(adapter) { return !!adapter && adapter.state === BluetoothAdapterState.Blocked; }
}
