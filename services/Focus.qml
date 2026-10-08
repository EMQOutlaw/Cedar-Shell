pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import ".."
import "../components"

// CEDAR Focus: a timed session in which the desktop quiets itself. A sibling
// to Shield and Gaming Mode: a transaction over CEDAR's own settings (do not
// disturb, Whispers, Trails, a quiet desktop) held in the ownership stack
// under "focus", so a Desktop Profile and Focus can overlap and both restore
// correctly. Statistics are observed, never estimated: a notification that
// CEDAR's own popup path held back counts as held; one that reached the
// screen (critical, or an app you excepted) counts as an interruption.
// CEDAR is this session's notification server, so "held" means held.
//
// The session outlives the shell: ~/.local/state/cedar/focus.json carries
// the deadline, the counts and the values each held key had before, and a
// restarted shell re-holds them and carries on (or ends an expired session).
Singleton {
    id: root
    readonly property string owner: "focus"
    property bool active: false
    property bool paused: false
    property double startedAt: 0
    property double deadline: 0
    property real pausedRemaining: 0
    property int preset: 25
    property int held: 0
    property int interruptions: 0
    property string error: ""
    property string trigger: ""          // manual | restored
    property double now: Date.now()
    property var history: []            // newest first: {startedAt, endedAt, planned, actual, held, interruptions, completed}
    readonly property real remaining: active ? Math.max(0, paused ? pausedRemaining : (deadline - now) / 1000) : 0
    readonly property real planned: preset * 60
    readonly property real elapsed: active ? Math.max(0, planned - remaining) : 0
    readonly property real fraction: active && planned > 0 ? Math.min(1, elapsed / planned) : 0
    readonly property alias steps: tx.steps
    readonly property alias busy: tx.busy
    readonly property alias phase: tx.phase
    readonly property var failures: tx.failures
    readonly property int readyCount: tx.readyCount
    readonly property int plannedCount: tx.plannedCount
    readonly property real progress: tx.progress
    Transaction { id: tx; onSettled: root.settle() }

    function clock(seconds) {
        const s = Math.max(0, Math.round(seconds)), h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), r = s % 60;
        return h ? h + ":" + String(m).padStart(2, "0") + ":" + String(r).padStart(2, "0") : m + ":" + String(r).padStart(2, "0");
    }
    function minutes(seconds) { const m = Math.round(seconds / 60); return m + (m === 1 ? " min" : " min"); }
    readonly property string summary: busy ? (phase === "restore" ? "Restoring the desktop…" : "Quieting the desktop…")
        : !active ? "Off" : (paused ? "Paused · " : "") + minutes(remaining) + " left" + (held ? " · " + held + " held" : "")
    readonly property string detail: failures.length ? failures.map(f => f.label + " could not be changed").join(" · ") : ""

    // -------------------------------------------------------- the registry
    // What a session quiets, from Settings › Notifications › Focus.
    readonly property var registry: [
        { id: "dnd", key: "doNotDisturb", value: true, label: "Do not disturb", hud: "Notifications", restored: "Notifications", enabled: Config.saved.focusDnd },
        { id: "whispers", key: "forestWhispers", value: false, label: "Whispers", hud: "Whispers", restored: "Whispers", enabled: Config.saved.focusWhispers },
        { id: "trails", key: "forestTrails", value: false, label: "Activity trails", hud: "Trails", restored: "Trails", enabled: Config.saved.focusTrails },
        { id: "ambient", key: "ambientIntensity", value: 0, label: "Ambient effects", hud: "Desktop appearance", restored: "Desktop appearance", enabled: Config.saved.focusQuiet },
        { id: "performance", key: "performanceMode", value: "on", label: "Performance mode", hud: "Visual quality", restored: "Visual quality", enabled: Config.saved.focusQuiet }
    ]
    readonly property var allowedApps: String(Config.saved.focusAllowedApps || "").split(",").map(s => s.trim().toLowerCase()).filter(Boolean)
    function allows(app) { return active && allowedApps.includes(String(app || "").toLowerCase()); }

    // -------------------------------------------------------------- start
    function start(minutesWanted) {
        if (active || busy || ShellState.locked) return false;
        const m = Number(minutesWanted || Config.saved.focusMinutes || 25);
        if (!isFinite(m) || m < 1 || m > 600) return false;
        error = ""; trigger = "manual";
        preset = Math.round(m); now = Date.now(); startedAt = now; deadline = now + preset * 60000;
        paused = false; pausedRemaining = 0; held = 0; interruptions = 0;
        tx.registry = registry;
        tx.start("apply");
        showHud("enter");
        active = true;
        for (const r of registry) {
            if (!r.enabled) continue;
            const took = Overrides.apply(r.key, owner, r.value);
            tx.setStep(r.id, took ? "active" : "failed", took ? r.label + " " + (typeof r.value === "boolean" ? (r.value ? "on" : "off") : r.value === 0 ? "off" : String(r.value)) : "Setting did not take");
        }
        persist();
        tx.launched();
        return true;
    }
    function toggle() { if (active) { if (paused) resume(); else pause(); } else start(); }
    function pause() {
        if (!active || paused || busy) return;
        now = Date.now(); pausedRemaining = Math.max(0, (deadline - now) / 1000); paused = true; persist(); announce();
    }
    function resume() {
        if (!active || !paused || busy) return;
        now = Date.now(); deadline = now + pausedRemaining * 1000; paused = false; persist(); announce();
    }
    function end() { finish("ended"); }
    function complete() { finish("completed"); }
    function finish(reason) {
        if (!active || busy) return;
        now = Date.now();
        const actual = Math.max(0, Math.round(planned - remaining));
        const entry = { startedAt: startedAt, endedAt: now, planned: planned, actual: actual, held: held, interruptions: interruptions, completed: reason === "completed" };
        history = [entry].concat(history).slice(0, 30);
        lastSession = entry;
        error = "";
        const attempted = tx.steps.filter(s => s.state === "active" || s.state === "failed").map(s => s.id);
        showHud("leave");
        active = false; paused = false;
        tx.start("restore", attempted);
        for (const id of attempted) {
            const r = registry.find(x => x.id === id), res = Overrides.restore(r.key, owner);
            tx.setStep(id, res.ok ? "restored" : "failed", !res.ok ? "Setting did not take" : res.restore ? r.label + " as before" : Overrides.reasonText(res.reason));
        }
        tx.launched();
        if (reason === "completed" && CoreService.enabled)
            CoreService.publish({ id: "focus-complete", type: "timer", priority: "high", title: "Focus complete · " + minutes(planned), subtitle: held + " held · " + interruptions + (interruptions === 1 ? " interruption" : " interruptions"),
                                  persistent: true, sticky: true, remember: true, actions: [{ id: "dismiss", label: "Dismiss" }] });
    }
    property var lastSession: null
    function settle() {
        if (phase === "idle") { Overrides.releaseAll(owner); CoreService.remove("focus", false); store.setText(JSON.stringify({ history: history }) + "\n"); }
        else { persist(); announce(); }
        if (hudShown) hudHold.restart();
    }

    // ------------------------------------------------------------ the clock
    // One second while something shows the seconds; a minute for the pill;
    // a single shot at the deadline for completion. Nothing while inactive.
    Timer { interval: 1000; repeat: true; running: root.active && !root.paused && (root.windowOpen || CoreService.expanded); onTriggered: root.now = Date.now() }
    Timer { interval: 60000; repeat: true; running: root.active && !root.paused; onTriggered: { root.now = Date.now(); root.announce(); } }
    Timer { id: finishClock; interval: Math.max(50, root.deadline - Date.now()); running: root.active && !root.paused; repeat: false; onTriggered: { root.now = Date.now(); if (root.remaining <= 0) root.complete(); else restart(); } }
    onDeadlineChanged: if (active && !paused) finishClock.restart()
    onPausedChanged: if (active && !paused) finishClock.restart()

    // --------------------------------------------------- observed statistics
    Connections {
        target: NoticeStore
        function onNoticeRecorded(n) {
            if (!root.active || Config.testMode && false) return;
            const critical = n.urgency === 2, hidden = Config.saved.doNotDisturb && !critical && !root.allows(n.appName) || !Config.saved.notificationsEnabled;
            if (hidden) root.held++; else root.interruptions++;
            root.persist();
        }
    }

    // ------------------------------------------------------------- feedback
    function announce() {
        if (!CoreService.enabled || !active) return;
        CoreService.publish({ id: "focus", type: "integration", title: "Focus · " + minutes(planned), subtitle: summary + (detail ? " · " + detail : ""),
                              persistent: true, sticky: false, priority: failures.length ? "high" : "normal", announce: false, timeout: 3000,
                              actions: [{ id: "focus-pause", label: paused ? "Resume" : "Pause" }, { id: "focus-end", label: "End session" }] });
    }
    property bool hudShown: false
    property bool hudClosing: false
    property string hudMode: "enter"
    property string hudScreen: ""
    property bool hudForTests: false
    readonly property bool hudSettled: hudShown && !busy
    function showHud(mode) {
        if (Config.testMode && !hudForTests) return;
        if (ShellState.locked || trigger === "restored") return;
        hudHold.stop(); hudExit.stop();
        hudMode = mode; hudClosing = false; hudScreen = ShellState.focusedOutput(); hudShown = true;
    }
    function hideHud() { hudHold.stop(); hudExit.stop(); hudClosing = false; hudShown = false; }
    Timer { id: hudHold; interval: 1200; onTriggered: { root.hudClosing = true; hudExit.restart(); } }
    Timer { id: hudExit; interval: Config.saved.reducedMotion ? 0 : 200; onTriggered: { root.hudShown = false; root.hudClosing = false; } }

    // ---------------------------------------------------------------- window
    property bool windowOpen: false
    readonly property bool open: windowOpen && !ShellState.locked
    function openApp() { if (ShellState.locked) return; windowOpen = true; now = Date.now(); }
    function closeApp() { windowOpen = false; }
    function toggleApp() { if (windowOpen) closeApp(); else openApp(); }

    // ---------------------------------------------------------- persistence
    FileView { id: store; path: Config.stateDir + "/focus.json"; atomicWrites: true; printErrors: false; blockLoading: true }
    function persist() {
        const heldKeys = Overrides.keysHeldBy(owner).map(k => ({ key: k, previous: Overrides.entry(k, owner).previous, value: Overrides.entry(k, owner).value }));
        store.setText(JSON.stringify({ active: active, paused: paused, startedAt: startedAt, deadline: deadline, pausedRemaining: pausedRemaining, preset: preset, held: held, interruptions: interruptions, keys: heldKeys, steps: tx.steps, history: history }) + "\n");
    }
    Component.onCompleted: {
        let saved = null;
        try { saved = JSON.parse(store.text() || "null"); } catch (_) { saved = null; }
        if (!saved || typeof saved !== "object") return;
        history = Array.isArray(saved.history) ? saved.history.slice(0, 30) : [];
        if (Config.testMode || !saved.active) return;
        // The previous shell stopped mid-session: re-hold what it held and carry on.
        trigger = "restored";
        startedAt = Number(saved.startedAt) || Date.now(); deadline = Number(saved.deadline) || Date.now(); pausedRemaining = Number(saved.pausedRemaining) || 0;
        preset = Number(saved.preset) || 25; held = Number(saved.held) || 0; interruptions = Number(saved.interruptions) || 0; paused = !!saved.paused;
        for (const k of (saved.keys || [])) if (k.key in Config.saved) Overrides.hold(k.key, owner, k.previous, k.value);
        tx.registry = registry; tx.steps = Array.isArray(saved.steps) ? saved.steps : []; tx.phase = "active";
        active = true; now = Date.now();
        trigger = "manual";
        if (!paused && deadline <= now) complete(); else announce();
    }
    Connections { target: ShellState; function onLockedChanged() { if (ShellState.locked) { root.hideHud(); root.windowOpen = false; } } }
}
