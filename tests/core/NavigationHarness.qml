import QtQuick
import QtTest
import Quickshell
import Quickshell.Hyprland
import "../.."
import "../../components/core"
import "../../modules"
import "../../services"

ShellRoot {
    FloatingWindow {
        id: window
        visible: true
        implicitWidth: 1000
        implicitHeight: 900
        // The offscreen host supplies CanopyWindow's native Escape handler.
        contentItem.Keys.onEscapePressed: Canopy.close()
        CoreSurface {
            id: core
            x: 300
            y: 10
            maximumWidth: 460
            maximumHeight: 600
        }
        Loader {
            id: strata
            active: Config.barStyle === "cedar"
            x: 6
            y: 90
            width: window.width - 12
            height: Config.barHeight - 12
            sourceComponent: StrataBarContents { output: Quickshell.screens[0] }
        }
        CanopyPanel {
            id: canopy
            y: 240
            width: 480
            height: 650
            active: true
            visible: Canopy.shown
        }
        HyprlandFocusGrab { id: grab; windows: [window].concat(Canopy.controlWindows.filter(w=>w.visible)); active: false }
        TestCase {
            id: tests
            name: "Navigation"
            when: window.visible
            function named(item, name) {
                if (item.objectName === name)
                    return item;
                for (const child of item.children || []) {
                    const found = named(child, name);
                    if (found)
                        return found;
                }
                return null;
            }
            function click(item) {
                verify(item !== null);
                mouseClick(item, item.width / 2, item.height / 2);
                wait(20);
            }
            function test_navigation() {
                // Quick Controls and Connections now belong to the right rail.
                Config.set("barStyle", "cedar");
                Config.set("reducedMotion", true);
                Config.set("coreWarnings", false);
                Config.set("canopyEnabled", true);
                wait(100);
                Canopy.registerControls(window);
                Canopy.registerControls(window);
                compare(Canopy.controlWindows.length, 1);
                compare(grab.windows.length, 2);
                Canopy.unregisterControls(window);
                compare(Canopy.controlWindows.length, 0);
                const header = named(strata.item, "strataQuick"), network = named(strata.item, "strataNetwork");
                click(header);
                compare(Canopy.topic, "quick");
                verify(Canopy.shown);
                const volume = named(canopy, "quickVolume");
                verify(volume !== null);
                verify(!volume.visible, "Bar audio owns volume controls");
                click(header);
                verify(!Canopy.shown);
                for (const type of ["media", "network", "warning", "notification"]) {
                    CoreService.publish({
                        id: "fixture",
                        type: type,
                        title: "Fixture activity",
                        persistent: true
                    });
                    click(header);
                    compare(Canopy.topic, "quick");
                    verify(Canopy.shown);
                    click(header);
                    verify(!Canopy.shown);
                    CoreService.remove("fixture", false);
                }
                Network.data = {
                    available: true,
                    label: "Wired connection",
                    enabled: false,
                    hardware: false,
                    devices: [],
                    networks: [],
                    saved: [],
                    status: {
                        kind: "wired",
                        state: "connected",
                        internet: "unknown",
                        vpns: []
                    }
                };
                compare(Network.kind, "wired");
                compare(Network.fallbackGlyph, "E");
                click(network);
                compare(Canopy.topic, "network");
                verify(Canopy.shown);
                click(header);
                compare(Canopy.topic, "quick");
                header.forceActiveFocus();
                verify(header.activeFocus);
                keyClick(Qt.Key_Space);
                wait(20);
                verify(!Canopy.shown);
                keyClick(Qt.Key_Space);
                wait(20);
                verify(Canopy.shown);
                keyClick(Qt.Key_Escape);
                wait(20);
                verify(!Canopy.shown);
                network.forceActiveFocus();
                verify(network.activeFocus, "Connections accepts keyboard focus");
                ShellState.open("control");
                compare(Canopy.topic, "quick");
                compare(ShellState.panel, "canopy");
                ShellState.toggle("control");
                verify(!Canopy.shown);
                ShellState.open("power");
                compare(Canopy.topic, "power");
                compare(ShellState.panel, "canopy");
                wait(30);
                const session = named(canopy, "sessionControls");
                verify(session !== null);
                session.choose("reboot");
                compare(session.pending, "reboot");
                session.pending = "";
                Canopy.close();
                // Use the actual media preview and mouse delivery; no parent handler fires.
                CoreService.publish({
                    id: "media-fixture",
                    type: "media",
                    title: "Fixture track",
                    persistent: true
                });
                core.hovering = true;
                wait(100);
                const play = named(core, "coreMediaPlay");
                verify(play !== null);
                play.enabled = true;
                let pressed = 0;
                const record = () => {
                    pressed++;
                };
                play.clicked.connect(record);
                click(play);
                compare(pressed, 1);
                verify(!Canopy.shown);
                play.clicked.disconnect(record);
                CoreService.remove("media-fixture", false);
                core.hovering = false;
                ShellState.locked = true;
                click(header);
                click(network);
                Canopy.toggleQuick();
                Canopy.open("network");
                Canopy.pin();
                ShellState.open("control");
                verify(!Canopy.shown && !Canopy.pinned && ShellState.panel !== "canopy");
                ShellState.locked = false;
                Config.set("canopyEnabled", false);
                click(header);
                compare(ShellState.panel, "control");
                click(header);
                compare(ShellState.panel, "");
                console.log("PASS: consolidated navigation, real pointer/media events, focus, Escape and lock guards");
            }
            function test_strata_navigation() {
                Config.set("barStyle", "cedar");
                Config.set("coreEnabled", true);
                Config.set("canopyEnabled", true);
                Config.set("reducedMotion", true);
                ShellState.locked = false;
                Canopy.close();
                CoreService.collapse();
                wait(100);
                verify(strata.item !== null);
                verify(core.integrated);
                verify(!core.showNetwork, "Strata keeps network in the right rail");
                const header = named(core, "coreHeader");
                const quick = named(strata.item, "strataQuick");
                const network = named(strata.item, "strataNetwork");
                compare(header.hint, "Signals");
                click(header);
                verify(CoreService.expanded, "Center header opens Signals");
                verify(!Canopy.shown, "Signals does not open Quick Controls");
                click(header);
                verify(!CoreService.expanded);
                click(quick);
                compare(Canopy.topic, "quick");
                compare(Canopy.outputName, Quickshell.screens[0].name);
                verify(Canopy.shown, "Right Quick control opens Quick Controls");
                click(header);
                verify(CoreService.expanded && !Canopy.shown, "Center header switches Quick Controls to Signals");
                click(quick);
                verify(Canopy.shown && !CoreService.expanded, "Right Quick control switches Signals to Quick Controls");
                click(network);
                compare(Canopy.topic, "network");
                compare(Canopy.outputName, Quickshell.screens[0].name);
                verify(Canopy.shown);
                Canopy.close();
                header.forceActiveFocus();
                keyClick(Qt.Key_Return);
                wait(20);
                verify(CoreService.expanded && !Canopy.shown, "Keyboard header activation opens Signals");
                keyClick(Qt.Key_Escape);
                wait(20);
                verify(!CoreService.expanded && !Canopy.shown);
                ShellState.locked = true;
                click(header);
                click(quick);
                click(network);
                verify(!CoreService.expanded && !Canopy.shown, "Strata actions respect the lock guard");
                ShellState.locked = false;
                console.log("PASS: Strata Signals header and right-side Quick/Network pointer and keyboard routes");
            }
            function signalCheck(ok, message = "Signals assertion") {
                if (!ok) {
                    console.error("FAIL: " + message);
                    fail(message);
                }
            }
            function signalCompare(actual, expected, message) {
                signalCheck(actual === expected, message + ": " + actual + " != " + expected);
            }
            function test_unified_signals() {
                Config.set("barStyle", "cedar");
                Config.set("coreEnabled", true);
                ShellState.locked = false;
                Canopy.close();
                CoreService.collapse();
                const header = named(core, "coreHeader");
                const loader = named(core, "coreHubLoader");
                for (const reduced of [true, false]) {
                    Config.set("reducedMotion", reduced);
                    mouseMove(window.contentItem, 950, 850);
                    wait(800);
                    signalCheck(!loader.active, "Closed Signals unloads the hub");
                    CoreService.publish({ id: "unified-fixture", type: "integration", title: "Signal opening", persistent: true });
                    mouseMove(header, header.width / 2, header.height / 2);
                    wait(1000);
                    signalCheck(core.signalsOpen && !CoreService.expanded, "Hover opens the shared Signals panel: " + JSON.stringify({open: core.signalsOpen, hover: core.hovering, dismissed: core.hoverDismissed, pinned: CoreService.expanded, canopy: Canopy.shown, volume: core.volume, active: core.active, locked: ShellState.locked, headerHovered: header.hovered, headerWidth: header.width, width: core.width, height: core.height}));
                    signalCheck(loader.item !== null);
                    const hub = loader.item;
                    const height = core.height;
                    const width = core.width;
                    let resizes = 0;
                    const resized = () => { resizes++; };
                    core.heightChanged.connect(resized);
                    click(header);
                    wait(500);
                    signalCheck(CoreService.expanded, "Click pins the hovered panel");
                    signalCheck(loader.item === hub, "Pinning retains the same hub and controls");
                    signalCompare(core.height, height, "Pinning preserves panel height");
                    signalCompare(core.width, width, "Pinning preserves panel width");
                    signalCompare(resizes, 0, "Pinning does not start another height animation");
                    core.heightChanged.disconnect(resized);
                    mouseMove(window.contentItem, 950, 850);
                    wait(600);
                    signalCheck(core.signalsOpen, "Pinned panel survives pointer leave");
                    click(header);
                    wait(800);
                    signalCheck(!core.signalsOpen && !loader.active, "Click closes fully even while still hovered");
                    mouseMove(window.contentItem, 950, 850);
                    wait(300);
                    mouseMove(header, header.width / 2, header.height / 2);
                    wait(800);
                    signalCheck(core.signalsOpen, "Re-entering permits a new hover opening");
                    mouseMove(window.contentItem, 950, 850);
                    wait(1000);
                    signalCheck(!core.signalsOpen && !loader.active, "Leaving unpinned Signals closes and unloads it");
                    CoreService.remove("unified-fixture", false);
                }
                Config.set("reducedMotion", true);
                ShellState.osd("VOLUME", .5, "50%");
                mouseMove(header, header.width / 2, header.height / 2);
                wait(800);
                signalCheck(core.volumeInline && !core.signalsOpen, "Volume remains inline on hover");
                mouseMove(window.contentItem, 950, 850);
                ShellState.osdOpen = false;
                console.log("PASS: Signals shares one hover/click panel, stable pin geometry, dismissal and lazy lifetime with motion on/off");
            }
            function test_retired_layout_preferences() {
                for (const style of ["floating", "minimal", "islands", "center", "split"]) {
                    Config.set("barStyle", style);
                    compare(Config.barStyle, "cedar");
                    verify(!Config.barDetached && !Config.barIslands);
                    verify(core.integrated);
                }
                Config.set("barStyle", "cedar");
            }
            function cleanupTestCase() {
                Qt.quit();
            }
        }
    }
}
