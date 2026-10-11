import QtQuick
import Quickshell
import "../.."
import "../../components"
import "../../components/core"
import "../../modules"
import "../../services"

ShellRoot {
    FloatingWindow {
        id: window
        visible: true
        implicitWidth: 1280
        implicitHeight: 180
        color: Theme.background
        property int step: 0
        function check(ok, label) {
            if (!ok) {
                console.error("FAIL: " + label);
                Qt.exit(1);
            }
        }
        function named(item, name) {
            if (item.objectName === name)
                return item;
            for (const c of item.children || []) {
                const result = named(c, name);
                if (result)
                    return result;
            }
            return null;
        }
        Item {
            id: scene
            width: 1280
            height: parent.height
            Item {
                id: bar
                y: 20
                x: 0
                width: scene.width - x * 2
                height: Config.barHeight
                StrataBarFrame {
                    anchors.fill: parent
                    materialOpacity: Config.barOpacity
                    centerWidth: contents.item ? contents.item.centerWidth : 0
                }
                Loader {
                    id: contents
                    anchors.fill: parent
                    anchors.margins: 6
                    sourceComponent: strataContents
                }
                Component {
                    id: strataContents
                    StrataBarContents { output: Quickshell.screens[0] }
                }
            }
            CoreSurface {
                id: core
                visible: CoreService.enabled
                anchors.horizontalCenter: parent.horizontalCenter
                y: bar.y + barInset
                active: visible
                maximumWidth: 480
                maximumHeight: 600
            }
            GlowText {
                y: 130
                x: 20
                text: Config.barStyle + " · " + scene.width + "px · Core " + (CoreService.enabled ? "enabled" : "disabled / secondary bar appearance")
                color: Theme.muted
            }
        }
        Timer {
            id: inspect
            interval: 190
            onTriggered: {
                const group = contents.item;
                window.check(group !== null, "Selected bar layout is loaded");
                if (group.coreHost) {
                    const left = window.named(group, "barLeftControls"), right = window.named(group, "barRightControls");
                    window.check(left !== null && right !== null, "Selected bar exposes both side regions");
                    window.check(left.x + left.width <= group.width / 2 - CoreService.reserveWidth / 2, "Left controls must leave room for Core in " + Config.barStyle);
                    window.check(right.x >= group.width / 2 + CoreService.reserveWidth / 2, "Right controls must leave room for Core in " + Config.barStyle);
                }
                const fallback = window.named(group, "barCoreControls");
                window.check(fallback !== null, "Secondary/disabled Core center exists");
                if (!group.coreHost) {
                    const center = fallback.mapToItem(scene, fallback.width / 2, 0).x;
                    window.check(Math.abs(center - scene.width / 2) < 1, "Fallback remains centered");
                    window.check(fallback.width <= 280, "Fallback identity or clock stays bounded");
                }
                scene.grabToImage(r => r.saveToFile(Quickshell.env("CEDAR_SCREENSHOT_DIR") + "/bar-" + Config.barStyle + "-" + scene.width + "-" + (CoreService.enabled ? "core" : "plain") + ".png"));
            }
        }
        Timer {
            interval: 360
            repeat: true
            running: true
            onTriggered: {
                if (window.step === 6) {
                    console.log("PASS: Strata bar reserve Core space at three widths and keep a centered fallback");
                    Qt.quit();
                    return;
                }
                Config.set("reducedMotion", true);
                Config.set("coreWarnings", false);
                Config.set("barStyle", "cedar");
                Config.set("coreEnabled", window.step % 2 === 0);
                scene.width = window.step < 2 ? 1280 : window.step < 4 ? 960 : 640;
                Config.set("fontScale", window.step < 4 ? 1 : 1.25);
                inspect.restart();
                window.step++;
            }
        }
    }
}
