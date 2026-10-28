pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import ".."

// Keep awake: one logind inhibitor, held for as long as the user asks and
// released on the next tap, lock, or when the shell exits. The state shown
// is the inhibitor process itself, never an optimistic flag: `held` turns on
// only once systemd-inhibit is running and off once it has gone. CEDAR's own
// idle lock reads `held` the same way it reads Gaming Mode's inhibitor.
// Nothing is remembered across a shell restart: a stale "awake" after a
// crash would be worse than asking again.
Singleton {
    id: root
    readonly property bool available: Capabilities.gaming.systemdInhibit && !Config.testMode
    property bool wanted: false
    readonly property bool held: inhibit.running
    property bool busy: false
    property string error: ""
    property double since: 0
    readonly property string summary: !available ? "systemd-inhibit is not installed"
        : busy ? (wanted ? "Holding off sleep…" : "Letting go…")
        : held ? "On · idle lock and sleep held off" : error ? error : "Off"
    function toggle() { if (held || wanted) release(); else hold(); }
    function hold() {
        if (!available || ShellState.locked || busy) return;
        error = ""; wanted = true; busy = true; verify.restart();
    }
    function release() {
        if (busy && !wanted) return;
        wanted = false; busy = true; verify.restart();
    }
    Process {
        id: inhibit
        running: root.wanted && root.available
        command: ["systemd-inhibit", "--what=idle:sleep", "--who=CEDAR Keep awake", "--why=Keep awake was switched on in the Understory", "--mode=block", "sleep", "infinity"]
        onRunningChanged: {
            if (running) root.since = Date.now();
            else if (root.wanted && !root.busy) { root.wanted = false; root.error = "The inhibitor exited"; }
        }
    }
    // A beat after asking, the process is either there or it is not.
    Timer {
        id: verify; interval: 400
        onTriggered: {
            root.busy = false;
            if (root.wanted && !inhibit.running) { root.wanted = false; root.error = "systemd-inhibit did not start"; }
            else if (!root.wanted && inhibit.running) root.error = "The inhibitor is still running";
        }
    }
    Connections { target: ShellState; function onLockedChanged() { if (ShellState.locked && root.wanted) root.release(); } }
}
