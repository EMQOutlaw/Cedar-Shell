import QtQuick
import Quickshell.Io
import "../omacale.bar" as Omacale

// Loaded only for the reviewed Omacale adapter, before switching the bar.
// Preserve original bindings, not just values. Never access the locker.
Item {
    id: root
    property var shell: null
    property bool pausing: true
    Component.onDestruction: pausing = false
    readonly property var handovers: [Omacale.NotifHandover, Omacale.OsdHandover]
    function ready(): bool {
        return pausing && pauses.count === 2 && handovers.every(h => !h.busy
            && !h.startCheck.running && !h.lockedRetry.running && !h.settle.running
            && !h.watchers.active && !h.updates.enabled);
    }
    Repeater {
        id: pauses
        model: root.handovers
        delegate: Item {
            required property var modelData
            Binding { target: modelData.startCheck; property: "running"; when: root.pausing; value: false; restoreMode: Binding.RestoreBindingOrValue }
            Binding { target: modelData.lockedRetry; property: "running"; when: root.pausing; value: false; restoreMode: Binding.RestoreBindingOrValue }
            Binding { target: modelData.settle; property: "running"; when: root.pausing; value: false; restoreMode: Binding.RestoreBindingOrValue }
            Binding { target: modelData.watchers; property: "active"; when: root.pausing; value: false; restoreMode: Binding.RestoreBindingOrValue }
            Binding { target: modelData.updates; property: "enabled"; when: root.pausing; value: false; restoreMode: Binding.RestoreBindingOrValue }
        }
    }
    IpcHandler {
        target: "cedarOmacaleGuard"
        function ready(): bool { return root.ready(); }
    }
}
