pragma Singleton
import QtQuick
import Quickshell
import ".."

// The Understory: the rail that grows from the bar's left end on one output.
// One surface, routed through ShellState.panel like the Canopy, so opening it
// closes whatever else is showing and vice versa. Its window (modules/
// UnderstoryWindow.qml) lives only while the rail is wanted on a screen.
Singleton {
    id: root
    property string outputName: ""
    readonly property var screen: Quickshell.screens.find(s => s.name === outputName) || null
    readonly property bool shown: !ShellState.locked && ShellState.panel === "understory" && screen !== null
    // Entrance clock shared by the rail's instruments; Reduced Motion and tests snap.
    property real reveal: 1
    function ease(start, span) {
        const t = Math.max(0, Math.min(1, (reveal - start) / span));
        return 1 - Math.pow(1 - t, 3);
    }
    function enter() {
        entrance.stop();
        if (Theme.reducedMotion || Config.testMode) { reveal = 1; return; }
        reveal = 0;
        entrance.start();
    }
    property NumberAnimation entrance: NumberAnimation { target: root; property: "reveal"; from: 0; to: 1; duration: VisualQuality.ms(Theme.entrance) }
    property Connections motionGuard: Connections { target: Theme; function onReducedMotionChanged() { if (Theme.reducedMotion) { root.entrance.stop(); root.reveal = 1; } } }

    function open(output = "") {
        if (ShellState.locked || Config.stage < 3)
            return;
        outputName = output || ShellState.preferredOutput();
        ShellState.panel = "understory";
        ShellState.output = outputName;
    }
    function close() {
        if (ShellState.panel === "understory")
            ShellState.close();
    }
    function toggle(output = "") {
        if (shown && (!output || output === outputName))
            close();
        else
            open(output);
    }
    function status() {
        return { shown: shown, screen: screen ? screen.name : "", reveal: reveal };
    }
}
