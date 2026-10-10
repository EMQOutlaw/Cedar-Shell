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
                // These established checks exercise the legacy Core that owns
                // Quick Controls and the neighbouring network entry.
                Config.set("barStyle", "floating");
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
                const header = named(core, "coreHeader"), network = named(core, "coreNetwork");
                verify(header.width + network.width <= core.width);
                click(header);
                compare(Canopy.topic, "quick");
                verify(Canopy.shown);
                const volume = named(canopy, "quickVolume");
                verify(volume !== null);
                verify(volume.mapToItem(canopy, 0, 0).y < 400, "Volume immediately visible");
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
                keyClick(Qt.Key_Return);
                wait(20);
                verify(!Canopy.shown);
                keyClick(Qt.Key_Return);
                wait(20);
                verify(Canopy.shown);
                keyClick(Qt.Key_Escape);
                wait(20);
                verify(!Canopy.shown);
                header.forceActiveFocus();
                keyClick(Qt.Key_Tab);
                wait(20);
                verify(network.activeFocus, "Network is the next focus target");
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
            function cleanupTestCase() {
                Qt.quit();
            }
        }
    }
}
