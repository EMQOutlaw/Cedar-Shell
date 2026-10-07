pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import ".."
import "../components"

// Gaming Mode: a transactional, temporary system state. activate() runs
// CAPTURE → APPLY → VERIFY → ACTIVE over an explicit registry of
// optimizations; each reports what really happened, so the pill can say
// "4 / 5 optimizations active" and name the one that did not take.
// deactivate() restores exactly what was captured. The captured values are
// written to ~/.local/state/cedar/gaming.json before anything is applied, so
// a shell that dies mid-game restores the desktop on its next start.
//
// Registry (settings in the Power page):
//   quiet       visual quality → gaming (in-process; VisualQuality reads `active`)
//   dnd         Do not disturb on                         (gamingDnd)
//   idle        no idle lock or sleep while the game runs (gamingIdle)
//   power       system power profile → performance       (gamingPower)
//   compositor  Hyprland blur / animations off at runtime (gamingBlur, gamingAnimations)
//   gamemode    Feral GameMode, observed over D-Bus; never driven
// Nothing is frozen or signalled: only CEDAR's own behaviour and the
// providers above change, through their supported interfaces.
Singleton {
    id: root
    property bool active: false
    property bool busy: false
    property string phase: "idle"      // idle | capture | apply | restore
    property string trigger: ""        // manual | gamemode | restored
    property var captured: ({})
    property var steps: []             // [{id, label, state, detail}] state: active | failed | unavailable | off | observing
    property string error: ""
    property double activatedAt: 0
    property int gameModeClients: 0
    readonly property bool gameModeActive: gameModeClients > 0
    readonly property bool inhibitIdle: active && Config.saved.gamingIdle
    readonly property int activeCount: steps.filter(s => s.state === "active").length
    readonly property int totalCount: steps.filter(s => s.state === "active" || s.state === "failed").length
    readonly property var failures: steps.filter(s => s.state === "failed")
    readonly property string summary: !active ? (busy ? "Quieting the desktop…" : "Off")
        : busy ? "Quieting the desktop…" : activeCount + " / " + totalCount + (totalCount === 1 ? " optimization active" : " optimizations active")
    readonly property string detail: failures.length ? failures.map(f => f.label + " could not be changed").join(" · ") : ""

    readonly property var registry: [
        { id: "quiet", label: "Visual quality", enabled: true },
        { id: "dnd", label: "Do not disturb", enabled: Config.saved.gamingDnd },
        { id: "idle", label: "Stay awake", enabled: Config.saved.gamingIdle },
        { id: "power", label: "Performance power profile", enabled: Config.saved.gamingPower },
        { id: "compositor", label: "Compositor effects", enabled: Config.saved.gamingBlur || Config.saved.gamingAnimations },
        { id: "gamemode", label: "GameMode", enabled: true }
    ]
    function stepIndex(id) { return steps.findIndex(s => s.id === id); }
    function setStep(id, state, detailText) {
        const next = steps.slice(), at = stepIndex(id), entry = registry.find(r => r.id === id);
        const row = { id: id, label: entry ? entry.label : id, state: state, detail: detailText || "" };
        if (at >= 0) next[at] = row; else next.push(row);
        steps = next;
    }

    // ------------------------------------------------------------ activate
    function toggle() { if (busy) return; if (active) deactivate(); else activate("manual"); }
    function activate(reason) {
        if (active || busy || ShellState.locked) return;
        busy = true; error = ""; phase = "capture"; trigger = reason || "manual";
        steps = registry.map(r => ({ id: r.id, label: r.label, state: r.enabled ? "pending" : "off", detail: r.enabled ? "" : "Turned off in Settings" }));
        captured = { dnd: Config.saved.doNotDisturb, profile: Controls.data.profile || "", compositor: null };
        if (wantsCompositor() && Capabilities.gaming.hyprctl && !Config.testMode) ask({ action: "compositor", mode: "capture" });
        else apply();
    }
    function wantsCompositor() { return Config.saved.gamingBlur || Config.saved.gamingAnimations; }
    function apply() {
        phase = "apply";
        active = true;                                   // quiet: VisualQuality follows this
        persist();
        setStep("quiet", "active", "Breathing light, spores, sweeps and ambient telemetry paused");
        if (Config.saved.gamingDnd) {
            Config.set("doNotDisturb", true);
            setStep("dnd", Config.saved.doNotDisturb ? "active" : "failed", Config.saved.doNotDisturb ? "Popups wait until you leave" : "Setting did not take");
        }
        if (Config.saved.gamingIdle) {
            if (Config.testMode || !Capabilities.gaming.systemdInhibit) setStep("idle", "unavailable", Config.testMode ? "Not started in test mode" : "systemd-inhibit is not installed");
            else inhibitCheck.restart();
        }
        if (Capabilities.gaming.gameModeAvailable) setStep("gamemode", gameModeActive ? "active" : "observing", gameModeActive ? gameModeClients + " game registered" : "Installed; no game registered yet");
        else setStep("gamemode", "unavailable", "GameMode is not installed");
        queue = [];
        if (Config.saved.gamingPower) queue.push("power");
        if (wantsCompositor()) queue.push("compositor");
        next();
    }
    property var queue: []
    function next() {
        const id = queue.shift();
        if (id === "power") return applyPower();
        if (id === "compositor") return applyCompositor();
        if (id === "restore-compositor") return restoreCompositor();
        if (id === "restore-power") return restorePower();
        settle();
    }
    function settle() {
        phase = active ? "active" : "idle"; busy = false;
        if (active) { activatedAt = Date.now(); persist(); announce(); }
        else { captured = ({}); store.setText(""); CoreService.remove("gaming", false); }
    }

    // power: through Controls (power-profiles-daemon); verified by reading back
    property string waitingFor: ""
    function applyPower() {
        const profiles = Controls.data.profiles || [];
        if (Config.testMode || !profiles.includes("performance")) { setStep("power", "unavailable", Config.testMode ? "No power provider in test mode" : "No performance profile on this computer"); return next(); }
        if (Controls.data.profile === "performance") { setStep("power", "active", "Already on performance"); return next(); }
        if (Controls.busy) { setStep("power", "failed", "The power service was busy"); return next(); }
        waitingFor = "power"; Controls.run({ action: "profile", value: "performance" });
    }
    function restorePower() {
        const previous = captured.profile || "";
        if (Config.testMode || !previous || previous === "performance" || Controls.data.profile === previous) return next();
        waitingFor = "restore-power"; Controls.run({ action: "profile", value: previous });
    }
    Connections {
        target: Controls
        function onBusyChanged() {
            if (Controls.busy || !root.waitingFor) return;
            const what = root.waitingFor; root.waitingFor = "";
            if (what === "power") root.setStep("power", Controls.data.profile === "performance" ? "active" : "failed", Controls.data.profile === "performance" ? "Switched from " + (root.captured.profile || "unknown") : (Controls.error || "Profile did not change"));
            root.next();
        }
    }

    // compositor: hyprctl keyword through the helper; verified by getoption
    function applyCompositor() {
        if (Config.testMode || !Capabilities.gaming.hyprctl) { setStep("compositor", "unavailable", Config.testMode ? "No compositor in test mode" : "hyprctl is not available"); return next(); }
        const values = {};
        if (Config.saved.gamingBlur) values.blur = false;
        if (Config.saved.gamingAnimations) values.animations = false;
        ask({ action: "compositor", mode: "apply", values: values });
    }
    function restoreCompositor() {
        const previous = captured.compositor;
        if (!previous || Config.testMode) return next();
        ask({ action: "compositor", mode: "apply", values: previous });
    }
    // One ServiceRequest object per helper call. A shared process object
    // raced its own exit handling (the reply arrives before the process exits
    // and the request field is cleared), so each call gets a fresh one that
    // is destroyed after it exits.
    property var asked: ({})
    Component {
        id: helperFactory
        ServiceRequest { script: "scripts/gaming.py"; timeoutMs: 10000 }
    }
    function ask(request) {
        asked = request;
        const h = helperFactory.createObject(root);
        h.result.connect(value => root.helperResult(request, value));
        h.failed.connect(message => root.helperFailed(request, message));
        h.exited.connect(() => h.destroy(50));
        h.send(request);
    }
    function helperResult(request, value) {
        if (phase === "capture") { captured = Object.assign({}, captured, { compositor: value }); apply(); return; }
        if (phase === "apply") {
            const wanted = request.values || {};
            const bad = Object.keys(wanted).filter(k => value[k] !== wanted[k]);
            setStep("compositor", bad.length ? "failed" : "active", bad.length ? "Hyprland kept " + bad.join(", ") + " on" : Object.keys(wanted).map(k => k === "blur" ? "blur" : "animations").join(" and ") + " off until you leave");
        }
        next();
    }
    function helperFailed(request, message) {
        if (phase === "capture") { captured = Object.assign({}, captured, { compositor: null }); setStep("compositor", "failed", message); apply(); return; }
        if (phase === "apply") setStep("compositor", "failed", message);
        else error = "Compositor effects were not restored: " + message;
        next();
    }

    // idle: a logind inhibitor held for as long as Gaming Mode is active, plus
    // CEDAR's own idle lock reading inhibitIdle. Verified by the process running.
    Process {
        id: inhibit
        running: root.active && Config.saved.gamingIdle && Capabilities.gaming.systemdInhibit && !Config.testMode
        command: ["systemd-inhibit", "--what=idle:sleep", "--who=CEDAR Gaming Mode", "--why=A game is running", "--mode=block", "sleep", "infinity"]
        onRunningChanged: if (!running && root.active && root.stepIndex("idle") >= 0 && root.steps[root.stepIndex("idle")].state === "active") root.setStep("idle", "failed", "The inhibitor exited")
    }
    Timer { id: inhibitCheck; interval: 400; onTriggered: root.setStep("idle", inhibit.running ? "active" : "failed", inhibit.running ? "Idle lock and sleep held off" : "systemd-inhibit did not start") }

    // ------------------------------------------------------------ deactivate
    function deactivate() {
        if (!active || busy) return;
        busy = true; phase = "restore";
        active = false;                                   // quiet off first: VisualQuality returns
        if (Config.saved.gamingDnd && stepIndex("dnd") >= 0 && steps[stepIndex("dnd")].state === "active") Config.set("doNotDisturb", !!captured.dnd);
        queue = [];
        if (captured.compositor) queue.push("restore-compositor");
        if (captured.profile) queue.push("restore-power");
        next();
    }

    // ------------------------------------------------------------- feedback
    function announce() {
        if (!CoreService.enabled) return;
        CoreService.publish({ id: "gaming", type: "integration", title: "Gaming Mode", subtitle: summary + (detail ? " · " + detail : ""),
                              persistent: true, sticky: false, priority: failures.length ? "high" : "normal", announce: true, timeout: 3000,
                              actions: [{ id: "leave", label: "Leave Gaming Mode" }] });
    }
    onSummaryChanged: if (active && !busy) announce()

    // ---------------------------------------------------- crash recovery
    FileView { id: store; path: Config.stateDir + "/gaming.json"; atomicWrites: true; printErrors: false; blockLoading: true }
    function persist() { store.setText(JSON.stringify({ active: true, trigger: trigger, captured: captured, at: Date.now() }) + "\n"); }
    Component.onCompleted: {
        if (Config.testMode) return;
        let saved = null;
        try { saved = JSON.parse(store.text() || "null"); } catch (_) { saved = null; }
        if (saved && saved.active && saved.captured) {
            // The previous shell died with Gaming Mode on: put the desktop back.
            captured = saved.captured; trigger = "restored"; busy = true; phase = "restore"; active = false;
            if (captured.dnd !== undefined) Config.set("doNotDisturb", !!captured.dnd);
            queue = [];
            if (captured.compositor) queue.push("restore-compositor");
            if (captured.profile) queue.push("restore-power");
            next();
        }
    }

    // ---------------------------------------------------- GameMode watch
    Process {
        id: gameModeWatch
        running: Capabilities.gaming.gameModeAvailable && !Config.testMode
        command: ["python3", Quickshell.shellPath("scripts/gamemode_watch.py")]
        stdout: SplitParser {
            onRead: line => {
                try {
                    const event = JSON.parse(line);
                    root.gameModeClients = event.available ? Number(event.clients) || 0 : 0;
                } catch (_) {}
            }
        }
    }
    onGameModeClientsChanged: {
        if (active) setStep("gamemode", gameModeActive ? "active" : "observing", gameModeActive ? gameModeClients + " game registered" : "No game registered");
        if (gameModeActive && !active && !busy && Config.saved.gamingAutoGameMode) activate("gamemode");
        else if (!gameModeActive && active && !busy && trigger === "gamemode") deactivate();
    }
    Connections { target: ShellState; function onLockedChanged() { if (ShellState.locked && root.active && !root.busy && root.trigger === "manual") root.deactivate(); } }
}
