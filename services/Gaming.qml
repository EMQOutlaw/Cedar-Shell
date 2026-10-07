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
//
// Steps that do not depend on each other run at the same time: the power
// profile and the compositor are asked together and the transaction settles
// when the last one has answered. Each row moves pending → applying →
// active | failed | unavailable (or restored on the way out), and the
// preparation panel (modules/GamingHud.qml) simply reacts to `steps`.
Singleton {
    id: root
    property bool active: false
    property bool busy: false
    property string phase: "idle"      // idle | capture | apply | restore
    property string trigger: ""        // manual | gamemode | restored
    property var captured: ({})
    property var steps: []             // [{id, label, hud, restored, state, detail}] state: pending | applying | active | failed | unavailable | off | observing | restored
    property string error: ""
    property double activatedAt: 0
    property int gameModeClients: 0
    property var gameNames: []         // executables GameMode reports, from the watcher
    readonly property string gameName: gameNames.length ? gameNames[0] : ""
    readonly property bool gameModeActive: gameModeClients > 0
    readonly property bool inhibitIdle: active && Config.saved.gamingIdle
    readonly property int activeCount: steps.filter(s => s.state === "active").length
    readonly property int totalCount: steps.filter(s => s.state === "active" || s.state === "failed").length
    readonly property var failures: steps.filter(s => s.state === "failed")
    // Progress for the panel: rows that will be attempted, and rows that are done.
    readonly property int plannedCount: steps.filter(s => s.state === "pending" || s.state === "applying" || s.state === "active" || s.state === "failed" || s.state === "restored").length
    readonly property int readyCount: steps.filter(s => s.state === "active" || s.state === "restored").length
    readonly property real progress: plannedCount ? readyCount / plannedCount : 0
    readonly property string summary: !active ? (busy ? (phase === "restore" ? "Restoring the desktop…" : "Quieting the desktop…") : "Off")
        : busy ? "Quieting the desktop…" : activeCount + " / " + totalCount + (totalCount === 1 ? " optimization active" : " optimizations active")
    readonly property string detail: failures.length ? failures.map(f => f.label + " could not be changed").join(" · ") : ""

    readonly property var registry: [
        { id: "quiet", label: "Visual quality", hud: "CEDAR effects", restored: "CEDAR effects restored", enabled: true },
        { id: "dnd", label: "Do not disturb", hud: "Notifications", restored: "Notifications restored", enabled: Config.saved.gamingDnd },
        { id: "idle", label: "Stay awake", hud: "Sleep inhibited", restored: "Idle policy restored", enabled: Config.saved.gamingIdle },
        { id: "power", label: "Performance power profile", hud: "Performance profile", restored: "Performance profile restored", enabled: Config.saved.gamingPower },
        { id: "compositor", label: "Compositor effects", hud: "Compositor effects", restored: "Compositor effects restored", enabled: Config.saved.gamingBlur || Config.saved.gamingAnimations },
        { id: "gamemode", label: "GameMode", hud: "GameMode", restored: "GameMode", enabled: true }
    ]
    function stepIndex(id) { return steps.findIndex(s => s.id === id); }
    function stepState(id) { const at = stepIndex(id); return at >= 0 ? steps[at].state : ""; }
    function setStep(id, state, detailText) {
        const next = steps.slice(), at = stepIndex(id), entry = registry.find(r => r.id === id);
        const row = { id: id, label: entry ? entry.label : id, hud: entry ? entry.hud : id, restored: entry ? entry.restored : id, state: state, detail: detailText || "" };
        if (at >= 0) next[at] = row; else next.push(row);
        steps = next;
    }

    // Outstanding asynchronous steps. `launching` holds the settle back while
    // the steps are still being started, so a step that answers at once does
    // not end the transaction before the others have begun.
    property int outstanding: 0
    property bool launching: false
    function begin() { outstanding++; }
    function finish() { outstanding = Math.max(0, outstanding - 1); if (!launching && outstanding === 0 && busy && phase !== "capture") settle(); }
    function launched() { launching = false; if (outstanding === 0 && busy) settle(); }

    // ------------------------------------------------------------ activate
    function toggle() { if (busy) return; if (active) deactivate(); else activate("manual"); }
    function activate(reason) {
        if (active || busy || ShellState.locked) return;
        busy = true; error = ""; phase = "capture"; trigger = reason || "manual";
        steps = registry.map(r => ({ id: r.id, label: r.label, hud: r.hud, restored: r.restored, state: r.enabled ? "pending" : "off", detail: r.enabled ? "" : "Turned off in Settings" }));
        captured = ({}); controlsAsked = false;
        showHud("enter");
        prepare();
    }
    // Prerequisites before anything is captured: the capability registry
    // must have answered (right after login it may still be discovering) and
    // the power snapshot must be current, since Controls only reads it when a
    // panel opens. Without this, Super+G seconds after login reported steps
    // as unavailable and captured no profile to restore.
    property bool controlsAsked: false
    function prepare() {
        if (phase !== "capture") return;
        if (Config.testMode) return capture();
        if (!Capabilities.ready) return;                              // onReadyChanged → prepare()
        if (!controlsAsked && !(Controls.data.profiles || []).length) { controlsAsked = true; waitingFor = "snapshot"; Controls.refresh(); if (Controls.busy) return; waitingFor = ""; }
        capture();
    }
    Connections { target: Capabilities; function onReadyChanged() { if (Capabilities.ready) root.prepare(); } }
    function capture() {
        captured = { dnd: Config.saved.doNotDisturb, profile: Controls.data.profile || "", compositor: null };
        if (wantsCompositor() && Capabilities.gaming.hyprctl && !Config.testMode) { setStep("compositor", "applying", "Reading the current values"); ask({ action: "compositor", mode: "capture" }); }
        else apply();
    }
    function wantsCompositor() { return Config.saved.gamingBlur || Config.saved.gamingAnimations; }
    function apply() {
        phase = "apply"; launching = true; outstanding = 0;
        active = true;                                   // quiet: VisualQuality follows this
        persist();
        setStep("quiet", "active", "Breathing light, spores, sweeps and ambient telemetry paused");
        if (Config.saved.gamingDnd) {
            Config.set("doNotDisturb", true);
            setStep("dnd", Config.saved.doNotDisturb ? "active" : "failed", Config.saved.doNotDisturb ? "Popups wait until you leave" : "Setting did not take");
        }
        if (Config.saved.gamingIdle) {
            if (Config.testMode || !Capabilities.gaming.systemdInhibit) setStep("idle", "unavailable", Config.testMode ? "Not started in test mode" : "systemd-inhibit is not installed");
            else { setStep("idle", "applying", "Holding off idle lock and sleep"); begin(); inhibitCheck.restart(); }
        }
        if (Capabilities.gaming.gameModeAvailable) setStep("gamemode", gameModeActive ? "active" : "observing", gameModeActive ? gameModeClients + " game registered" : "Installed; no game registered yet");
        else setStep("gamemode", "unavailable", "GameMode is not installed");
        // Independent providers: asked together, verified separately.
        if (Config.saved.gamingPower) applyPower();
        if (wantsCompositor()) applyCompositor();
        launched();
    }
    function settle() {
        phase = active ? "active" : "idle"; busy = false; launching = false;
        if (active) { activatedAt = Date.now(); persist(); announce(); }
        else { captured = ({}); store.setText(""); CoreService.remove("gaming", false); }
        if (hudShown) hudHold.restart();
    }

    // power: through Controls (power-profiles-daemon); verified by reading back
    property string waitingFor: ""
    function applyPower() {
        const profiles = Controls.data.profiles || [];
        if (Config.testMode || !profiles.includes("performance")) return setStep("power", "unavailable", Config.testMode ? "No power provider in test mode" : "No performance profile on this computer");
        if (Controls.data.profile === "performance") return setStep("power", "active", "Already on performance");
        if (Controls.busy) return setStep("power", "failed", "The power service was busy");
        setStep("power", "applying", "Asking power-profiles-daemon");
        waitingFor = "power"; begin(); Controls.run({ action: "profile", value: "performance" });
    }
    function restorePower() {
        const previous = captured.profile || "";
        if (Config.testMode || !previous || previous === "performance" || Controls.data.profile === previous) { if (stepIndex("power") >= 0) setStep("power", "restored", "Profile unchanged"); return; }
        if (Controls.busy) return setStep("power", "failed", "The power service was busy");
        setStep("power", "applying", "Returning to " + previous);
        waitingFor = "restore-power"; begin(); Controls.run({ action: "profile", value: previous });
    }
    Connections {
        target: Controls
        function onBusyChanged() {
            if (Controls.busy || !root.waitingFor) return;
            const what = root.waitingFor; root.waitingFor = "";
            if (what === "snapshot") return root.prepare();
            if (what === "power") root.setStep("power", Controls.data.profile === "performance" ? "active" : "failed", Controls.data.profile === "performance" ? "Switched from " + (root.captured.profile || "unknown") : (Controls.error || "Profile did not change"));
            else { const previous = root.captured.profile || ""; root.setStep("power", Controls.data.profile === previous ? "restored" : "failed", Controls.data.profile === previous ? "Back on " + previous : (Controls.error || "Profile did not return to " + previous)); }
            root.finish();
        }
    }

    // compositor: hyprctl through the helper; verified by getoption
    function applyCompositor() {
        if (Config.testMode || !Capabilities.gaming.hyprctl) return setStep("compositor", "unavailable", Config.testMode ? "No compositor in test mode" : "hyprctl is not available");
        const values = {};
        if (Config.saved.gamingBlur) values.blur = false;
        if (Config.saved.gamingAnimations) values.animations = false;
        setStep("compositor", "applying", "Asking Hyprland");
        begin(); ask({ action: "compositor", mode: "apply", values: values });
    }
    function restoreCompositor() {
        const previous = captured.compositor;
        if (!previous || Config.testMode) return;
        setStep("compositor", "applying", "Returning Hyprland's values");
        begin(); ask({ action: "compositor", mode: "apply", values: previous });
    }
    // One ServiceRequest object per helper call. A shared process object
    // raced its own exit handling (the reply arrives before the process exits
    // and the request field is cleared), so each call gets a fresh one that
    // is destroyed after it exits.
    Component {
        id: helperFactory
        ServiceRequest { script: "scripts/gaming.py"; timeoutMs: 10000 }
    }
    function ask(request) {
        const h = helperFactory.createObject(root);
        h.result.connect(value => root.helperResult(request, value));
        h.failed.connect(message => root.helperFailed(request, message));
        h.exited.connect(() => h.destroy(50));
        h.send(request);
    }
    function helperResult(request, value) {
        if (phase === "capture") { captured = Object.assign({}, captured, { compositor: value }); apply(); return; }
        const wanted = request.values || {};
        const bad = Object.keys(wanted).filter(k => value[k] !== wanted[k]);
        if (phase === "apply") setStep("compositor", bad.length ? "failed" : "active", bad.length ? "Hyprland kept " + bad.join(", ") + " on" : Object.keys(wanted).map(k => k === "blur" ? "blur" : "animations").join(" and ") + " off until you leave");
        else setStep("compositor", bad.length ? "failed" : "restored", bad.length ? "Hyprland did not take " + bad.join(", ") + " back" : "Blur and animations as before");
        if (bad.length && phase === "restore") error = "Compositor effects were not fully restored: " + bad.join(", ");
        finish();
    }
    function helperFailed(request, message) {
        if (phase === "capture") { captured = Object.assign({}, captured, { compositor: null }); setStep("compositor", "failed", message); apply(); return; }
        setStep("compositor", "failed", message);
        if (phase === "restore") error = "Compositor effects were not restored: " + message;
        finish();
    }

    // idle: a logind inhibitor held for as long as Gaming Mode is active, plus
    // CEDAR's own idle lock reading inhibitIdle. Verified by the process running.
    Process {
        id: inhibit
        running: root.active && Config.saved.gamingIdle && Capabilities.gaming.systemdInhibit && !Config.testMode
        command: ["systemd-inhibit", "--what=idle:sleep", "--who=CEDAR Gaming Mode", "--why=A game is running", "--mode=block", "sleep", "infinity"]
        onRunningChanged: if (!running && root.active && root.stepState("idle") === "active") root.setStep("idle", "failed", "The inhibitor exited")
    }
    Timer { id: inhibitCheck; interval: 400; onTriggered: { root.setStep("idle", inhibit.running ? "active" : "failed", inhibit.running ? "Idle lock and sleep held off" : "systemd-inhibit did not start"); root.finish(); } }
    Timer { id: releaseCheck; interval: 400; onTriggered: { root.setStep("idle", inhibit.running ? "failed" : "restored", inhibit.running ? "The inhibitor is still running" : "Idle lock and sleep allowed again"); root.finish(); } }

    // ------------------------------------------------------------ deactivate
    function deactivate() {
        if (!active || busy) return;
        busy = true; phase = "restore"; error = ""; launching = true; outstanding = 0;
        const was = steps;
        const attempted = id => was.some(s => s.id === id && (s.state === "active" || s.state === "failed"));
        showHud("leave");
        active = false;                                   // quiet off first: VisualQuality returns
        // Rows for what was changed, in registry order; GameMode is only observed.
        steps = registry.filter(r => r.id !== "gamemode" && attempted(r.id)).map(r => ({ id: r.id, label: r.label, hud: r.hud, restored: r.restored, state: "pending", detail: "" }));
        setStep("quiet", "restored", "Breathing light, spores and sweeps back");
        if (attempted("dnd")) { Config.set("doNotDisturb", !!captured.dnd); setStep("dnd", Config.saved.doNotDisturb === !!captured.dnd ? "restored" : "failed", Config.saved.doNotDisturb === !!captured.dnd ? "Popups show again" : "Setting did not take"); }
        if (attempted("idle")) { setStep("idle", "applying", "Releasing the inhibitor"); begin(); releaseCheck.restart(); }
        if (captured.compositor && attempted("compositor")) restoreCompositor();
        if (captured.profile && attempted("power")) restorePower();
        launched();
    }

    // ------------------------------------------------------------- feedback
    // The preparation panel. hudShown is explicit state: on while a transaction
    // runs, held for a moment once it settles, then closed. The window itself
    // is created by shell.qml only while hudShown is true.
    property bool hudShown: false
    property bool hudClosing: false
    property string hudMode: "enter"   // enter | leave
    property string hudScreen: ""
    readonly property bool hudSettled: hudShown && !busy
    function showHud(mode) {
        if (Config.testMode && !hudForTests) return;
        if (ShellState.locked || trigger === "restored") return;
        hudHold.stop(); hudExit.stop();
        hudMode = mode; hudClosing = false; hudScreen = ShellState.focusedOutput(); hudShown = true;
    }
    property bool hudForTests: false
    function hideHud() { hudHold.stop(); hudExit.stop(); hudClosing = false; hudShown = false; }
    Timer { id: hudHold; interval: 1200; onTriggered: { root.hudClosing = true; hudExit.restart(); } }
    Timer { id: hudExit; interval: Config.saved.reducedMotion ? 0 : 200; onTriggered: { root.hudShown = false; root.hudClosing = false; } }
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
            captured = saved.captured; trigger = "restored"; busy = true; phase = "restore"; active = false; launching = true; outstanding = 0;
            if (captured.dnd !== undefined) Config.set("doNotDisturb", !!captured.dnd);
            if (captured.compositor) restoreCompositor();
            if (captured.profile) restorePower();
            launched();
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
                    root.gameNames = event.available && Array.isArray(event.games) ? event.games.filter(n => typeof n === "string" && n !== "") : [];
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
    Connections { target: ShellState; function onLockedChanged() { if (ShellState.locked) { root.hideHud(); if (root.active && !root.busy && root.trigger === "manual") root.deactivate(); } } }
}
