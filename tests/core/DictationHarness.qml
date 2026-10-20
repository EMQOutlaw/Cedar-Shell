import QtQuick
import Quickshell
import "../.."
import "../../services"

// check_settings_service.py supplies a fake voxtype on PATH. No microphone,
// real daemon, transcripts or system configuration are accessed.
ShellRoot {
    property int phase: 0
    property int ticks: 0
    function check(ok, label) { if (!ok) { console.error("FAIL: " + label); Qt.exit(1); } }
    Timer {
        interval: 25; repeat: true; running: true
        onTriggered: {
            ticks++;
            check(ticks < 200, "Dictation fixture finishes in time");
            if (phase === 0) {
                if (!Dictation.checked || !Dictation.daemon) return;
                check(Dictation.installed && Dictation.state === "idle", "probe reads fake daemon status");
                Dictation.applyState("recording");
                check(Dictation.recording && Dictation.active, "recording state is active");
                Dictation.daemon = false;
                check(!Dictation.active && Dictation.state === "", "daemon loss clears stale activity");
                Dictation.applyState("transcribing");
                Dictation.applyState("invalid-state");
                check(!Dictation.daemon && !Dictation.active, "invalid state clears stale activity");
                Dictation.applyState("idle");
                ShellState.locked = true;
                check(!Dictation.start() && !Dictation.stop() && !Dictation.toggle(), "lock refuses record commands");
                ShellState.locked = false;
                check(Dictation.start(), "start is accepted while available");
                // The fake start takes 150ms. The recording isn't visible yet.
                ShellState.locked = true;
                phase = 1; ticks = 0;
            } else if (phase === 1 && ticks >= 40) {
                check(!Dictation.active && Dictation.state === "idle", "lock cancels a start that finishes after locking");
                check(!Dictation.available && !Dictation.start(), "recording stays refused while locked");
                ShellState.locked = false;
                console.log("PASS: Dictation state, daemon loss, command guards and in-flight lock cancellation");
                Qt.quit();
            }
        }
    }
    Component.onCompleted: { Config.set("coreDictation", false); Dictation.refresh(); }
}
