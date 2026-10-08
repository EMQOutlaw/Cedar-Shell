pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import ".."

// One CAVA feed for every audio-reactive surface. Consumers hold a demand
// while they are shown; the process runs only while the demand is above
// zero, Reduced Motion is off and this is not a test. `levels` is the real
// 24-band spectrum (0 … 1) at CAVA's 30 frames per second; `energy` its mean,
// so a consumer can rest its strokes on silence. Nothing is synthesised:
// without CAVA, `available` is false and the consumers say so.
Singleton {
    id: root
    property int demand: 0
    property var levels: []
    property real energy: 0
    property bool available: true
    property string error: ""
    readonly property bool running: worker.running
    function hold() { demand++; }
    function release() { demand = Math.max(0, demand - 1); }
    Process {
        id: worker
        command: ["python3", Quickshell.shellPath("scripts/spectrum.py")]
        running: root.demand > 0 && !Theme.reducedMotion && !Config.testMode
        stdout: SplitParser {
            onRead: data => {
                const values = data.trim().split(";").filter(s => s !== "").map(Number);
                if (values.length === 24 && values.every(v => Number.isFinite(v))) {
                    const scaled = values.map(v => Math.max(0, Math.min(1, v / 100)));
                    root.levels = scaled;
                    root.energy = scaled.reduce((a, b) => a + b, 0) / 24;
                }
            }
        }
        stderr: StdioCollector { onStreamFinished: if (text.trim()) { root.error = text.trim().slice(0, 160); root.available = !/unavailable/i.test(text); } }
        onExited: (code, status) => { if (code !== 0 && root.demand > 0) root.available = false; root.levels = []; root.energy = 0; }
    }
}
