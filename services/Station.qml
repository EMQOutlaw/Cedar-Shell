pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import ".."
import "../components"
import "../components/core/Diagnostics.js" as Diagnostics

// CEDAR Station: the health of this desktop as a first-party application.
// It reuses the collectors that already exist (SettingsInfo for the service
// list and versions, SystemStats for the live readings, Capabilities for
// the privilege helper and the GPU path, CoreService for the update check)
// and adds one read-only helper, scripts/station.py, for failed units, the
// shell log, configuration files and the GPU reading. The diagnostics
// engine (components/core/Diagnostics.js) turns those readings into issues
// that say what happened, why it matters, what was verified, the action on
// offer and whether it needs elevated privileges. Nothing polls: Station
// reads when its window opens and when asked; SystemStats raises its
// cadence only while the window is open.
Singleton {
    id: root
    property var data: ({ failedUnits: [], logIssues: [], config: [], gpu: { available: false, source: "none" }, shellMemoryMb: -1, logPath: "" })
    property bool ready: false
    property string error: ""
    property string message: ""
    property string logs: ""
    property string logsFor: ""
    property string report: ""
    property double readAt: 0
    readonly property bool busy: worker.busy
    property bool updatesChecked: false

    // ------------------------------------------------------------- derived
    readonly property var services: SettingsInfo.data.services || []
    readonly property int updates: updatesChecked ? CoreService.packages.length : -1
    readonly property var issues: Diagnostics.diagnose({
        services: services, failedUnits: data.failedUnits, logIssues: data.logIssues, config: data.config,
        disk: SystemStats.disk, diskLimit: Config.saved.coreDiskLimit / 100, temperature: SystemStats.temperature, temperatureLimit: Config.saved.coreTemperatureLimit,
        updates: updates, shellMemoryMb: data.shellMemoryMb, visualQuality: VisualQuality.level,
        // Only once discovered, and with CEDAR's own polkit agent counted: the defaults before the probe answers are not readings.
        capabilities: Capabilities.ready ? Object.assign({}, Capabilities.data, { privilege: { helper: Capabilities.privilege.helper, agent: Capabilities.privilege.agent || Permission.registered } }) : null })
    readonly property string status: !ready ? "reading" : Diagnostics.status(issues)
    readonly property string headline: ready ? Diagnostics.headline(status) : "Reading…"
    readonly property int criticalCount: issues.filter(i => i.severity === "critical").length
    readonly property int warningCount: issues.filter(i => i.severity === "warning").length
    readonly property int noticeCount: issues.filter(i => i.severity === "notice").length
    readonly property string subline: !ready ? "" : issues.length === 0 ? "Nothing needs attention" : [criticalCount ? criticalCount + " to fix" : "", warningCount ? warningCount + (warningCount === 1 ? " warning" : " warnings") : "", noticeCount ? noticeCount + (noticeCount === 1 ? " notice" : " notices") : ""].filter(Boolean).join(" · ")
    readonly property int healthyServices: services.filter(s => s.status === "Healthy").length
    function issue(id) { return issues.find(i => i.id === id) || null; }

    // ------------------------------------------------------------- actions
    function refresh() {
        if (Config.testMode) return;
        error = "";
        SettingsInfo.refresh(true);
        if (!Capabilities.ready) Capabilities.refresh();
        worker.send({ action: "snapshot" });
    }
    function checkUpdates() { if (!Config.testMode) { updatesChecked = true; CoreService.run({ action: "check-updates" }); } }
    function restart(unit, user) { if (Config.testMode || !unit) return; error = ""; message = "Restarting " + unit + "…"; worker.send({ action: "restart", unit: unit, user: !!user }); }
    function resetFailed(unit, user) { if (Config.testMode || !unit) return; error = ""; message = "Resetting " + unit + "…"; worker.send({ action: "reset-failed", unit: unit, user: !!user }); }
    function showLogs(unit, user) { if (Config.testMode || !unit) return; logsFor = unit; worker.send({ action: "logs", unit: unit, user: !!user }); }
    function act(issue) {
        if (!issue || !issue.action) return;
        const r = issue.action.request;
        if (r.action === "restart") restart(r.unit, r.user);
    }
    // The report: Station's own sections plus the helper's snapshot, redacted by the helper.
    function buildReport() {
        if (Config.testMode) return;
        const sections = [
            { title: "Status", text: headline + " · " + subline + "\n" + issues.map(i => "[" + i.severity + "] " + i.title + " — " + i.what).join("\n") },
            { title: "Versions", text: "CEDAR " + SettingsInfo.data.version + "\n" + SettingsInfo.data.os + "\nKernel " + SettingsInfo.data.kernel + "\n" + Object.keys(SettingsInfo.data.versions || {}).map(k => k + ": " + SettingsInfo.data.versions[k]).join("\n") },
            { title: "Services", text: services.map(s => s.name + ": " + s.status + " (" + s.detail + ")").join("\n") },
            { title: "Readings", text: "CPU " + (SystemStats.cpu >= 0 ? Math.round(SystemStats.cpu) + "%" : "unknown") + "\nMemory " + SystemStats.memoryLabel + "\nDisk " + (SystemStats.disk >= 0 ? Math.round(SystemStats.disk * 100) + "%" : "unknown") + "\nTemperature " + (SystemStats.temperature >= 0 ? Math.round(SystemStats.temperature) + " °C" : "unknown") + "\nGPU " + (data.gpu.available ? data.gpu.utilization + "% (" + data.gpu.source + ")" : "no supported path") + "\nShell memory " + (data.shellMemoryMb >= 0 ? Math.round(data.shellMemoryMb) + " MB" : "unknown") + "\nVisual quality " + VisualQuality.level + "\nUpdates " + (updates >= 0 ? updates : "not checked") },
            { title: "Capabilities", text: JSON.stringify(Capabilities.data) }
        ];
        worker.send({ action: "report", sections: sections });
    }
    ServiceRequest {
        id: worker
        script: "scripts/station.py"
        timeoutMs: 150000              // pkexec waits for the user
        onResult: value => {
            root.error = "";
            if (value.failedUnits !== undefined) { root.data = Object.assign({}, root.data, value); root.ready = true; root.readAt = Date.now(); }
            if (value.message !== undefined) { root.message = value.message; SettingsInfo.refresh(true); }
            if (value.logs !== undefined) root.logs = value.logs;
            if (value.report !== undefined) root.report = value.report;
        }
        onFailed: text => { root.error = text; root.message = ""; root.ready = true; }
    }
    Connections { target: CoreService; function onPackagesChanged() { root.updatesChecked = true; } }

    // ---------------------------------------------------------------- window
    property bool windowOpen: false
    readonly property bool open: windowOpen && !ShellState.locked
    readonly property var pageIds: ["overview", "services", "issues", "log", "report"]
    property string requestedPage: ""
    function openApp() { if (ShellState.locked) return; windowOpen = true; }
    function openPage(page) { const id = String(page || "").toLowerCase(); if (!pageIds.includes(id) || ShellState.locked) return; windowOpen = true; requestedPage = ""; requestedPage = id; }
    function closeApp() { windowOpen = false; }
    function toggleApp() { if (windowOpen) closeApp(); else openApp(); }
    onOpenChanged: if (open) refresh()
    Connections { target: ShellState; function onLockedChanged() { if (ShellState.locked) root.windowOpen = false; } }
}
