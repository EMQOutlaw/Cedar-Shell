import QtQuick
import Quickshell
import Quickshell.Io
import ".."

Scope {
    id: root
    property bool externalLocked: true
    property real updated: 0
    function apply() {
        // A missing/dead supervisor cannot leave unlocked controls exposed.
        ShellState.locked = externalLocked || Date.now() - updated > 5000;
        if (ShellState.locked) ShellState.close();
    }
    FileView {
        path: Quickshell.env("CEDAR_SESSION_STATUS")
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const state = JSON.parse(text());
                root.externalLocked = state.locked !== false;
                root.updated = Number(state.updated) || 0;
            } catch (_) { root.externalLocked = true; }
            root.apply();
        }
        onLoadFailed: { root.externalLocked = true; root.apply(); }
    }
    Timer { interval: 1000; running: true; repeat: true; onTriggered: root.apply() }
    Component.onCompleted: { ShellState.locked = true; Qt.callLater(root.apply); }
}
