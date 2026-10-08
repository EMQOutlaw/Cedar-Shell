pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import ".."

// One shell-wide sampler, read in-process. /proc/stat, /proc/meminfo,
// /proc/net/dev, /proc/uptime and the hwmon temperature inputs are FileViews
// read synchronously on their own cadence (preload + blockLoading, then
// reload + waitForJob: a few hundred bytes each, microseconds on the main
// thread, no helper process; without preload a reload hands back the previous
// read). Only
// disk usage asks a process (`df`), every 30 s while an instrument shows it or
// every five minutes for the disk warning. Visible instruments raise the
// cadence; the quiet Core and the warning service keep slower, explicitly
// named background subscriptions. One timer sleeps until the next due topic
// instead of ticking every second to ask whether anything is due.
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
    readonly property bool instrument: !ShellState.locked && (ShellState.panel === "hud" || Station.open || (ShellState.panel === "settings" && ["overview","system"].includes(ShellState.settingsSection)) || (Canopy.shown && ["system", "quick", "station"].includes(Canopy.topic)))
    // Below normal visual quality (Performance or Gaming Mode) the ambient pulse stops; instruments and warnings keep their cadence.
    readonly property bool ambient: Config.saved.forestPulse && Config.saved.coreEnabled && !ShellState.locked && VisualQuality.normal
    readonly property bool warnings: Config.saved.coreWarnings
    readonly property int fastCadence: instrument ? 2000 : ambient ? 20000 : 0
    readonly property int temperatureCadence: instrument ? 5000 : warnings ? 30000 : 0
    readonly property int slowCadence: instrument ? 30000 : warnings ? 300000 : 0
    readonly property bool demanded: !Config.testMode && !!(fastCadence || temperatureCadence || slowCadence)
    property var sampled: ({fast:0, slow:0, temperature:0})
    // Built per call: a `property var` list is not yet assigned when the first
    // cadence change handlers run during construction.
    function cadences() { return [["fast", fastCadence], ["slow", slowCadence], ["temperature", temperatureCadence]]; }

    // An instrument opening wants fresh numbers now, not at the ambient cadence.
    onInstrumentChanged: if (instrument && demanded) { root.sampled = ({fast:0, slow:0, temperature:0}); root.sample(); }
    // Change handlers do not fire for construction-time values, so arm once.
    Component.onCompleted: root.arm()
    onDemandedChanged: root.arm()
    onFastCadenceChanged: root.arm()
    onSlowCadenceChanged: root.arm()
    onTemperatureCadenceChanged: root.arm()

    // `force` reads every topic regardless of demand (tests and diagnostics).
    function sample(force) {
        if (!force && !demanded) return;
        const now = Date.now(), topics = [];
        for (const pair of cadences())
            if (force || (pair[1] && now - sampled[pair[0]] >= pair[1])) topics.push(pair[0]);
        if (topics.length) {
            const next = Object.assign({}, sampled);
            topics.forEach(topic => next[topic] = now);
            sampled = next;
            if (topics.includes("fast")) { root.readCpu(root.read(stat)); root.readMemory(root.read(meminfo)); root.readNetwork(root.read(netdev)); }
            if (topics.includes("slow")) { root.readUptime(root.read(uptimeFile)); if (!df.running) df.running = true; }
            if (topics.includes("temperature")) root.readTemperature();
        }
        arm();
    }
    // Sleep until the earliest due topic; a change in demand re-arms.
    function arm() {
        schedule.stop();
        if (!demanded) return;
        const now = Date.now();
        let wait = Infinity;
        for (const pair of cadences())
            if (pair[1]) wait = Math.min(wait, Math.max(0, sampled[pair[0]] + pair[1] - now));
        if (wait === Infinity) return;
        schedule.interval = Math.max(50, wait);
        schedule.start();
    }
    Timer { id: schedule; onTriggered: root.sample() }
    function fail() { root.available = false; }
    // A fresh synchronous read; "" when the file cannot be read.
    function read(view) { view.reload(); view.waitForJob(); return String(view.text() || ""); }

    // ------------------------------------------------------------------ fast
    FileView { id: stat; path: "/proc/stat"; preload: true; blockLoading: true; printErrors: false }
    FileView { id: meminfo; path: "/proc/meminfo"; preload: true; blockLoading: true; printErrors: false }
    FileView { id: netdev; path: "/proc/net/dev"; preload: true; blockLoading: true; printErrors: false }
    function readCpu(text) {
        const fields = String(text).split("\n")[0].trim().split(/\s+/).slice(1, 9).map(Number);
        if (fields.length < 5 || fields.some(isNaN)) { root.fail(); return; }
        const total = fields.reduce((a, b) => a + b, 0), idle = fields[3] + fields[4], delta = total - root.previousTotal;
        if (root.previousTotal > 0 && delta > 0) root.cpu = Math.max(0, Math.min(1, 1 - (idle - root.previousIdle) / delta));
        root.previousTotal = total; root.previousIdle = idle;
        root.available = true;
    }
    function readMemory(text) {
        const mem = {}, pattern = /^(\w+):\s+(\d+)/gm, source = String(text);
        for (let match = pattern.exec(source); match; match = pattern.exec(source)) mem[match[1]] = Number(match[2]);
        if (!(mem.MemTotal > 0) || !(mem.MemAvailable >= 0)) { root.fail(); return; }
        root.ram = 1 - mem.MemAvailable / mem.MemTotal;
        root.memoryLabel = ((mem.MemTotal - mem.MemAvailable) / 1048576).toFixed(1) + " / " + (mem.MemTotal / 1048576).toFixed(1) + " GiB";
    }
    function readNetwork(text) {
        let bytes = 0;
        for (const line of String(text).split("\n").slice(2)) {
            const colon = line.indexOf(":");
            if (colon < 0 || line.slice(0, colon).trim() === "lo") continue;
            const v = line.slice(colon + 1).trim().split(/\s+/);
            if (v.length > 8) bytes += Number(v[0]) + Number(v[8]);
        }
        const now = Date.now() / 1000;
        root.networkRate = root.previousTime && now > root.previousTime && bytes >= root.previousBytes ? (bytes - root.previousBytes) / (now - root.previousTime) : 0;
        root.previousBytes = bytes; root.previousTime = now;
    }

    // ------------------------------------------------------------------ slow
    FileView { id: uptimeFile; path: "/proc/uptime"; preload: true; blockLoading: true; printErrors: false }
    function readUptime(text) {
        const seconds = Number(String(text).split(/\s+/)[0]);
        root.uptime = text && isFinite(seconds) ? Math.floor(seconds / 86400) + "d " + Math.floor(seconds / 3600) % 24 + "h " + Math.floor(seconds / 60) % 60 + "m" : "Unavailable";
    }
    // POSIX `df`: "<fs> <1024-blocks> <used> <available> <capacity> <mount>".
    Process {
        id: df
        command: ["df", "-P", "-k", "--", Config.diskPath]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = String(text).trim().split("\n"), fields = (lines[lines.length - 1] || "").trim().split(/\s+/);
                const total = Number(fields[1]), used = Number(fields[2]);
                root.disk = lines.length > 1 && total > 0 && used >= 0 ? used / total : -1;
            }
        }
        onExited: (code, status) => { if (code !== 0) root.disk = -1; }
    }

    // ----------------------------------------------------------- temperature
    // hwmon inputs are discovered once by the helper (chip names need a read per
    // directory), then read here forever. The CPU package sensor is preferred;
    // without one, the hottest of every input stands in, as `sensors` did.
    property var sensorPaths: []
    property bool discovered: false
    property double discoveredAt: 0
    property var readings: ({})
    readonly property var preferredChips: ["k10temp", "zenpower", "coretemp", "cpu_thermal", "acpitz", "thinkpad"]
    readonly property var preferredLabels: ["tctl", "tdie", "package id 0", "cpu"]
    function chooseSensors(rows) {
        for (const chip of preferredChips) {
            const mine = rows.filter(r => r.chip === chip);
            if (!mine.length) continue;
            const labelled = mine.filter(r => preferredLabels.includes(String(r.label).toLowerCase()));
            return (labelled.length ? labelled : mine.slice(0, 1)).map(r => r.path);
        }
        return rows.map(r => r.path);
    }
    function readTemperature() {
        if (!discovered || (!sensorPaths.length && Date.now() - discoveredAt > 600000)) {
            if (!discover.running && !Config.testMode) discover.running = true;
            return;
        }
        for (let i = 0; i < sensors.count; ++i) { const view = sensors.objectAt(i); root.readSensor(view.path, root.read(view)); }
    }
    function readSensor(path, text) {
        const raw = String(text).trim(), value = raw ? Number(raw) / 1000 : NaN;
        const next = Object.assign({}, readings);
        if (isFinite(value) && value > -20 && value < 150) next[path] = value; else delete next[path];
        readings = next;
        const values = Object.values(readings);
        root.temperature = values.length ? Math.max(...values) : -1;
    }
    Process {
        id: discover
        command: ["python3", Quickshell.shellPath("scripts/telemetry.py"), "sensors"]
        stdout: StdioCollector {
            onStreamFinished: {
                let rows = [];
                try { rows = JSON.parse(text); if (!Array.isArray(rows)) rows = []; } catch (_) { rows = []; }
                root.sensorPaths = root.chooseSensors(rows.filter(r => r && typeof r.path === "string" && r.path.startsWith("/sys/class/hwmon/")));
                root.discovered = true; root.discoveredAt = Date.now(); root.readings = ({});
                if (root.sensorPaths.length) root.readTemperature(); else root.temperature = -1;
            }
        }
        onExited: (code, status) => { if (code !== 0) { root.discovered = true; root.discoveredAt = Date.now(); root.sensorPaths = []; root.temperature = -1; } }
    }
    Instantiator {
        id: sensors
        model: root.sensorPaths
        delegate: FileView {
            required property string modelData
            path: modelData; preload: true; blockLoading: true; printErrors: false
        }
    }
}
