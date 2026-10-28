// MOCK — Settings › Nursery: plugin cards over fixture registries.
// Rendered offscreen by tests/check_nursery_mock.py. Fixture state only.
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../.."
import "../../components"
import "../../modules"
import "../../services"

ShellRoot {
    FloatingWindow {
        id: window
        visible: true
        implicitWidth: 1000
        implicitHeight: 680
        color: Theme.background

        // Three fixture registries: a healthy running plugin, a plugin whose
        // first-time question is still open, and the empty Nursery.
        property var fixtureRunning: ({
            plugins_dir: "/home/user/.config/cedar/plugins.d",
            plugins: [{
                id: "cedar-ai", name: "CEDAR Ai",
                tagline: "The field vault: an exact map of the machine, local-only.",
                unit: "cedar-ai.service", dashboard: "http://127.0.0.1:3650/",
                setup: "cedar-ai setup", docs: "",
                installed: true, active: true, enabled: true,
                setup_state: "enabled", dashboard_ok: true
            }]
        })
        property var fixturePending: ({
            plugins_dir: "/home/user/.config/cedar/plugins.d",
            plugins: [{
                id: "cedar-ai", name: "CEDAR Ai",
                tagline: "The field vault: an exact map of the machine, local-only.",
                unit: "cedar-ai.service", dashboard: "http://127.0.0.1:3650/",
                setup: "cedar-ai setup", docs: "",
                installed: false, active: false, enabled: false,
                setup_state: "pending", dashboard_ok: false
            }, {
                id: "fieldglass", name: "Fieldglass",
                tagline: "A weather almanac that keeps a year of sky in the vault.",
                unit: "", dashboard: "", setup: "", docs: "",
                installed: false, active: false, enabled: false,
                setup_state: "", dashboard_ok: false
            }]
        })
        property var fixtureEmpty: ({ plugins_dir: "/home/user/.config/cedar/plugins.d", plugins: [] })

        Item {
            id: panel
            anchors.fill: parent
            anchors.margins: 24

            ColumnLayout {
                anchors.fill: parent; spacing: 16
                ColumnLayout {
                    spacing: 4
                    GlowText { text: "Nursery"; font.family: Theme.labelFont; font.pixelSize: 36; color: Theme.strataText }
                    GlowText { text: "Companion services planted into the shell — CEDAR Ai first. Off until you say otherwise."; color: Theme.strataMuted; font.pixelSize: Theme.small }
                }
                NurserySettings {
                    id: page
                    Layout.fillWidth: true
                    active: true
                }
            }
        }

        property int step: 0
        Timer {
            interval: 300; running: !Quickshell.env("CEDAR_MOCK_LIVE"); repeat: true
            onTriggered: {
                const dir = Quickshell.env("CEDAR_SCREENSHOT_DIR");
                if (window.step === 0) {
                    Nursery.feed(window.fixtureRunning);
                    panel.grabToImage(r => r.saveToFile(dir + "/nursery-running.png"));
                } else if (window.step === 1) {
                    Nursery.feed(window.fixturePending);
                    panel.grabToImage(r => r.saveToFile(dir + "/nursery-pending.png"));
                } else if (window.step === 2) {
                    Nursery.feed(window.fixtureEmpty);
                    panel.grabToImage(r => r.saveToFile(dir + "/nursery-empty.png"));
                } else {
                    console.log("PASS: Nursery mock — 3 renders");
                    Qt.quit();
                }
                window.step++;
            }
        }
    }
}
