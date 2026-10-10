import QtQuick
import Quickshell
import "../.."
import "../../components"
import "../../components/core"
import "../../modules"
import "../../services"

// Two real QsScreens provide output identities; the offscreen platform does
// not prove native layer-shell placement. No controls execute hardware actions.
ShellRoot {
    FloatingWindow {
        id: window
        visible: true
        implicitWidth: Number(Quickshell.env("CEDAR_STRATA_WIDTH"))
        implicitHeight: 200
        color: Theme.background
        property int scenario: 0
        property int savedShots: 0
        readonly property real epsilon: 1

        function check(value, message) {
            if (!value) {
                console.error("FAIL: " + message);
                Qt.exit(1);
            }
        }
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
        function rect(item, target) {
            const p = item.mapToItem(target, 0, 0);
            return { x: p.x, y: p.y, right: p.x + item.width, bottom: p.y + item.height };
        }
        function workspaceFixtures(output) {
            return [1, 2, 3, 4, 5].map(number => ({
                id: number,
                name: String(number),
                monitor: { name: output.name },
                activate: function() {}
            }));
        }
        function contained(item, target, label) {
            const r = rect(item, target);
            check(r.x >= -epsilon && r.right <= target.width + epsilon,
                  label + " must fit horizontally at " + width + "px, font " + Theme.fontScale);
            check(r.y >= -epsilon && r.bottom <= target.height + epsilon,
                  label + " must fit vertically at font " + Theme.fontScale);
        }
        function inspect(sample) {
            const group = sample.contents;
            const left = named(group, "barLeftControls");
            const right = named(group, "barRightControls");
            const fallback = named(group, "barCoreControls");
            check(!!left && !!right && !!fallback, "Strata exposes its three layout regions");
            const host = CoreService.enabled && sample.output.name === CoreService.hostName;
            check(group.coreHost === host, "Only the selected output reserves the activity Core");
            const reserve = host ? CoreService.reserveWidth : fallback.width;
            const leftBounds = rect(left, group), rightBounds = rect(right, group);
            check(leftBounds.right <= (group.width - reserve) / 2 + epsilon, "Left controls leave the center clear");
            check(rightBounds.x >= (group.width + reserve) / 2 - epsilon, "Right controls leave the center clear");
            contained(left, group, "Left controls");
            contained(right, group, "Right controls");
            check(group.statusWidth <= group.sideWidth + epsilon, "Measured status controls fit the right rail, including VPN");
            if (host) {
                check(sample.core.width <= CoreService.reserveWidth + epsilon, "Resting Core stays inside its reservation");
                check(!sample.core.showNetwork, "Strata Core does not duplicate the right-side network control");
            } else {
                check(fallback.visible, "Disabled or secondary Core has a visible identity");
                const midpoint = fallback.mapToItem(group, fallback.width / 2, 0).x;
                check(Math.abs(midpoint - group.width / 2) < epsilon, "Fallback remains centered");
            }
            const regions = [
                [left, ["strataIdentity", "strataLauncher", "strataWorkspaces", "strataWorkspaceOverview", "strataWindowTitle"]],
                [right, ["strataNetwork", "strataAudio", "strataPower", "strataClock", "strataNotifications", "strataQuick"]]
            ];
            for (const region of regions) {
                for (const name of region[1]) {
                    const item = named(group, name);
                    check(!!item, "Expected control " + name);
                    if (!item.visible)
                        continue;
                    contained(item, region[0], name);
                    const topic = name === "strataNetwork" ? "network" : item.anchorTopic;
                    if (topic) {
                        check(item.anchorOutput === sample.output.name, name + " has this output's anchor");
                        const key = topic + "@" + sample.output.name;
                        check(Canopy.anchorProviders[key] === item.anchorRect, name + " owns " + key);
                    }
                }
            }
            for (const name of ["strataIdentity", "strataLauncher", "strataNetwork", "strataAudio", "strataClock", "strataQuick"])
                check(named(group, name).visible, name + " remains available at narrow width");
        }
        function save(sample) {
            const suffix = (CoreService.enabled ? "core" : "plain") + "-" + (Theme.fontScale > 1 ? "1p3" : "1");
            const filename = "strata-" + width + "-" + sample.output.name + "-" + suffix + ".png";
            sample.grabToImage(result => {
                check(result.saveToFile(Quickshell.env("CEDAR_SCREENSHOT_DIR") + "/" + filename), "Saved " + filename);
                savedShots++;
                if (savedShots === 2) {
                    scenario++;
                    advance.start();
                }
            });
        }

        component SampleBar: Item {
            id: sample
            required property var output
            property alias contents: contents
            property alias core: core
            width: window.width
            height: 90
            Item {
                id: bar
                width: parent.width
                height: Config.barHeight
                StrataBarFrame {
                    anchors.fill: parent
                    centerWidth: contents.coreHost ? CoreService.reserveWidth : window.named(contents, "barCoreControls")?.width || 0
                }
                StrataBarContents {
                    id: contents
                    anchors.fill: parent
                    anchors.margins: 6
                    output: sample.output
                    workspaceModel: window.workspaceFixtures(sample.output)
                    activeWorkspace: workspaceModel[1]
                }
                CoreSurface {
                    id: core
                    visible: contents.coreHost
                    active: visible
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: barInset
                    maximumWidth: CoreService.reserveWidth
                    maximumHeight: 600
                }
            }
            Text {
                x: 14
                y: 58
                color: Theme.muted
                font.pixelSize: 11
                text: sample.output.name + " · " + window.width + "px · font " + Theme.fontScale
                      + " · " + (contents.coreHost ? "activity Core" : "centered identity")
            }
        }
        SampleBar {
            id: primary
            y: 8
            output: Quickshell.screens[0]
        }
        SampleBar {
            id: secondary
            y: 104
            output: Quickshell.screens[1]
        }
        Timer {
            id: advance
            interval: 100
            running: true
            onTriggered: {
                window.check(Quickshell.screens.length === 2, "Two virtual outputs are available");
                if (window.scenario === 4) {
                    console.log("PASS: Strata layout, enlarged text and per-output anchors");
                    Qt.quit();
                    return;
                }
                Config.set("coreEnabled", window.scenario % 2 === 0);
                Config.set("fontScale", window.scenario < 2 ? 1 : 1.3);
                Config.set("reducedMotion", true);
                Config.set("coreWarnings", false);
                Config.set("barStyle", "cedar");
                // Deliberate fixture state, never a claim about this machine:
                // enlarged text also exercises the wider VPN network icon.
                Network.data = {
                    available: true, devices: [], networks: [], saved: [],
                    status: { state: "connected", kind: "wired", label: "Fixture Ethernet",
                              vpns: window.scenario >= 2 ? [{ name: "Fixture VPN" }] : [] }
                };
                window.savedShots = 0;
                settle.start();
            }
        }
        Timer {
            id: settle
            interval: 220
            onTriggered: {
                window.inspect(primary);
                window.inspect(secondary);
                window.save(primary);
                window.save(secondary);
            }
        }
    }
}
