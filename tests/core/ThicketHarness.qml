import QtQuick
import Quickshell
import "../.."
import "../../services"

ShellRoot {
    FloatingWindow {
        id: window
        visible: true
        implicitWidth: 640
        implicitHeight: 480
        color: Theme.background
        property int step: 0
        function check(ok, msg) {
            if (!ok) { console.error("FAIL: " + msg); Qt.exit(1); }
        }
        Component.onCompleted: timer.start()
        Timer {
            id: timer
            interval: 250
            onTriggered: {
                if (window.step === 0) {
                    // Fresh config: dnd off, lockPrivacy on (the defaults).
                    window.check(!Config.saved.doNotDisturb && Config.saved.lockPrivacy, "fixture defaults");
                    window.check(!Thicket.engaged && !Thicket.busy, "Thicket starts disarmed");
                    window.check(Thicket.registry.length === 5 && Thicket.registry[4].id === "lock", "Lock is the final hold");
                    Thicket.engage();
                    window.check(Thicket.busy, "engage starts the transaction");
                    window.step++; timer.restart();
                } else if (window.step === 1) {
                    // verifyHold fires at 700 ms; at ~950 ms the gate is closed.
                    if (Thicket.busy || !Thicket.engaged) { timer.restart(); return; }
                    window.check(Thicket.engaged, "engaged after verification");
                    window.check(Config.saved.doNotDisturb === true, "dnd held");
                    window.check(Config.saved.lockPrivacy === true, "lock privacy held");
                    window.check(Thicket.stepState("radio") === "unavailable", "radio unavailable in test mode");
                    window.check(Thicket.stepState("dnd") === "active" && Thicket.stepState("privacy") === "active", "config holds active");
                    window.check(Thicket.stepState("lock") === "active", "gate closed last");
                    window.check(!ShellState.locked, "test mode never really locks");
                    window.check(Thicket.engagedAt > 0, "engagedAt recorded");
                    window.step++; timer.restart();
                } else if (window.step === 2) {
                    Thicket.release();
                    // In test mode every restore is synchronous: busy settles
                    // inside the call, so only the outcome is assertable.
                    window.step++; timer.restart();
                } else if (window.step === 3) {
                    if (Thicket.busy) { timer.restart(); return; }
                    window.check(!Thicket.engaged, "released");
                    window.check(Config.saved.doNotDisturb === false, "dnd restored");
                    window.check(Config.saved.lockPrivacy === true, "lock privacy restored to its default");
                    window.check(Thicket.stepState("lock") === "restored", "gate row reads restored");
                    window.check(Thicket.summary === "5 holds armed", "summary rearms");
                    // A manual change while held is respected on the way out:
                    // hold dnd via engage, flip it off as the user would, and
                    // release must NOT force it back on.
                    Thicket.engage();
                    window.step++; timer.restart();
                } else if (window.step === 4) {
                    if (Thicket.busy || !Thicket.engaged) { timer.restart(); return; }
                    Config.set("doNotDisturb", false);   // the user's own change
                    Thicket.release();
                    window.step++; timer.restart();
                } else if (window.step === 5) {
                    if (Thicket.busy) { timer.restart(); return; }
                    window.check(Config.saved.doNotDisturb === false, "user change during shelter is respected");
                    console.log("PASS: Thicket engage, verify, release, and ownership respect");
                    Qt.quit();
                }
            }
        }
    }
}
