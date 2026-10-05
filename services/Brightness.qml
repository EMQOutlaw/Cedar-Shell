pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import ".."

Singleton {
    id: root
    property real value: 0
    property bool available: false
    property int pending: 0
    property bool showAfter: false
    function change(delta) { pending += delta; showAfter = true; drain(); }
    function show() { showAfter = true; drain(); }
    function drain() {
        if (poll.running) return;
        poll.command = ["python3", Quickshell.shellPath("scripts/telemetry.py"), "brightness", Config.brightnessDevice, String(pending)];
        pending = 0; poll.running = true;
    }
    Process {
        id: poll
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const s = JSON.parse(text); root.available = s.value !== null && s.value !== undefined;
                    if (root.available) root.value = s.value;
                    if (root.showAfter) ShellState.osd("BRIGHTNESS", root.available ? root.value : 0, root.available ? Math.round(root.value*100) + "%" : s.error || "Unavailable");
                } catch (_) { root.available = false; }
            }
        }
        onExited: { if (root.pending !== 0) Qt.callLater(root.drain); else root.showAfter = false; }
    }
    // Poll only while a brightness control is on screen. Key presses and the
    // OSD read on demand through change()/show(); nothing samples a hidden value.
    readonly property bool observed: !ShellState.locked && !Config.testMode && (
        ShellState.panel === "control" ||
        (ShellState.panel === "settings" && ShellState.settingsSection === "power") ||
        (Canopy.shown && Canopy.topic === "quick") ||
        (ShellState.osdOpen && ShellState.osdKind === "BRIGHTNESS"))
    Timer { interval: 10000; running: root.observed; repeat: true; triggeredOnStart: true; onTriggered: root.drain() }
}
