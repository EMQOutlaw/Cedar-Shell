import QtQuick
import Quickshell
import Quickshell.Io
import ".."

// Trailwatch on Omarchy: publish the lock surface's state for the bridge that
// serves Omarchy's lock IPC. Written on every change and as a heartbeat, so a
// shell that died reads as stale (not ready), never as unlocked.
Scope {
    id: root
    readonly property bool ready: ShellState.nativeLockReady
    readonly property bool locked: ShellState.locked
    readonly property bool secure: ShellState.lockSecure
    readonly property bool fingerprint: ShellState.fingerprint !== ""
    property string event: "started"
    function write() {
        store.setText(JSON.stringify({ready: ready, locked: locked, secure: secure, fingerprint: fingerprint, event: event, updated: Date.now()}) + "\n");
    }
    onReadyChanged: { event = ready ? "ready" : "unavailable"; write(); }
    onLockedChanged: { event = locked ? "lock-requested" : "unlocked"; write(); }
    onSecureChanged: { event = "secure=" + secure; write(); }
    onFingerprintChanged: write()
    Component.onCompleted: write()
    Timer { interval: 5000; running: true; repeat: true; onTriggered: root.write() }
    FileView { id: store; path: Config.lockStatePath; atomicWrites: true; printErrors: false }
}
