import QtQuick
import Quickshell
import "../.."
import "../../modules"
import "../../services"

// The production CoreWindow bindings over a covered output while dictating.
// Run by tests/check_surface_policy.py with CoreWindow rewritten to a plain
// window (no layer shell offscreen); the bindings under test are untouched.
ShellRoot {
    id: test
    property int failures: 0
    function check(value, message) {
        if (!value) { failures++; console.error("FAIL: " + message); }
    }
    function findFilament(item) {
        if (!item) return null;
        if (item.objectName === "coreDictation") return item;
        for (let i = 0; i < item.children.length; i++) {
            const found = findFilament(item.children[i]);
            if (found) return found;
        }
        return null;
    }
    // Covered output (fullscreen window / Gaming Mode) while dictating: the
    // production CoreWindow bindings must keep the whole, input-taking pill
    // down and show only the ember dot; a warranted alert still brings the
    // pill back; the lock hides everything. And the audio bridge is wanted
    // only while a filament is actually live to draw the levels.
    CoreWindow { id: core; modelData: Quickshell.screens[0] }
    function step9_coveredDictation() {
        Config.saved.barPlacement = "top";
        ShellState.close();
        check(core.visible && core.pillShown && !core.covered, "uncovered: the pill shows");
        Config.fullscreenScreen = Quickshell.screens[0].name;
        Config.fullscreenFocused = true;
        check(core.covered, "a fullscreen window covers the output");
        check(!core.visible, "covered and idle: no pill at all");
        Dictation.applyState("recording");
        check(core.covered && !core.pillShown, "covered + dictation: the whole pill stays down");
        check(core.emberDot && core.visible, "covered + dictation: only the ember dot is mapped");
        check(core.inputRegionEmpty, "covered + dictation: the window takes no input");
        check(Dictation.levelConsumers === 0 && !Dictation.levelsWanted, "no live filament anywhere: the audio bridge is not wanted (" + Dictation.levelConsumers + ")");
        // The filament inside this very window (mapped for the dot) is dark:
        // its surface is hidden, so it is not live, not painting, not sweeping.
        const inner = findFilament(core.contentItem);
        check(inner !== null, "the pill's own filament exists inside the mapped window");
        check(inner && !inner.live && !inner.painting && !inner.sweeping && !inner.attached, "covered: the pill's filament inside the mapped window does not animate or consume levels");
        // A warranted alert (another high-priority announcement) still raises the pill.
        check(CoreService.publish({ id: "test/alert", type: "warning", priority: "high", title: "Battery critical", announce: true, timeout: 4000 }), "publish a warranted alert");
        check(core.pillShown && !core.emberDot && !core.inputRegionEmpty, "a warranted alert brings the pill over the cover and takes input");
        CoreService.remove("test/alert", false);
        check(!core.pillShown && core.emberDot, "alert gone: back to the dot");
        Dictation.applyState("transcribing");
        check(!core.pillShown && core.emberDot, "transcribing under cover: still the dot");
        ShellState.locked = true;
        check(!core.visible, "locked: nothing mapped");
        ShellState.locked = false;
        Config.fullscreenFocused = false; Config.fullscreenScreen = "";
        check(core.pillShown && !core.inputRegionEmpty, "uncovered again: the pill returns and takes input");
        // With the pill uncovered the filament is live inside it and the bridge is wanted.
        Dictation.applyState("recording");
        check(Dictation.levelConsumers >= 1 && Dictation.levelsWanted, "a live filament wants the levels (" + Dictation.levelConsumers + ")");
        Dictation.applyState("idle");
        check(!Dictation.levelsWanted, "idle: levels not wanted");
        // The Core pill is Strata-only. Beside the left bar there is no Core
        // surface at all: the service stays enabled for the stack/timer, but
        // nothing maps and the covered/dot logic has nothing to own.
        Config.saved.barPlacement = "understory";
        check(CoreService.enabled && Config.barVertical, "Core stays enabled with the bar on the left");
        check(!CoreService.available, "no Core pill in Understory: not floating, not docked, nothing");
        check(!core.visible, "the Core window does not map when the bar is on the left");
        Config.saved.barPlacement = "top";
    }
    Timer {
        interval: 700; running: true
        onTriggered: {
            try { test.step9_coveredDictation(); } catch (e) { test.failures++; console.error("FAIL: exception " + e); }
            if (test.failures === 0) console.log("PASS: covered core");
            else console.error("FAIL: " + test.failures + " covered core checks");
            Qt.exit(test.failures === 0 ? 0 : 1);
        }
    }
}
