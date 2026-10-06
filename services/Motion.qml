pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Wayland
import ".."

// One shell-wide gate for decorative motion. Ambient loops keep their look but
// stop committing frames when nobody is at the keyboard, when Reduced Motion is
// on, or in offscreen tests. Functional transitions do not consult this gate.
Singleton {
    id: root
    // Seconds without input before ambience pauses. Any input resumes it.
    readonly property int restAfter: 120
    readonly property bool resting: idle.isIdle
    readonly property bool active: !Theme.reducedMotion && !resting
    // Frame rate for timer-driven ambient loops. A 1px filament breathing over
    // four seconds reads the same at 12 steps per second as at the display rate.
    readonly property int ambientFps: 12
    IdleMonitor {
        id: idle
        enabled: !Config.testMode
        timeout: root.restAfter
    }
}
