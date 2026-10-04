pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import ".."

Singleton {
    id: root
    property real cpu: -1
    property real ram: -1
    property real disk: -1
    property real temperature: -1
    property string memoryLabel: "Waiting for memory"
    property string uptime: "…"
    property real networkRate: 0
    property real previousBytes: -1
    property double previousTime: 0
    property real previousTotal: 0
    property real previousIdle: 0
    property bool available: false
    Process {
        id: stats
        command: ["python3", Quickshell.shellPath("scripts/telemetry.py"), "stats", Config.diskPath]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const s = JSON.parse(text);
                    if (s.error) throw new Error(s.error);
                    const delta = s.total - root.previousTotal;
                    if (root.previousTotal > 0 && delta > 0) root.cpu = Math.max(0, Math.min(1, 1-(s.idle-root.previousIdle)/delta));
                    root.previousTotal = s.total; root.previousIdle = s.idle;
                    const sampleTime=Date.now();
                    root.networkRate=root.previousTime && root.previousBytes>=0 && s.netBytes>=root.previousBytes ? (s.netBytes-root.previousBytes)*1000/(sampleTime-root.previousTime):0;
                    root.previousBytes=s.netBytes;root.previousTime=sampleTime;
                    root.ram = s.ram; root.disk = s.disk;
                    root.memoryLabel = s.ramUsed.toFixed(1) + " / " + s.ramTotal.toFixed(1) + " GiB";
                    root.uptime = Math.floor(s.uptime/86400) + "d " + Math.floor(s.uptime/3600)%24 + "h " + Math.floor(s.uptime/60)%60 + "m";
                    root.available = true;
                } catch (_) { root.available = false; root.cpu = -1; root.ram = -1; root.disk = -1; }
            }
        }
    }
    Process {
        id: temps
        command: ["python3", Quickshell.shellPath("scripts/telemetry.py"), "temperature"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { const s = JSON.parse(text); root.temperature = s.temperature ?? -1; }
                catch (_) { root.temperature = -1; }
            }
        }
    }
    Timer { interval: 2000; running: true; repeat: true; triggeredOnStart: true; onTriggered: if (!stats.running) stats.running = true }
    Timer { interval: 10000; running: true; repeat: true; triggeredOnStart: true; onTriggered: if (!temps.running) temps.running = true }
}
