pragma Singleton
import QtQuick
import Quickshell
import ".."
import "../components/core/OverrideStack.js" as Stack

// Who owns each managed desktop value right now. Desktop Profiles, Focus
// and Gaming Mode hold a key with the value they found and the value they
// applied; releases nest in any order and a manual change while a key is
// held is respected (see components/core/OverrideStack.js).
//
// Config-backed keys (do-not-disturb, idle lock, ambient intensity,
// performance mode, whispers) are written here through apply()/restore(),
// so a change that arrives any other way, from Settings, Quick Controls or
// IPC, is recorded as the user's own and the holder's release leaves it be.
// Keys owned by outside providers (power, nightlight, audioScene) are held
// and released here but written by their owners, who report external
// changes with external().
Singleton {
    id: root
    property var state: Stack.create()
    property bool writing: false
    readonly property var watched: ["doNotDisturb", "idleLockSeconds", "ambientIntensity", "performanceMode", "forestWhispers"]

    function hold(key, owner, previous, value) { state = Stack.hold(state, key, owner, previous, value); }
    function external(key, current) { state = Stack.external(state, key, current); }
    // Returns {restore, target, reason}; the caller writes `target` when `restore` is true.
    function release(key, owner) { const r = Stack.release(state, key, owner); state = r.state; return { restore: r.restore, target: r.target, reason: r.reason }; }
    function holder(key) { return Stack.holder(state, key); }
    function held(key, owner) { return Stack.held(state, key, owner); }
    function keysHeldBy(owner) { return Stack.keysHeldBy(state, owner); }
    function entry(key, owner) { return Stack.entry(state, key, owner); }
    function releaseAll(owner) { for (const key of keysHeldBy(owner)) release(key, owner); }

    // A Config-backed key: hold it and write it; true when the setting took.
    function apply(key, owner, value) {
        if (!(key in Config.saved)) return false;
        hold(key, owner, Config.saved[key], value);
        writing = true; Config.set(key, value); writing = false;
        return Config.saved[key] === value;
    }
    // Let go of a Config-backed key: {restore, reason, ok}. `ok` is whether
    // the written value read back; true when nothing had to be written.
    function restore(key, owner) {
        const r = release(key, owner);
        if (!r.restore) return { restore: false, reason: r.reason, ok: true };
        writing = true; Config.set(key, r.target); writing = false;
        return { restore: true, reason: r.reason, ok: Config.saved[key] === r.target };
    }
    function reasonText(reason) {
        return reason === "overridden" ? "Kept your own change" : reason === "nested" ? "Still held by another mode" : reason === "none" ? "Was not held" : "";
    }
    // Writes that did not come through apply()/restore() are the user's.
    Connections {
        target: Config.saved
        function onDoNotDisturbChanged() { if (!root.writing) root.external("doNotDisturb", Config.saved.doNotDisturb); }
        function onIdleLockSecondsChanged() { if (!root.writing) root.external("idleLockSeconds", Config.saved.idleLockSeconds); }
        function onAmbientIntensityChanged() { if (!root.writing) root.external("ambientIntensity", Config.saved.ambientIntensity); }
        function onPerformanceModeChanged() { if (!root.writing) root.external("performanceMode", Config.saved.performanceMode); }
        function onForestWhispersChanged() { if (!root.writing) root.external("forestWhispers", Config.saved.forestWhispers); }
    }
}
