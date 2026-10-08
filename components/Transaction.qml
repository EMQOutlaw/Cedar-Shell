import QtQuick

// A transaction over an explicit registry of steps. Gaming Mode, Desktop
// Profiles and Focus share it: CAPTURE the current values, APPLY each
// enabled step through its provider, VERIFY by reading the provider back,
// settle into ACTIVE; RESTORE runs the same rows in reverse. Each row moves
//   pending → applying → active | failed | unavailable   (apply)
//   pending → applying → restored | failed               (restore)
// and `off` marks a registry entry the user turned off. The owner decides
// what each step does; this object only keeps the rows honest and knows
// when the last asynchronous provider has answered.
//
// Steps that do not depend on each other run together: the owner calls
// begin() before asking a provider and finish() when it answers; launched()
// after starting every step. `launching` holds the settle back until then,
// so a provider that answers at once cannot end the transaction early.
QtObject {
    id: root
    property var registry: []           // [{id, label, hud, restored, enabled}]
    property var steps: []              // [{id, label, hud, restored, state, detail}]
    property string phase: "idle"       // idle | capture | apply | active | restore
    property bool busy: false
    property int outstanding: 0
    property bool launching: false
    signal settled()

    readonly property int activeCount: steps.filter(s => s.state === "active").length
    readonly property int totalCount: steps.filter(s => s.state === "active" || s.state === "failed").length
    readonly property var failures: steps.filter(s => s.state === "failed")
    // Progress for a panel: rows that will be attempted, and rows that are done.
    readonly property int plannedCount: steps.filter(s => ["pending", "applying", "active", "failed", "restored"].includes(s.state)).length
    readonly property int readyCount: steps.filter(s => s.state === "active" || s.state === "restored").length
    readonly property real progress: plannedCount ? readyCount / plannedCount : 0

    function entry(id) { return registry.find(r => r.id === id) || null; }
    function stepIndex(id) { return steps.findIndex(s => s.id === id); }
    function stepState(id) { const at = stepIndex(id); return at >= 0 ? steps[at].state : ""; }
    function setStep(id, state, detailText) {
        const next = steps.slice(), at = stepIndex(id), reg = entry(id);
        const row = { id: id, label: reg ? reg.label : id, hud: reg ? reg.hud : id, restored: reg ? reg.restored : id, state: state, detail: detailText || "" };
        if (at >= 0) next[at] = row; else next.push(row);
        steps = next;
    }
    // Rows are built from the registry: enabled entries wait, the rest are
    // marked off. `ids` limits a restore to the rows that were attempted.
    function start(nextPhase, ids) {
        const rows = (ids ? registry.filter(r => ids.includes(r.id)) : registry).map(r => ({
            id: r.id, label: r.label, hud: r.hud, restored: r.restored,
            state: ids || r.enabled ? "pending" : "off", detail: ids || r.enabled ? "" : "Turned off in Settings" }));
        steps = rows;
        run(nextPhase);
    }
    // Enter a phase without rebuilding the rows (capture → apply, or a crash restore).
    function run(nextPhase) { busy = true; phase = nextPhase; launching = true; outstanding = 0; }
    function begin() { outstanding++; }
    function finish() { outstanding = Math.max(0, outstanding - 1); if (!launching && outstanding === 0 && busy && phase !== "capture") settle(); }
    function launched() { launching = false; if (outstanding === 0 && busy) settle(); }
    function settle() {
        phase = phase === "restore" ? "idle" : "active";
        busy = false; launching = false;
        settled();
    }
    function reset() { steps = []; phase = "idle"; busy = false; launching = false; outstanding = 0; }
}
