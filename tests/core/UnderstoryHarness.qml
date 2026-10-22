import QtQuick
import Quickshell
import "../.."
import "../../modules"
import "../../services"

// The Understory rail over the test services (no daemons, no hardware), a
// screenshot of it, and the routing checks: opening takes the panel, closing
// releases it, opening the Canopy displaces it, and Keep awake refuses
// politely without systemd-inhibit.
ShellRoot {
    FloatingWindow {
        id: window
        visible: true
        implicitWidth: 420
        implicitHeight: 1156
        color: Theme.background
        Rectangle {
            id: frame
            x: 0; y: 0; width: 388; height: window.height
            color: Qt.alpha(Theme.strataFoundation, .96)
            Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Qt.alpha(Theme.strataAccent, .32) }
            UnderstoryRail {
                id: rail
                anchors.fill: parent
                active: true
                outputName: ""
            }
        }
        Timer {
            interval: 900; running: true
            onTriggered: {
                let ok = true;
                function check(cond, what) { if (!cond) { ok = false; console.log("FAIL: " + what); } }
                check(rail.childAt(30, 30) !== null, "the rail has an instrument column");
                check(Awake.available === false && Awake.held === false, "Keep awake is unavailable in test mode and not held");
                Awake.toggle();
                check(Awake.held === false, "Keep awake stays off without systemd-inhibit");
                // Routing through ShellState.panel.
                Understory.open();
                check(ShellState.panel === "understory", "open takes the panel (" + ShellState.panel + ")");
                check(Understory.shown || Understory.screen === null, "shown follows the panel when a screen exists");
                Canopy.open("quick");
                check(ShellState.panel !== "understory", "the Canopy displaces the Understory");
                Understory.open();
                check(!Canopy.shown, "the Understory displaces the Canopy");
                Understory.toggle();
                check(ShellState.panel === "", "toggle closes (" + ShellState.panel + ")");
                Understory.close();
                check(ShellState.panel === "", "close is idempotent");
                frame.grabToImage(r => {
                    r.saveToFile(Quickshell.env("CEDAR_SCREENSHOT_DIR") + "/understory.png");
                    if (ok) console.log("PASS: Understory rail");
                    Qt.quit();
                });
            }
        }
    }
}
