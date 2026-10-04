import QtQuick
import Quickshell
import "../.."
import "../../components/core"
import "../../services"

ShellRoot {
    FloatingWindow {
        id: window
        visible: true
        implicitWidth: 620
        implicitHeight: 740
        color: Theme.background
        CoreSurface {
            id: core
            anchors.horizontalCenter: parent.horizontalCenter
            y: 20
            maximumWidth: 480
            maximumHeight: 690
            active: true
            focusRequested: CoreService.expanded
        }
        property int step: 0
        property var originalSlider: null
        property string shot: ""
        property int closed: 0
        Connections {
            target: ShellState
            function onOsdOpenChanged() {
                if (!ShellState.osdOpen && window.step > 0)
                    window.closed++;
            }
        }
        function check(ok, label) {
            if (!ok) {
                console.error("FAIL: " + label);
                Qt.exit(1);
            }
        }
        function find(item, name) {
            if (item.objectName === name)
                return item;
            for (let c of item.children || []) {
                const result = find(c, name);
                if (result)
                    return result;
            }
            return null;
        }
        Timer {
            id: capture
            interval: 280
            onTriggered: core.grabToImage(r => r.saveToFile(Quickshell.env("CEDAR_SCREENSHOT_DIR") + "/" + window.shot + ".png"))
        }
        Timer {
            interval: 550
            running: true
            repeat: true
            onTriggered: {
                switch (window.step) {
                case 0:
                    Config.set("coreWarnings", false);
                    Config.set("reducedMotion", true);
                    window.shot = "core-rest";
                    break;
                case 1:
                    ShellState.osd("VOLUME", .5, "50%");
                    window.originalSlider = window.find(core, "coreVolumeSlider");
                    window.shot = "core-volume";
                    break;
                case 2:
                    for (let i = 0; i < 100; i++)
                        ShellState.osd("VOLUME", i / 100, i + "%");
                    window.check(window.originalSlider === window.find(core, "coreVolumeSlider"), "Repeated volume changes preserve the slider instance");
                    window.check(ShellState.osdOpen && window.closed === 0, "Repeated volume changes never blink closed");
                    ShellState.osdCoreDragging = true;
                    ShellState.osdCoreInteracting = true;
                    CoreService.hold("osd");
                    window.shot = "core-volume-held";
                    break;
                case 3:
                case 4:
                case 5:
                case 6:
                    window.check(ShellState.osdOpen, "Interaction extends OSD visibility");
                    window.shot = "core-volume-hold-" + window.step;
                    break;
                case 7:
                    Config.set("coreWarnings", true);
                    ShellState.osdCoreDragging = false;
                    ShellState.osdCoreInteracting = false;
                    CoreService.hold("");
                    CoreService.publish({
                        id: "capture",
                        type: "recording",
                        title: "Screen recording",
                        subtitle: "Microphone included",
                        persistent: true,
                        priority: "high",
                        data: {
                            started: Date.now() - 134000
                        },
                        actions: []
                    });
                    CoreService.publish({
                        id: "download",
                        type: "progress",
                        title: "Fedora.iso",
                        subtitle: "Example provider · download in progress",
                        progress: .68,
                        persistent: true
                    });
                    CoreService.publish({
                        id: "critical",
                        type: "warning",
                        priority: "critical",
                        title: "High temperature · 91°C",
                        subtitle: "System temperature sensors",
                        persistent: true,
                        sticky: true
                    });
                    window.check(CoreService.foreground.id === "critical", "Critical activity wins over concurrent events");
                    window.shot = "core-warning";
                    break;
                case 8:
                    CoreService.expand("critical");
                    window.shot = "core-stack";
                    break;
                case 9:
                    CoreService.remove("critical", false);
                    CoreService.timer.start(300, "Tea timer");
                    CoreService.model.selectedId = "timer";
                    window.shot = "core-timer";
                    break;
                case 10:
                    CoreService.timer.toggle();
                    window.check(CoreService.timer.paused && CoreService.timer.remaining > 295, "Timer pauses without losing remaining duration");
                    window.shot = "core-timer-paused";
                    break;
                case 11:
                    CoreService.timer.cancel();
                    CoreService.remove("capture", false);
                    CoreService.remove("download", false);
                    CoreService.publish({
                        id: "screenshot/test",
                        type: "screenshot",
                        title: "Screenshot captured",
                        subtitle: "Saved locally",
                        timeout: 6500,
                        actions: [
                            {
                                id: "open-file",
                                label: "Open"
                            },
                            {
                                id: "copy-image",
                                label: "Copy image"
                            },
                            {
                                id: "reveal-file",
                                label: "Reveal"
                            }
                        ]
                    });
                    CoreService.model.selectedId = "screenshot/test";
                    window.shot = "core-screenshot";
                    break;
                case 12:
                    CoreService.collapse();
                    ShellState.osdOpen = false;
                    Config.set("coreEnabled", false);
                    window.check(!CoreService.ownsOsd, "Legacy OSD remains available when Core is disabled");
                    console.log("PASS: Core stable volume, interaction hold, priority, timer, stack and OSD fallback");
                    Qt.quit();
                    return;
                }
                capture.restart();
                window.step++;
            }
        }
    }
}
