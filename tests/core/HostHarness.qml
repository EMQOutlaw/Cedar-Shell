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
                console.log("PASS: Core host identity, output changes, fallback, disable/enable and two reloads");
                Qt.quit();
                return;
            }
            checkpoint.step++;
        }
    }
}
