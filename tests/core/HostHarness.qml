import QtQuick
import Quickshell
import "../.."
import "../../components/core"
import "../../services"

ShellRoot {
    id: test
    property var original: null
    function check(value, message) {
        if (!value) {
            console.error("FAIL: " + message);
            Qt.exit(1);
        }
    }
    function host(name) {
        // The Core pill is Strata-only: beside the left bar there is no host at
        // all. Anything else would mean a pill where the owner wants none.
        if (Config.barVertical) {
            check(core.instances.length === 0, "no Core host while the bar is on the left");
            return;
        }
        check(core.instances.length === 1, "exactly one host");
        check(core.instances[0].modelData.name === name, "host must use " + name);
        // Offscreen places floating windows on its first screen regardless of
        // the requested output. Check the immutable delegate assignment here;
        // actual layer-surface placement is a live Wayland check.
        check(core.instances[0].assignedOutput === name, "window output assignment never migrates");
    }
    PersistentProperties {
        id: checkpoint
        reloadableId: "core-host-test"
        property int step: 0
    }
    CoreHost {
        id: core
        // Exercise the production host/Variants model with real offscreen
        // QSscreens and QWindows. Wayland layer protocol needs a live compositor.
        delegate: FloatingWindow {
            required property var modelData
            property string assignedOutput: ""
            Component.onCompleted: assignedOutput = modelData.name
            screen: modelData
            visible: true
            implicitWidth: 100
            implicitHeight: 80
        }
    }
    Timer {
        interval: 600
        repeat: true
        running: true
        onTriggered: {
            switch (checkpoint.step) {
            case 0:
                test.check(Quickshell.screens.length === 2, "two virtual outputs");
                test.host("DP-2");
                test.original = core.instances[0];
                for (let n = 0; n < 100; n++) ShellState.osd("VOLUME", n / 100, n + "%");
                test.check(core.instances[0] === test.original, "volume updates retain the host window");
                Config.set("coreMonitor", "DP-1");
                break;
            case 1:
                test.host("DP-1");
                test.check(core.instances[0] !== test.original, "display selection gets a window assigned to the new screen");
                Config.set("coreMonitor", "DP-2");
                break;
            case 2:
                test.host("DP-2");
                checkpoint.step++;
                Quickshell.reload(false);
                return;
            case 3:
                test.host("DP-2");
                Config.set("coreMonitor", "disconnected-output");
                break;
            case 4:
                test.host("DP-1");
                Config.set("coreEnabled", false);
                break;
            case 5:
                test.check(core.instances.length === 0, "disabled Core releases its host");
                Config.set("coreEnabled", true);
                Config.set("coreMonitor", "");
                break;
            case 6:
                test.host("DP-2");
                checkpoint.step++;
                Quickshell.reload(false);
                return;
            case 7:
                test.host("DP-2");
                // The Understory placement has no Core pill at all: the host model
                // is empty. The activity stack survives; the pill's dormant
                // geometry stays correct for a future placement.
                test.original = core.instances[0];
                test.check(CoreService.publish({ id: "test/kept", type: "keyboard", title: "Kept", persistent: true, timeout: 0 }), "publish before the placement switch");
                Config.set("barPlacement", "understory");
                test.check(CoreService.enabled && Config.barVertical, "Core stays enabled with the bar on the left");
                test.host("DP-2");
                test.check(core.instances.length === 0, "no Core host window instantiated when the bar is on the left");
                test.check(CoreService.rows.some(r => r.id === "test/kept"), "placement switch retains the activity stack");
                test.check(CoreService.placement.left >= Config.barWidth && CoreService.placement.left + CoreService.placement.width <= 1920, "dormant floating geometry lies inside DP-2's usable area (" + JSON.stringify(CoreService.placement) + ")");
                Config.set("coreMonitor", "DP-1");
                break;
            case 8:
                test.host("DP-1");
                test.check(CoreService.placement.left + CoreService.placement.width <= 1280, "floating pill fits the smaller DP-1 (" + JSON.stringify(CoreService.placement) + ")");
                Config.set("coreMonitor", "");
                Config.set("barPlacement", "top");
                break;
            case 9:
                test.host("DP-2");
                test.check(!Config.barVertical && CoreService.rows.some(r => r.id === "test/kept"), "back on the top bar with the stack intact");
                test.check(core.instances.length === 1, "the Core host window is instantiated again when the bar is on top");
                console.log("PASS: Core host identity, output changes, fallback, disable/enable, two reloads and placement switches");
                Qt.quit();
                return;
            }
            checkpoint.step++;
        }
    }
}
