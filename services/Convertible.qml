pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import ".."

// CEDAR's 2-in-1 transition owner (scripts/convertible.py does the work):
// the tablet-mode switch state drives the internal keyboard and touchpad
// through Hyprland's per-device enabled flag — off folded, back the instant
// it unfolds, self-healing against lost switch events. Two guarantees the
// firmware alone did not give: whatever was disabled is restored when the
// watcher exits, and the keyboard is ALWAYS enabled while the session is
// locked (Trailwatch needs it for the password).
Singleton {
    id: root
    property bool detected: false
    property string device: ""
    property bool tabletMode: false
    property string osk: ""
    property string error: ""
    readonly property bool busy: probe.running || watcher.running

    function refresh() {
        if (!Config.testMode && !probe.running)
            probe.running = true;
    }

    Component.onCompleted: refresh()

    Process {
        id: probe
        command: ["python3", Quickshell.shellPath("scripts/convertible.py"), "state"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const row = JSON.parse(text);
                    root.detected = row.detected === true;
                    root.device = row.device || "";
                    root.tabletMode = row.tablet === true;
                    root.osk = row.osk || "";
                    if (row.note) root.error = row.note;
                } catch (_) {
                    root.error = "Convertible detection returned an unreadable response.";
                }
            }
        }
        onExited: (code, status) => {
            // The watcher only runs on real convertibles, and NEVER while
            // locked — the lock screen must always have its keyboard.
            watcher.running = root.detected && !Config.testMode && !ShellState.locked;
            if (ShellState.locked && root.detected)
                forceLaptop.running = true;
        }
    }

    // Locking the session forces laptop posture first — no dead keyboard at
    // the password prompt, whatever mode the lid is folded into.
    property bool locked: ShellState.locked
    onLockedChanged: {
        if (!root.detected || Config.testMode)
            return;
        if (locked) {
            watcher.running = false;
            forceLaptop.running = true;
        } else {
            watcher.running = true;
        }
    }

    Process {
        id: forceLaptop
        command: ["python3", Quickshell.shellPath("scripts/convertible.py"), "laptop"]
        running: false
    }

    // The on-screen keyboard rides the transition: up while folded into a
    // tablet, gone the moment the physical keyboard returns. It never runs
    // while locked (Trailwatch has the physical keyboard force-enabled).
    Process {
        id: osk
        command: root.osk !== "" ? [root.osk] : ["true"]
        running: root.tabletMode && root.osk !== "" && !Config.testMode && !ShellState.locked
    }

    Process {
        id: watcher
        command: ["python3", Quickshell.shellPath("scripts/convertible.py"), "watch"]
        running: false
        stdout: SplitParser {
            onRead: line => {
                try {
                    const row = JSON.parse(line);
                    if (row.kind === "state")
                        root.tabletMode = row.tablet === true;
                    if (row.kind === "error") {
                        root.error = row.error || "Convertible watcher error.";
                        // An unreadable switch means the one-time rules step
                        // is pending — wait for it, never hot-loop a respawn.
                        if (root.error.indexOf("unreadable") !== -1 || root.error.indexOf("cannot open") !== -1)
                            root.rulesPending = true;
                    }
                } catch (_) {}
            }
        }
        onExited: (code, status) => {
            // The script restores devices itself on exit; if it died and the
            // session is unlocked, bring the watcher back after a breath —
            // unless it is waiting on the one-time rules step.
            if (root.detected && !root.rulesPending && !Config.testMode && !ShellState.locked)
                restart.start();
        }
    }
    property bool rulesPending: false
    Timer { id: restart; interval: 2000; onTriggered: watcher.running = true }
    // While the rules step is pending, re-probe occasionally: the user runs
    // the sudo step once and the watcher comes up on its own.
    Timer { interval: 60000; running: root.rulesPending && !Config.testMode; repeat: true
            onTriggered: { root.rulesPending = false; watcher.running = root.detected && !ShellState.locked; } }
}
