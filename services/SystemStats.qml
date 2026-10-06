pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import ".."

// One shell-wide sampler. Visible instruments increase cadence; the quiet Core
// and warning service retain slower, explicitly named background subscriptions.
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
    readonly property bool instrument: !ShellState.locked && (ShellState.panel === "hud" || (ShellState.panel === "settings" && ["overview","system"].includes(ShellState.settingsSection)) || (Canopy.shown && ["system", "quick"].includes(Canopy.topic)))
    readonly property bool ambient: Config.saved.forestPulse && Config.saved.coreEnabled && !ShellState.locked
    readonly property bool warnings: Config.saved.coreWarnings
    readonly property int fastCadence: instrument ? 2000 : ambient ? 20000 : 0
    readonly property int temperatureCadence: instrument ? 5000 : warnings ? 30000 : 0
    readonly property int slowCadence: instrument || warnings ? 30000 : 0
    readonly property bool demanded: !Config.testMode && !!(fastCadence || temperatureCadence || slowCadence)
    property var sampled: ({fast:0, slow:0, temperature:0})
    property int backoff: 0
    property double retryAfter: 0
    onInstrumentChanged: if (instrument && demanded) schedule.restart()
    function sample() {
        if (!demanded || worker.running || Date.now() < retryAfter) return;
        const now = Date.now(), topics = [];
        for (const pair of [["fast",fastCadence],["slow",slowCadence],["temperature",temperatureCadence]])
            if (pair[1] && now - sampled[pair[0]] >= pair[1]) topics.push(pair[0]);
        if (!topics.length) return;
        const next = Object.assign({}, sampled);
        topics.forEach(topic => next[topic] = now);
        sampled = next;
        worker.command = ["python3", Quickshell.shellPath("scripts/telemetry.py"), "sample", Config.diskPath, topics.join(",")];
        worker.running = true;
    }
    Timer { id: schedule; interval: 1000; running: root.demanded; repeat: true; triggeredOnStart: true; onTriggered: root.sample() }
    Process {
        id: worker
        onStarted: deadline.restart()
        onExited: (code, status) => {
            deadline.stop();
            if (code !== 0) { root.backoff = Math.min(60000, Math.max(2000, root.backoff*2)); root.retryAfter = Date.now()+root.backoff; }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    if (text.length > 16384) throw new Error("Oversized telemetry");
                    const s = JSON.parse(text);
                    if (s.error) throw new Error("Unavailable telemetry");
                    root.backoff = 0;
                    if (s.fast?.error) root.available=false;
                    if (s.fast && !s.fast.error) {
                        const f = s.fast, delta = f.total - root.previousTotal;
                        if (root.previousTotal > 0 && delta > 0) root.cpu = Math.max(0, Math.min(1, 1-(f.idle-root.previousIdle)/delta));
                        root.previousTotal = f.total; root.previousIdle = f.idle;
                        root.networkRate = root.previousTime && f.monotonic > root.previousTime && f.netBytes >= root.previousBytes
                            ? (f.netBytes-root.previousBytes)/(f.monotonic-root.previousTime) : 0;
                        root.previousBytes = f.netBytes; root.previousTime = f.monotonic;
                        root.ram = f.ram;
                        root.memoryLabel = f.ramUsed.toFixed(1) + " / " + f.ramTotal.toFixed(1) + " GiB";
                        root.available = true;
                    }
                    if (s.slow?.error) {root.disk=-1;root.uptime="Unavailable";}
                    if (s.slow && !s.slow.error) {
                        root.disk = s.slow.disk;
                        root.uptime = Math.floor(s.slow.uptime/86400) + "d " + Math.floor(s.slow.uptime/3600)%24 + "h " + Math.floor(s.slow.uptime/60)%60 + "m";
                    }
                    if (s.temperature) root.temperature = s.temperature.temperature ?? -1;
                } catch (_) {
                    root.available = false;
                    root.backoff = Math.min(60000, Math.max(2000, root.backoff*2));
                    root.retryAfter = Date.now()+root.backoff;
                }
            }
        }
    }
    Timer { id: deadline; interval: 8000; onTriggered: worker.running = false }
}
