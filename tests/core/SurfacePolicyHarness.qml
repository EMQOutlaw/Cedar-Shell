import QtQuick
import Quickshell
import "../.."
import "../../services"
import "../../components/core"
import "../../modules"

// Surface policy over the test services (no daemons, no compositor):
//  - Core stays enabled under both bar placements and floats beside the
//    Understory bar, centred in the usable area;
//  - a placement switch keeps the activity stack and the timer;
//  - one interactive surface: Core hub, Canopy (pinned or not), Understory and
//    Settings dismiss each other; the resting pill may stay;
//  - lock clears everything and nothing reopens on unlock;
//  - dictation has one presenter per placement.
ShellRoot {
    id: test
    property int failures: 0
    function check(value, message) {
        if (!value) { failures++; console.error("FAIL: " + message); }
    }
    function named(item, name) { if (item.objectName === name) return item; for (const child of item.children || []) { const found = named(child, name); if (found) return found; } return null; }
    function screenWidth() { return CoreService.hostScreen ? CoreService.hostScreen.width : 0; }
    function screenHeight() { return CoreService.hostScreen ? CoreService.hostScreen.height : 0; }
    // The pill is Strata (top-bar) ONLY. Under the Understory (left) bar no Core
    // surface exists at all: no host window (CoreHost's model is empty), no
    // available pill, no hub, and OSD ownership stays with the legacy OSD. The
    // service itself stays alive so activities and the timer are unaffected.
    function step1_coreStrataOnly() {
        check(Config.saved.barPlacement === "top", "starts with the top bar");
        check(CoreService.enabled && CoreService.available, "Core enabled and available under the top bar");
        check(!Config.barVertical, "top bar");
        check(CoreService.placement.left === Math.round((screenWidth() - CoreService.placement.width) / 2), "integrated pill centred on the monitor (" + JSON.stringify(CoreService.placement) + ")");
        Config.saved.barPlacement = "understory";
        check(Config.barVertical, "placement switched to the Understory");
        check(CoreService.enabled, "the Core service stays alive with the bar on the left (activities and timer keep running)");
        check(!CoreService.available, "no Core pill under the Understory bar: not floating, not docked, nothing");
        check(CoreService.hostScreen !== null, "the host output is still known for the next placement");
        // The dormant floating branch stays correct for a future placement:
        // docked just beside the bar, centred vertically on the output.
        const p = CoreService.placement;
        check(p.left >= Config.barWidth && p.left + p.width <= screenWidth(), "dormant floating rect stays inside the usable area (" + JSON.stringify(p) + ")");
        check(p.top === Math.round((screenHeight() - 40) / 2), "dormant floating rect is vertically centred (" + p.top + ")");
        // OSD ownership must not defer to a pill that does not exist.
        Config.saved.coreVolume = true;
        ShellState.osd("VOLUME", 0.5, "50%");
        check(ShellState.osdKind === "VOLUME", "a volume OSD is open");
        check(!CoreService.ownsOsd, "the legacy OSD owns volume while the bar is on the left");
        Config.saved.barPlacement = "top";
        ShellState.osd("VOLUME", 0.5, "50%");
        check(CoreService.ownsOsd, "the pill owns volume again under the top bar");
        ShellState.osdOpen = false;
        ShellState.osdKind = "";
    }
    function step2_stateSurvivesSwitches() {
        check(CoreService.publish({ id: "test/retained", type: "warning", title: "Retained", persistent: true, timeout: 0 }), "publish a persistent activity");
        CoreService.timer.start(600, "Kettle");
        check(CoreService.timer.active, "timer running");
        for (let n = 0; n < 10; n++) {
            Config.saved.barPlacement = n % 2 === 0 ? "understory" : "top";
            check(CoreService.rows.some(r => r.id === "test/retained"), "activity survives placement switch " + n);
            check(CoreService.timer.active, "timer survives placement switch " + n);
            check(CoreService.enabled, "Core enabled after switch " + n);
        }
        check(Config.saved.barPlacement === "top", "back on the top bar");
        // Publication while vertical, not merely survival: new events are
        // accepted, the hub keeps its selection, the timer its remaining time.
        Config.saved.barPlacement = "understory";
        check(CoreService.publish({ id: "test/vertical", type: "warning", title: "Published beside the left bar", persistent: true, timeout: 0 }), "publish is accepted while the bar is on the left");
        check(CoreService.rows.some(r => r.id === "test/vertical"), "the event is in the stack, not dropped");
        CoreService.expand("test/vertical");
        check(!CoreService.expanded && ShellState.panel === "" && !CoreService.available, "no Core surface while the bar is on the left: the hub cannot open");
        check(CoreService.model.selectedId === "", "no selection without a surface");
        const remaining = CoreService.timer.remaining;
        check(remaining > 0 && remaining <= 600, "timer has time left (" + remaining + ")");
        Config.saved.barPlacement = "top";
        check(!CoreService.expanded, "switching back does not resurrect a hub that never opened");
        check(Math.abs(CoreService.timer.remaining - remaining) <= 1 && CoreService.timer.label === "Kettle", "switching back keeps the timer's remaining time and label");
        check(CoreService.rows.some(r => r.id === "test/vertical") && CoreService.rows.some(r => r.id === "test/retained"), "both stacks' rows present after the round trip");
        CoreService.expand("test/vertical");
        check(CoreService.expanded && CoreService.model.selectedId === "test/vertical", "the hub opens normally once the bar is back on top");
        CoreService.collapse();
        CoreService.remove("test/vertical", false);
        CoreService.timer.cancel();
        CoreService.remove("test/retained", false);
    }
    function step3_singleSurface() {
        // Pinned Canopy yields to the Understory.
        Canopy.open("quick"); Canopy.pin();
        check(Canopy.shown && Canopy.pinned, "Canopy open and pinned");
        Understory.open();
        check(ShellState.panel === "understory", "Understory took the panel");
        check(!Canopy.shown, "pinned Canopy is dismissed by the Understory");
        check(!Canopy.pinned, "the pin is released with it");
        check(CoreService.available, "the resting pill may stay beside an open Understory");
        check(!CoreService.expanded, "but the hub is closed");
        check(ShellState.surfaceOwner() === "understory", "owner is the Understory (" + ShellState.surfaceOwner() + ")");
        // Core hub takes over from the Understory, and from a pinned Canopy.
        CoreService.expand();
        check(CoreService.expanded && !Understory.shown, "Core hub displaces the Understory");
        check(ShellState.surfaceOwner() === "core", "owner is Core");
        Canopy.open("quick"); Canopy.pin();
        check(!CoreService.expanded, "Canopy displaces the hub");
        CoreService.expand();
        check(!Canopy.shown && !Canopy.pinned, "Core hub dismisses a pinned Canopy");
        // Settings is a window, yet still one surface among the others.
        Canopy.open("quick"); Canopy.pin();
        ShellState.open("settings");
        check(SettingsService.windowOpen, "Settings opened");
        check(ShellState.panel === "" && !Canopy.shown && !Canopy.pinned, "Settings dismisses the pinned Canopy (" + ShellState.panel + ")");
        check(ShellState.surfaceOwner() === "settings", "owner is Settings");
        Understory.open();
        check(!SettingsService.windowOpen, "the Understory dismisses Settings");
        ShellState.open("settings");
        check(!Understory.shown, "Settings dismisses the Understory");
        CoreService.expand();
        check(!SettingsService.windowOpen && CoreService.expanded, "the Core hub dismisses Settings");
        SettingsService.closeApp(); ShellState.close();
        check(ShellState.surfaceOwner() === "", "nothing owns the surface");
        // Closing never reopens something else.
        Canopy.open("quick"); Canopy.pin(); Canopy.close();
        check(!Canopy.shown && !Canopy.pinned && ShellState.panel === "", "close releases the pin, nothing else appears");
    }
    // The central policy settles in one move: one panel change and one Settings
    // change per transition, no close/open bounce between the two Connections.
    property int panelChanges: 0
    property int settingsChanges: 0
    Connections { target: ShellState; function onPanelChanged() { test.panelChanges++; } }
    Connections { target: SettingsService; function onWindowOpenChanged() { test.settingsChanges++; } }
    function transition(label, act, panels, settings) {
        panelChanges = 0; settingsChanges = 0;
        act();
        check(panelChanges === panels && settingsChanges === settings, label + " settles in one move (panel x" + panelChanges + ", settings x" + settingsChanges + ")");
    }
    function step3b_noBounce() {
        ShellState.close(); SettingsService.closeApp();
        transition("Canopy open", () => Canopy.open("quick"), 1, 0);
        transition("pin", () => Canopy.pin(), 0, 0);
        transition("pinned Canopy -> Settings", () => ShellState.open("settings"), 1, 1);
        transition("Settings -> Understory", () => Understory.open(), 1, 1);
        transition("Understory -> Core hub", () => CoreService.expand(), 1, 0);
        transition("Core hub -> Settings", () => ShellState.open("settings"), 1, 1);
        transition("Settings closed by itself", () => SettingsService.closeApp(), 0, 1);
        transition("Settings open with nothing else", () => ShellState.open("settings"), 0, 1);
        transition("Settings -> Canopy", () => Canopy.open("quick"), 1, 1);
        transition("close", () => Canopy.close(), 1, 0);
        check(ShellState.surfaceOwner() === "", "settled on no owner");
        // Stale outside-click callbacks (a focus grab cleared after another
        // surface already took the panel) must not close the new owner.
        Canopy.open("quick");
        Understory.open();
        Canopy.close(); // the Canopy window's onCleared path
        check(ShellState.panel === "understory", "stale Canopy outside-click leaves the Understory in place");
        Canopy.open("quick");
        Understory.close(); // the Understory window's onCleared path, late
        check(ShellState.panel === "canopy", "stale Understory outside-click leaves the Canopy in place");
        CoreService.expand();
        Canopy.close(); Understory.close();
        check(CoreService.expanded, "stale closes leave the Core hub in place");
        CoreService.collapse();
        check(ShellState.panel === "", "hub collapsed");
    }
    function step4_lock() {
        // Lock from each owner state: every owner releases, nothing reopens.
        const owners = [
            ["core hub", () => CoreService.expand()],
            ["understory", () => Understory.open()],
            ["canopy", () => Canopy.open("quick")],
            ["pinned canopy", () => { Canopy.open("quick"); Canopy.pin(); }],
            ["settings", () => ShellState.open("settings")]
        ];
        for (const [name, open] of owners) {
            open();
            check(ShellState.surfaceOwner() !== "", name + " owns the surface before the lock (" + ShellState.surfaceOwner() + ")");
            ShellState.locked = true;
            check(ShellState.panel === "" && !Canopy.shown && !Canopy.pinned && !Understory.shown && !SettingsService.windowOpen && !CoreService.expanded && !CoreService.available && ShellState.surfaceOwner() === "", "lock from " + name + " clears every surface");
            ShellState.locked = false;
            check(ShellState.panel === "" && !Canopy.shown && !Understory.shown && !SettingsService.windowOpen && ShellState.surfaceOwner() === "", "unlock after " + name + " reopens nothing");
        }
        // Everything at once.
        Canopy.open("quick"); Canopy.pin();
        ShellState.open("settings");
        Understory.open();
        ShellState.locked = true;
        check(ShellState.panel === "" && !Canopy.shown && !Canopy.pinned && !Understory.shown && !SettingsService.windowOpen && !CoreService.available, "lock clears every surface");
        ShellState.locked = false;
        check(ShellState.panel === "" && !Canopy.shown && !Canopy.pinned && !Understory.shown && !SettingsService.windowOpen, "nothing reopens on unlock");
        check(CoreService.available, "the pill returns after unlock");
        // Explicit dismiss then toggle from the same control (the R3 sequence,
        // at the service level): a dismissal that already closed the surface
        // leaves one toggle meaning "open", and a second toggle closes it. The
        // compositor-side race (grab cleared by the control's own click) is the
        // window's HyprlandFocusGrab window list, checked by its own harness.
        Understory.open();
        Understory.close();                 // outside-click / Escape dismissal
        check(!Understory.shown && ShellState.panel === "", "dismissed");
        Understory.toggle();
        check(Understory.shown, "toggle after a dismissal opens once");
        Understory.toggle();
        check(!Understory.shown && ShellState.panel === "", "toggle again closes; no reopen loop");
        Canopy.open("quick");
        Canopy.close();
        Canopy.toggleTopic("quick");
        check(Canopy.shown, "Canopy toggle after dismissal opens once");
        Canopy.toggleTopic("quick");
        check(!Canopy.shown && ShellState.panel === "", "Canopy toggle again closes");
    }
    function step5_dictationPresenter() {
        Config.saved.barPlacement = "top";
        check(Dictation.presenter === "core", "top bar: the pill presents dictation (" + Dictation.presenter + ")");
        Config.saved.barPlacement = "understory";
        check(CoreService.enabled, "Core is still enabled beside the left bar");
        check(Dictation.presenter === "understory", "Understory bar: the bar's own filament presents, never a Core pill that does not exist (" + Dictation.presenter + ")");
        Config.saved.coreEnabled = false;
        check(!CoreService.enabled, "Core off");
        check(Dictation.presenter === "understory", "Understory without Core: the bar filament presents (" + Dictation.presenter + ")");
        Config.saved.barPlacement = "top";
        check(Dictation.presenter === "", "top bar without Core: no presenter (" + Dictation.presenter + ")");
        Config.saved.coreEnabled = true;
        Config.saved.coreDictation = false;
        check(Dictation.presenter === "", "dictation hidden from Core: no presenter");
        Config.saved.coreDictation = true;
        check(Dictation.presenter === "core", "restored");
        ShellState.locked = true;
        check(Dictation.presenter === "", "nobody presents while locked");
        ShellState.locked = false;
        check(Dictation.presenter === "core", "presenter returns after unlock");
    }
    function step6_reducedMotion() {
        Config.saved.reducedMotion = true;
        Understory.enter(); Canopy.enter();
        check(Understory.reveal === 1 && Canopy.reveal === 1, "Reduced Motion snaps the entrances");
        Config.saved.reducedMotion = false;
    }
    // A covered pill (fullscreen window, Gaming Mode) keeps one ember dot for
    // any capture. Dictation is a capture too: its row must count, so the
    // indication is never lost behind a game while the microphone is live.
    function step7_dictationCounted() {
        check(!CoreService.capturing, "nothing is capturing at rest");
        Dictation.applyState("recording");
        check(Dictation.active && CoreService.rows.some(r => r.id === "dictation"), "dictation publishes its Core row");
        check(CoreService.capturing, "dictation counts as a capture for the covered-pill ember dot");
        // Fullscreen/Gaming respect: the user started dictation themself, so the
        // row never raises an attention alert; a covered pill stays covered and
        // shows only the ember dot, never the whole pill over a game.
        const row = CoreService.rows.find(r => r.id === "dictation");
        check(row && row.attentionUntil <= CoreService.model.now, "dictation row raises no attention alert (attentionUntil " + (row && row.attentionUntil) + ")");
        Dictation.applyState("transcribing");
        check(CoreService.capturing, "still counted while transcribing");
        Dictation.applyState("idle");
        check(!CoreService.capturing, "released when Voxtype is idle");
        Config.saved.coreDictation = false;
        Dictation.applyState("recording");
        check(!CoreService.rows.some(r => r.id === "dictation") && !CoreService.capturing, "dictation hidden from Core publishes nothing");
        Dictation.applyState("idle");
        Config.saved.coreDictation = true;
    }
    // R4: the filament's repaint timer, elapsed tick and travelling light run
    // only while its host window is actually on screen. A pill hidden by a
    // fullscreen window, Gaming Mode, the lock or an unavailable Core must not
    // keep a 33 ms timer alive, whatever its item `visible` says.
    FloatingWindow {
        id: dictationHost
        visible: false
        implicitWidth: 320; implicitHeight: 60
        CoreDictation { id: filament; width: 280; height: 24 }
    }
    function step8_hiddenDictationRests() {
        Dictation.applyState("recording");
        check(Dictation.recording, "Voxtype listening");
        check(!filament.live && !filament.painting, "hidden host window: the filament is not live and does not repaint");
        check(Dictation.levelConsumers === 0, "hidden filament is no level consumer (" + Dictation.levelConsumers + ")");
        dictationHost.visible = true;
        check(filament.live && filament.painting, "shown host window: the filament is live and repaints");
        check(Dictation.levelConsumers === 1, "a window shown while already recording registers its filament (" + Dictation.levelConsumers + ")");
        dictationHost.visible = false;
        check(!filament.live && !filament.painting, "hiding the window stops the repaint timer at once");
        check(Dictation.levelConsumers === 0, "...and releases the level feed (" + Dictation.levelConsumers + ")");
        dictationHost.visible = true;
        ShellState.locked = true;
        check(!filament.live && !filament.painting, "locked: nothing animates even in a shown window");
        ShellState.locked = false;
        Dictation.applyState("transcribing");
        check(filament.live, "transcribing in a shown window is live");
        dictationHost.visible = false;
        check(!filament.live && !filament.sweeping, "hidden while transcribing: no travelling light");
        Dictation.applyState("idle");
        dictationHost.visible = true;
        check(!filament.live && !filament.painting, "idle: at rest");
        dictationHost.visible = false;
    }
    // Consumer accounting across a renderer swap while recording: the old
    // filament's destruction detaches it, the new host attaches exactly once,
    // and the final hide/destruction leaves 0 consumers and no bridge wanted.
    // (The Core host Variants in HostHarness is a virtual window record with no
    // CoreSurface, so a host reload there carries no filament; the teardown
    // under test here is the actual renderer item.)
    FloatingWindow { id: swapHost; visible: false; implicitWidth: 320; implicitHeight: 60 }
    Component { id: filamentFactory; CoreDictation { width: 280; height: 24 } }
    function step8b_consumerSwap() {
        dictationHost.visible = false;
        Dictation.applyState("recording");
        check(Dictation.levelConsumers === 0, "start: no consumers (" + Dictation.levelConsumers + ")");
        swapHost.visible = true;
        const a = filamentFactory.createObject(swapHost.contentItem);
        check(a.live && a.attached && Dictation.levelConsumers === 1, "first renderer attaches once (" + Dictation.levelConsumers + ")");
        a.destroy(); // renderer teardown (host swap / reload) while recording; deferred, checked next tick
    }
    function step8c_consumerSwapAfterTeardown() {
        check(Dictation.levelConsumers === 0, "destroyed renderer detached (" + Dictation.levelConsumers + ")");
        const b = filamentFactory.createObject(swapHost.contentItem);
        check(b.attached && Dictation.levelConsumers === 1 && Dictation.levelsWanted, "new host attaches exactly once and the bridge is wanted (" + Dictation.levelConsumers + ")");
        swapHost.visible = false;
        check(!b.attached && Dictation.levelConsumers === 0 && !Dictation.levelsWanted, "hiding the new host releases it; nothing wanted (" + Dictation.levelConsumers + ")");
        swapHost.visible = true;
        check(Dictation.levelConsumers === 1, "re-shown: one consumer again, not two (" + Dictation.levelConsumers + ")");
        Dictation.applyState("idle");
        check(Dictation.levelConsumers === 0 && !Dictation.levelsWanted, "idle releases (" + Dictation.levelConsumers + ")");
        Dictation.applyState("recording");
        check(Dictation.levelConsumers === 1, "recording again re-attaches once (" + Dictation.levelConsumers + ")");
        b.syncLevels(); b.syncLevels(); // repeated syncs for the same state must not double-count
        check(Dictation.levelConsumers === 1, "sync is idempotent (" + Dictation.levelConsumers + ")");
        b.destroy();
    }
    function step8d_consumerSwapFinal() {
        check(Dictation.levelConsumers === 0 && !Dictation.levelsWanted, "final destruction: 0 consumers, bridge not wanted (" + Dictation.levelConsumers + ")");
        Dictation.applyState("idle");
        swapHost.visible = false;
    }
    function step9_barButtonOpensStation() {
        // Owner correction (confirmed live 2026-10-25): the CEDAR mark opens
        // Field Station — the Canopy "station" drop, or the legacy "hud" when
        // the Canopy is off. It never opens the CEDAR Station diagnostics app
        // and never the Understory panel.
        const button = named(strataBar, "strataIdentity");
        check(button !== null, "the CEDAR identity button exists in the Strata bar");
        check(button.hint === "Field Station", "the CEDAR mark advertises Field Station");
        if (Config.stage >= 3) {
            button.clicked();
            if (Config.saved.canopyEnabled)
                check(Canopy.shown && Canopy.topic === "station", "CEDAR bar button opens the Field Station drop (Canopy 'station' topic: " + Canopy.topic + ")");
            else
                check(ShellState.panel === "hud", "CEDAR bar button opens Field Station (legacy hud) when the Canopy is off");
            check(!Station.windowOpen, "CEDAR bar button does not open the CEDAR Station diagnostics app");
            check(ShellState.panel !== "understory", "CEDAR bar button does not open Understory");
            check(button.checked === Config.saved.canopyEnabled, "the mark stays lit while Field Station is open");
            button.clicked();
            check(!Canopy.shown && ShellState.panel === "", "a second click closes Field Station again");
        } else {
            // Below stage 3 the mark opens the station topic in the hub instead.
            check(button.hint === "Field Station", "the mark still advertises Field Station below stage 3");
        }
    }
    // Phases: the synchronous policy steps, then the consumer-swap steps that
    // need the event loop between them (QObject.destroy is deferred).
    property int phase: 0
    function runSteps(steps) {
        for (const step of steps) {
            try { step(); } catch (e) { failures++; console.error("FAIL: exception " + e); }
        }
    }
    // The Strata bar, so the CEDAR mark's action can be exercised for real.
    StrataBarContents {
        id: strataBar
        output: Quickshell.screens[0]
    }
    Timer {
        interval: 700; running: true; repeat: true
        onTriggered: {
            if (test.phase === 0) test.runSteps([test.step1_coreStrataOnly, test.step2_stateSurvivesSwitches, test.step3_singleSurface, test.step3b_noBounce, test.step4_lock, test.step5_dictationPresenter, test.step6_reducedMotion, test.step7_dictationCounted, test.step8_hiddenDictationRests, test.step8b_consumerSwap, test.step9_barButtonOpensStation]);
            else if (test.phase === 1) test.runSteps([test.step8c_consumerSwapAfterTeardown]);
            else if (test.phase === 2) test.runSteps([test.step8d_consumerSwapFinal]);
            else {
                if (test.failures === 0) console.log("PASS: surface policy");
                else console.error("FAIL: " + test.failures + " surface policy checks");
                Qt.exit(test.failures === 0 ? 0 : 1);
            }
            test.phase++;
            interval = 150;
        }
    }
}
