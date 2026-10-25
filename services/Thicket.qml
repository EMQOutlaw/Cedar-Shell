pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import ".."
import "../components"

// The Thicket: a one-gesture panic privacy posture. engage() runs APPLY over
// an explicit registry of holds — radio off, microphone muted, do-not-disturb,
// lock-screen privacy — verifies each one really took, and only then locks.
// The lock is always the final hold and is never rolled back: you open the
// gate yourself. If any hold fails verification the rest are restored before
// the gate closes; the desktop never half-hides.
//
// The captured pre-Thicket values are written to ~/.local/state/cedar/
// thicket.json before anything is applied, so a shell that dies while
// sheltered comes back engaged and release() still puts the desktop back.
Singleton {
    id: root
    property bool engaged: false
    property double engagedAt: 0
    property string error: ""
    property var captured: ({})
    property alias busy: tx.busy
    property alias phase: tx.phase     // idle | apply | restore
    property alias steps: tx.steps     // [{id, label, hud, restored, state, detail}]
    readonly property int heldCount: steps.filter(s => s.state === "active").length
    readonly property string summary: busy
        ? (phase === "restore" ? "Stepping out…" : "Stepping into the brush…")
        : engaged ? "Sheltered · all quiet" : "5 holds armed"

    // Order matters: lock is the final hold and can never be rolled back.
    readonly property var registry: [
        { id: "radio",   label: "Network radio",       hud: "Network off",           restored: "Network restored",      enabled: true },
        { id: "mic",     label: "Microphone",           hud: "Microphone muted",      restored: "Microphone restored",   enabled: true },
        { id: "dnd",     label: "Do not disturb",       hud: "Notices held",          restored: "Notices restored",      enabled: true },
        { id: "privacy", label: "Lock-screen privacy",  hud: "Notice bodies blanked", restored: "Lock screen restored",  enabled: true },
        { id: "lock",    label: "Lock",                 hud: "The gate holds",        restored: "The gate opened",       enabled: true }
    ]
    Transaction { id: tx; registry: root.registry; onSettled: root.settle() }
    function stepState(id) { return tx.stepState(id); }
    function setStep(id, state, detailText) { tx.setStep(id, state, detailText); }

    function toggle() { if (busy) return; if (engaged) release(); else engage(); }

    // ---------------------------------------------------------------- engage
    function engage() {
        if (engaged || busy || ShellState.locked) return;
        error = "";
        tx.start("apply");
        captured = {
            micMuted: Audio.microphone ? Audio.microphone.muted : null,
            wireless: (Network.data && Network.data.available) ? Network.data.enabled : null,
            dndWas: Config.saved.doNotDisturb,
            privacyWas: Config.saved.lockPrivacy
        };
        engagedAt = Date.now(); persist();
        // radio: async through the network helper, verified on the next snapshot
        if (Config.testMode) setStep("radio", "unavailable", "No network provider in test mode");
        else if (captured.wireless === null) setStep("radio", "unavailable", "Network status is not answering");
        else if (captured.wireless === false) setStep("radio", "active", "The radio was already off");
        else { setStep("radio", "applying", "Switching the radio off"); Network.run({ action: "radio", enabled: false }); }
        // microphone: idempotent set, never a toggle
        if (!Audio.microphone) setStep("mic", "unavailable", "No microphone on this machine");
        else if (Audio.microphone.muted) setStep("mic", "active", "Already muted");
        else { Audio.microphone.muted = true; setStep("mic", Audio.microphone.muted ? "active" : "failed", Audio.microphone.muted ? "Muted at the source" : "The mute did not take"); }
        // do-not-disturb + lock privacy: Config keys through the ownership stack
        const tookDnd = Overrides.apply("doNotDisturb", "thicket", true);
        setStep("dnd", tookDnd ? "active" : "failed", tookDnd ? "Notices wait outside" : "The setting did not take");
        const tookPrivacy = Overrides.apply("lockPrivacy", "thicket", true);
        setStep("privacy", tookPrivacy ? "active" : "failed", tookPrivacy ? "The lock screen says nothing" : "The setting did not take");
        // the gate closes only after the four holds verify
        verifyHold.restart();
    }
    Timer { id: verifyHold; interval: 700; onTriggered: root.verify() }
    function verify() {
        if (phase !== "apply" || engaged) return;
        if (stepState("radio") === "applying") {
            const off = Network.data && Network.data.available && Network.data.enabled === false;
            setStep("radio", off ? "active" : "failed", off ? "Nothing leaves the machine" : (Network.error || "The radio is still on"));
        }
        const failed = steps.filter(s => ["radio", "mic", "dnd", "privacy"].includes(s.id) && s.state === "failed");
        if (failed.length) {
            error = failed.map(f => f.label).join(" and ") + " could not be held — everything was restored.";
            tx.start("restore", ["radio", "mic", "dnd", "privacy"]);
            restoreHolds();
            engaged = false; engagedAt = 0; store.setText("");
            tx.launched();
            return;
        }
        setStep("lock", "active", "Trailwatch keeps the gate");
        engaged = true; persist();
        tx.launched();
        if (!Config.testMode) ShellState.lock(false);
    }

    // ---------------------------------------------------------------- leave
    function release() {
        if (!engaged || busy) return;
        error = "";
        tx.start("restore", ["radio", "mic", "dnd", "privacy", "lock"]);
        setStep("lock", "restored", "You opened the gate");
        restoreHolds();
        engaged = false; engagedAt = 0; store.setText("");
        tx.launched();
    }
    function restoreHolds() {
        const p = Overrides.restore("lockPrivacy", "thicket");
        setStep("privacy", p.ok ? "restored" : "failed", !p.ok ? "The setting did not take" : p.restore ? "The lock screen can speak again" : Overrides.reasonText(p.reason));
        const d = Overrides.restore("doNotDisturb", "thicket");
        setStep("dnd", d.ok ? "restored" : "failed", !d.ok ? "The setting did not take" : d.restore ? "Notices show again" : Overrides.reasonText(d.reason));
        if (captured.micMuted === null || captured.micMuted === true) setStep("mic", "restored", "Microphone as before");
        else if (!Audio.microphone) setStep("mic", "failed", "No microphone to unmute");
        else { Audio.microphone.muted = false; setStep("mic", !Audio.microphone.muted ? "restored" : "failed", !Audio.microphone.muted ? "The microphone listens again" : "The unmute did not take"); }
        if (Config.testMode || captured.wireless !== true) setStep("radio", "restored", "Radio as before");
        else { setStep("radio", "applying", "Switching the radio back on"); Network.run({ action: "radio", enabled: true }); verifyRelease.restart(); }
    }
    Timer { id: verifyRelease; interval: 700; onTriggered: {
        const on = Network.data && Network.data.available && Network.data.enabled === true;
        root.setStep("radio", on ? "restored" : "failed", on ? "The machine is reachable again" : (Network.error || "The radio is still off"));
    } }

    function settle() { if (!engaged) store.setText(""); }

    // ------------------------------------------------------- state file
    function persist() { store.setText(JSON.stringify({ engaged: true, engagedAt: engagedAt, captured: captured }) + "\n"); }
    FileView {
        id: store
        path: Config.stateDir + "/thicket.json"
        atomicWrites: true
        printErrors: false
    }
    Component.onCompleted: {
        if (Config.testMode) return;
        let saved = null;
        try { saved = JSON.parse(store.text() || "null"); } catch (_) { saved = null; }
        if (saved && saved.engaged && saved.captured) {
            // The previous shell died in the brush: come back engaged so the
            // user leaves deliberately, with the captured values restored.
            captured = saved.captured; engagedAt = saved.engagedAt || Date.now();
            if (captured.dndWas !== undefined) Overrides.hold("doNotDisturb", "thicket", captured.dndWas, true);
            if (captured.privacyWas !== undefined) Overrides.hold("lockPrivacy", "thicket", captured.privacyWas, true);
            engaged = true;
        }
    }
}
