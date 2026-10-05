import QtQuick
import "../services"

// A slow sine between two values, stepped at Motion.ambientFps instead of the
// display refresh rate. An OpacityAnimator loop on an always-mapped surface
// commits a frame every vsync for the life of the shell; this commits about a
// dozen, and none while the user is away. `value` is the only output.
QtObject {
    id: root
    property bool running: true
    property real from: 0
    property real to: 1
    // Milliseconds for the rise; the fall may differ, as Core's breath does.
    property int rise: 2000
    property int fall: rise
    property real value: from
    property real phase: 0
    property double stamp: 0
    function restart() { phase = 0; stamp = Date.now(); value = from; }
    onRunningChanged: if (running) stamp = Date.now()
    property Timer clock: Timer {
        interval: Math.round(1000 / Math.max(1, Motion.ambientFps))
        repeat: true
        running: root.running
        onTriggered: {
            const now = Date.now(), elapsed = Math.min(250, now - root.stamp);
            root.stamp = now;
            // Advance phase by the fraction of the current half-cycle that passed.
            const half = root.phase < 1 ? Math.max(1, root.rise) : Math.max(1, root.fall);
            root.phase = (root.phase + elapsed / half) % 2;
            const t = root.phase < 1 ? root.phase : 2 - root.phase;
            root.value = root.from + (root.to - root.from) * (0.5 - 0.5 * Math.cos(Math.PI * t));
        }
    }
}
