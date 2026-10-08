pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import ".."
import "../components"
import "../components/core/Profiles.js" as Policy

// Desktop Profiles: one active stance for the desktop, applied as a
// transaction over typed operations (components/core/Profiles.js) through
// the providers CEDAR already drives, verified by reading each one back,
// and restored exactly on leave. Gaming is a profile too: its transaction
// is Gaming Mode's own, so Super+G and the Gaming tile keep working and the
// Profiles surface simply reflects it.
//
// Ownership: every value a profile changes is held in Overrides under the
// owner "profile". Focus and Gaming Mode hold the same keys under their own
// names, so nested changes restore in any order, and a value the user
// changes by hand while a profile holds it stays as the user left it.
//
// Profiles are exclusive: activating one while another is on restores the
// first and then applies the second. Definitions live in
// ~/.config/cedar/profiles.json (only Custom is editable); the runtime
// state in ~/.local/state/cedar/profiles.json is what a shell that died
// mid-profile reads on its next start to put the desktop back.
Singleton {
    id: root
    readonly property string owner: "profile"
    property string active: ""              // the profile whose values are held right now ("" = none)
    property string target: ""              // the profile being applied
    property string queued: ""              // a profile waiting for the current one to restore
    property string error: ""
    property string trigger: ""             // manual | restored
    property double activatedAt: 0
    property alias steps: tx.steps
    property alias busy: tx.busy
    property alias phase: tx.phase
    readonly property int activeCount: tx.activeCount
    readonly property int totalCount: tx.totalCount
    readonly property var failures: tx.failures
    readonly property int plannedCount: tx.plannedCount
    readonly property int readyCount: tx.readyCount
    readonly property real progress: tx.progress
    Transaction { id: tx; onSettled: root.settle() }

    // ---------------------------------------------------------- definitions
    property var user: ({})
    readonly property var definitions: Policy.definitions(user)
    readonly property var ops: Policy.ops
    readonly property var opOrder: Policy.order
    function definition(id) { return Policy.definition(definitions, id); }
    function describe(key, value) { return Policy.describe(key, value); }
    function managed(id) { return Policy.managed(definition(id)); }
    // Accent colours from tokens; "moss" is warm green, derived, never a literal.
    function accent(name) {
        return ({ green: Theme.green, teal: Theme.teal, blue: Theme.blue, violet: Theme.violet, amber: Theme.amber, brightGreen: Theme.brightGreen,
                  moss: Qt.tint(Theme.green, Qt.alpha(Theme.amber, .45)) })[name] || Theme.green;
    }
    function accentOf(id) { const d = definition(id); return accent(d ? d.accent : "green"); }
    // Custom is the user's: operations and accent, persisted apart from runtime state.
    function setCustomOp(key, value) {
        const custom = Object.assign({}, user.custom || {}), ops = Object.assign({}, custom.ops || {});
        if (value === null || value === undefined) delete ops[key]; else ops[key] = value;
        custom.ops = ops; user = Object.assign({}, user, { custom: custom }); saveUser();
    }
    function setCustomAccent(name) {
        if (!Policy.accents.includes(name)) return;
        user = Object.assign({}, user, { custom: Object.assign({}, user.custom || {}, { accent: name }) }); saveUser();
    }
    FileView {
        id: userFile
        path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/cedar/profiles.json"
        atomicWrites: true; printErrors: false; blockLoading: true; watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { const v = JSON.parse(text() || "{}"); root.user = v && typeof v === "object" ? v : ({}); } catch (_) { root.user = ({}); } }
    }
    function saveUser() { userFile.setText(JSON.stringify(user, null, 2) + "\n"); }

    // ------------------------------------------------------------- derived
    // What the desktop is in right now, Gaming included.
    readonly property string current: Gaming.active || (Gaming.busy && Gaming.phase !== "restore" && Gaming.phase !== "idle") ? "gaming" : active
    readonly property string currentLabel: current ? (definition(current) || { label: current }).label : "None"
    readonly property bool anyBusy: busy || Gaming.busy
    readonly property string summary: busy ? (phase === "restore" ? "Restoring the desktop…" : "Preparing " + (definition(target) || { label: "" }).label.toLowerCase() + "…")
        : current === "gaming" ? "Gaming · " + Gaming.summary
        : active ? currentLabel + " · " + activeCount + " / " + totalCount + (totalCount === 1 ? " change" : " changes") + (failures.length ? " · " + failures.length + " failed" : "")
        : "No profile"
    readonly property string detail: failures.length ? failures.map(f => f.label + " could not be changed").join(" · ") : ""

    // ------------------------------------------------------------ activate
    function toggle(id) { if (anyBusy) return; if (current === id) deactivate(); else activate(id); }
    function activate(id) {
        if (anyBusy || ShellState.locked) return;
        const def = definition(id);
        if (!def) return;
        if (def.gaming) { if (active) { queued = "gaming"; deactivate(); } else Gaming.activate("manual"); return; }
        if (Gaming.active) { queued = id; Gaming.deactivate(); return; }
        if (active) { queued = id; deactivate(); return; }
        error = ""; target = id; trigger = "manual"; controlsAsked = false; audioAsked = false;
        const wanted = Policy.managed(def);
        tx.registry = wanted.map(m => ({ id: m.key, label: ops[m.key].label, hud: ops[m.key].hud, restored: ops[m.key].hud, enabled: true, value: m.value }));
        tx.start("capture");
        showHud("enter");
        prepare();
    }
    // Providers that answer lazily must have answered before anything is captured.
    property bool controlsAsked: false
    property bool audioAsked: false
    property string waitingFor: ""
    function wants(key) { return tx.registry.some(r => r.id === key); }
    function wantedValue(key) { const r = tx.registry.find(r => r.id === key); return r ? r.value : undefined; }
    function prepare() {
        if (phase !== "capture") return;
        if (Config.testMode) return apply();
        if (!Capabilities.ready) return;
        if ((wants("power") || wants("nightlight")) && !controlsAsked) { controlsAsked = true; waitingFor = "snapshot"; Controls.refresh(); if (Controls.busy) return; waitingFor = ""; }
        if (wants("audioScene") && !audioAsked) { audioAsked = true; waitingFor = "audio"; AudioInstruments.refresh(); if (AudioInstruments.busy) return; waitingFor = ""; }
        apply();
    }
    Connections { target: Capabilities; function onReadyChanged() { if (Capabilities.ready) root.prepare(); } }
    function apply() {
        tx.run("apply");
        active = target; activatedAt = Date.now();
        persist();
        for (const r of tx.registry) applyOp(r.id, r.value);
        tx.launched();
    }
    function applyOp(key, value) {
        const cfg = Policy.configKeys[key];
        if (cfg) {
            const took = Overrides.apply(cfg, owner, value);
            return tx.setStep(key, took ? "active" : "failed", took ? ops[key].label + " " + describe(key, value) : "Setting did not take");
        }
        if (key === "power") {
            const profiles = Controls.data.profiles || [];
            if (Config.testMode || !profiles.includes(value)) return tx.setStep(key, "unavailable", Config.testMode ? "No power provider in test mode" : "No " + value + " profile on this computer");
            Overrides.hold("power", owner, Controls.data.profile || "", value);
            if (Controls.data.profile === value) return tx.setStep(key, "active", "Already on " + value);
            tx.setStep(key, "applying", "Asking power-profiles-daemon"); waitingFor = "power"; tx.begin(); Qt.callLater(() => root.send(Controls, { action: "profile", value: value }, "power"));
            return;
        }
        if (key === "nightlight") {
            if (Config.testMode || Controls.data.nightlight === null || Controls.data.nightlight === undefined) return tx.setStep(key, "unavailable", Config.testMode ? "No night-light provider in test mode" : "No night-light provider is running");
            Overrides.hold("nightlight", owner, !!Controls.data.nightlight, !!value);
            if (!!Controls.data.nightlight === !!value) return tx.setStep(key, "active", "Already " + (value ? "on" : "off"));
            tx.setStep(key, "applying", "Asking the night-light provider"); waitingFor = "nightlight"; tx.begin(); Qt.callLater(() => root.send(Controls, { action: "nightlight" }, "nightlight"));
            return;
        }
        if (key === "audioScene") {
            const scene = (AudioInstruments.data.scenes || []).find(s => s.name === value);
            if (Config.testMode || !scene) return tx.setStep(key, "unavailable", Config.testMode ? "No audio service in test mode" : "No saved scene named “" + value + "”");
            const current = (AudioInstruments.data.outputs || []).find(o => o.name === AudioInstruments.data.default) || null;
            Overrides.hold("audioScene", owner, current ? { name: current.name, volume: current.volume } : null, value);
            tx.setStep(key, "applying", "Applying scene “" + value + "”"); waitingFor = "audio-apply"; tx.begin(); Qt.callLater(() => root.send(AudioInstruments, { action: "apply-scene", name: value }, "audioScene"));
            return;
        }
        tx.setStep(key, "unavailable", "Unknown operation");
    }
    Connections {
        target: Controls
        function onGenerationChanged() {
            if (!root.waitingFor || !["snapshot", "power", "nightlight", "restore-power", "restore-nightlight"].includes(root.waitingFor)) return;
            const what = root.waitingFor; root.waitingFor = "";
            if (what === "snapshot") return Qt.callLater(root.prepare);
            if (what === "power") { const v = root.wantedValue("power"); root.setDone("power", Controls.data.profile === v, Controls.data.profile === v ? "Switched to " + v : (Controls.error || "Profile did not change")); }
            else if (what === "nightlight") { const v = !!root.wantedValue("nightlight"); root.setDone("nightlight", !!Controls.data.nightlight === v, !!Controls.data.nightlight === v ? "Night light " + (v ? "on" : "off") : (Controls.error || "Night light did not change")); }
            else if (what === "restore-power") { const v = root.restoreTarget; root.setBack("power", Controls.data.profile === v, Controls.data.profile === v ? "Back on " + v : (Controls.error || "Profile did not return to " + v)); }
            else if (what === "restore-nightlight") { const v = root.restoreTarget === "on"; root.setBack("nightlight", !!Controls.data.nightlight === v, !!Controls.data.nightlight === v ? "Night light " + (v ? "on" : "off") + " again" : (Controls.error || "Night light did not change back")); }
            tx.finish();
        }
    }
    Connections {
        target: AudioInstruments
        function onGenerationChanged() {
            if (!root.waitingFor || !["audio", "audio-apply", "restore-audio"].includes(root.waitingFor)) return;
            const what = root.waitingFor; root.waitingFor = "";
            if (what === "audio") return Qt.callLater(root.prepare);
            const scene = (AudioInstruments.data.scenes || []).find(s => s.name === root.wantedValue("audioScene"));
            if (what === "audio-apply") { const ok = !AudioInstruments.error && scene && AudioInstruments.data.default === scene.output.name; root.setDone("audioScene", ok, ok ? "Output on " + scene.output.name : (AudioInstruments.error || "The scene's output is not the default")); }
            else { const ok = !AudioInstruments.error && AudioInstruments.data.default === root.restoreTarget; root.setBack("audioScene", ok, ok ? "Output back on " + root.restoreTarget : (AudioInstruments.error || "Output did not return")); }
            tx.finish();
        }
    }
    // Send a provider request after leaving the previous reply's signal
    // context; a service still finishing its last process queues it.
    function send(service, request, key) { service.run(request); }
    function setDone(key, ok, text) { tx.setStep(key, ok ? "active" : "failed", text); }
    function setBack(key, ok, text) { tx.setStep(key, ok ? "restored" : "failed", text); if (!ok) error = text; }
    // External providers changed outside us: note it so the restore respects it.
    Connections {
        target: Controls
        function onDataChanged() {
            if (root.waitingFor) return;
            if (Overrides.holder("power") === root.owner) Overrides.external("power", Controls.data.profile || "");
            if (Overrides.holder("nightlight") === root.owner && Controls.data.nightlight !== null && Controls.data.nightlight !== undefined) Overrides.external("nightlight", !!Controls.data.nightlight);
        }
    }

    // ---------------------------------------------------------- deactivate
    property string restoreTarget: ""
    function deactivate() {
        if (!active || busy) return;
        error = "";
        const attempted = tx.steps.filter(s => s.state === "active" || s.state === "failed").map(s => s.id);
        showHud("leave");
        tx.start("restore", attempted);
        for (const key of attempted) restoreOp(key);
        tx.launched();
    }
    function restoreOp(key) {
        const cfg = Policy.configKeys[key];
        if (cfg) {
            const r = Overrides.restore(cfg, owner);
            return tx.setStep(key, r.ok ? "restored" : "failed", !r.ok ? "Setting did not take" : r.restore ? ops[key].label + " as before" : Overrides.reasonText(r.reason));
        }
        if (key === "power") {
            const r = Overrides.release("power", owner);
            if (!r.restore) return tx.setStep(key, "restored", Overrides.reasonText(r.reason));
            const previous = r.target || "";
            if (Config.testMode || !previous || Controls.data.profile === previous) return tx.setStep(key, "restored", "Profile unchanged");
            restoreTarget = previous; tx.setStep(key, "applying", "Returning to " + previous); waitingFor = "restore-power"; tx.begin(); Qt.callLater(() => root.send(Controls, { action: "profile", value: previous }, "power"));
            return;
        }
        if (key === "nightlight") {
            const r = Overrides.release("nightlight", owner);
            if (!r.restore) return tx.setStep(key, "restored", Overrides.reasonText(r.reason));
            if (Config.testMode || Controls.data.nightlight === null || !!Controls.data.nightlight === !!r.target) return tx.setStep(key, "restored", "Night light unchanged");
            restoreTarget = r.target ? "on" : "off"; tx.setStep(key, "applying", "Returning night light"); waitingFor = "restore-nightlight"; tx.begin(); Qt.callLater(() => root.send(Controls, { action: "nightlight" }, "nightlight"));
            return;
        }
        if (key === "audioScene") {
            const r = Overrides.release("audioScene", owner);
            if (!r.restore || !r.target || !r.target.name) return tx.setStep(key, "restored", r.restore ? "No previous output to return to" : Overrides.reasonText(r.reason));
            if (Config.testMode || AudioInstruments.data.default === r.target.name) return tx.setStep(key, "restored", "Output unchanged");
            restoreTarget = r.target.name; tx.setStep(key, "applying", "Returning output to " + r.target.name); waitingFor = "restore-audio"; tx.begin(); Qt.callLater(() => root.send(AudioInstruments, { action: "output", name: r.target.name, volume: r.target.volume }, "audioScene"));
            return;
        }
        tx.setStep(key, "restored", "");
    }
    function settle() {
        if (phase === "idle") {
            // A restore finished: nothing is held any more.
            Overrides.releaseAll(owner);
            active = ""; target = ""; store.setText(""); CoreService.remove("profile", false);
            if (hudShown) hudHold.restart();
            if (queued) { const next = queued; queued = ""; Qt.callLater(() => root.activate(next)); }
            return;
        }
        persist(); announce();
        if (hudShown) hudHold.restart();
    }
    // Gaming Mode is a profile: when it ends and one is waiting, apply it.
    Connections {
        target: Gaming
        function onBusyChanged() { if (!Gaming.busy && !Gaming.active && root.queued && !root.busy) { const next = root.queued; root.queued = ""; Qt.callLater(() => root.activate(next)); } }
    }

    // ------------------------------------------------------------- feedback
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
    function announce() {
        if (!CoreService.enabled || !active) return;
        CoreService.publish({ id: "profile", type: "integration", title: currentLabel + " profile", subtitle: summary + (detail ? " · " + detail : ""),
                              persistent: true, sticky: false, priority: failures.length ? "high" : "normal", announce: failures.length > 0, timeout: 3000,
                              actions: [{ id: "leave", label: "Leave " + currentLabel }] });
    }
    onSummaryChanged: if (active && !busy) announce()

    // ---------------------------------------------------------------- window
    property bool windowOpen: false
    readonly property bool open: windowOpen && !ShellState.locked
    function openApp() { if (ShellState.locked) return; windowOpen = true; }
    function closeApp() { windowOpen = false; }
    function toggleApp() { if (windowOpen) closeApp(); else openApp(); }
    onOpenChanged: if (open && !Config.testMode) { Controls.refresh(); if (!(AudioInstruments.data.scenes || []).length) AudioInstruments.refresh(); }

    // ---------------------------------------------------- crash recovery
    FileView { id: store; path: Config.stateDir + "/profiles.json"; atomicWrites: true; printErrors: false; blockLoading: true }
    function persist() {
        const held = Overrides.keysHeldBy(owner).map(k => ({ key: k, previous: Overrides.entry(k, owner).previous }));
        store.setText(JSON.stringify({ active: active, held: held, at: Date.now() }) + "\n");
    }
    Component.onCompleted: {
        if (Config.testMode) return;
        let saved = null;
        try { saved = JSON.parse(store.text() || "null"); } catch (_) { saved = null; }
        if (saved && saved.active && Array.isArray(saved.held)) {
            // The previous shell died with a profile on: put the plain settings back now,
            // and the outside providers as soon as their snapshots arrive.
            trigger = "restored";
            for (const h of saved.held) {
                if (Overrides.watched.includes(h.key) && h.key in Config.saved) { Overrides.writing = true; Config.set(h.key, h.previous); Overrides.writing = false; }
                else if (h.key === "power" && h.previous) recoverPower = h.previous;
            }
            store.setText("");
        }
    }
    property string recoverPower: ""
    Connections { target: Controls; function onDataChanged() { if (root.recoverPower && !Controls.busy && (Controls.data.profiles || []).includes(root.recoverPower)) { const p = root.recoverPower; root.recoverPower = ""; if (Controls.data.profile !== p) Controls.run({ action: "profile", value: p }); } } }
    Connections { target: ShellState; function onLockedChanged() { if (ShellState.locked) { root.hideHud(); root.windowOpen = false; } } }
}
