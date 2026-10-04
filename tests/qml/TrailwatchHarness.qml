import QtQuick
import QtTest
import Quickshell
import "../.."
import "../../modules"
import "../../services"
import "../../components/trailwatch/Policy.js" as Policy

ShellRoot {
    QtObject {
        id: auth
        property bool busy: false
        property string status: "Enter your password"
        signal clearInputs
    }
    FloatingWindow {
        id: window
        TestCase {
            id: keyboard
            name: "Trailwatch keyboard"
            when: false
        }
        visible: true
        implicitWidth: 1920
        implicitHeight: 1080
        TrailwatchView {
            id: view
            width: 1920
            height: 1080
            auth: auth
            active: true
            preview: true
            date: new Date(2026, 9, 4, 9, 41, 24)
            onSubmitted: value => {
                window.check(value === "fixture-response", "Submitted response");
                window.submits++;
            }
        }
        property int submits: 0
        property int step: 0
        function check(ok, label) {
            if (!ok) {
                console.error("FAIL: " + label);
                Qt.exit(1);
            }
        }
        function textTree(item) {
            let out = [];
            if (item.visible && typeof item.text === "string")
                out.push(item.text);
            for (const child of item.children || [])
                if (child.visible)
                    out = out.concat(textTree(child));
            return out.join("\n");
        }
        function geometry() {
            const p = view.terminal.mapToItem(view, 0, 0);
            check(p.x >= 0 && p.y >= 0 && p.x + view.terminal.width <= view.width + 1 && p.y + view.terminal.height <= view.height, "Authentication stays onscreen");
            check(view.terminal.field.width > 120, "Password field remains usable");
        }
        Component.onCompleted: {
            Config.set("latitude", "36.2");
            Config.set("longitude", "-81.7");
            Weather.temperature = "64°F";
            Weather.feelsLike = "62°F";
            Weather.wind = "8 km/h";
            Weather.rain = 35;
            Weather.code = 2;
            Weather.condition = "Clouds over the holler";
            Weather.updatedAt = new Date();
            Weather.stale = false;
            SystemStats.cpu = .17;
            SystemStats.ram = .38;
            SystemStats.disk = .52;
            SystemStats.temperature = 48;
            SystemStats.memoryLabel = "12.2 / 32.0 GiB";
            SystemStats.available = true;
            Network.data = {
                available: true,
                label: "Ethernet",
                devices: [
                    {
                        type: 1,
                        state: 100
                    }
                ],
                saved: [
                    {
                        type: "wireguard",
                        active: "fixture"
                    }
                ],
                connectivity: 4
            };
            Controls.data = {
                profile: "balanced",
                profiles: ["balanced"],
                errors: {}
            };
            Trailwatch.extra = {
                at: Date.now(),
                reminders: [
                    {
                        at: view.date.getTime() + 7200000,
                        title: "PRIVATE REMINDER"
                    }
                ],
                failed: 0,
                agenda: {
                    status: "ready",
                    events: [
                        {
                            at: view.date.getTime() + 3600000,
                            title: "PRIVATE EVENT"
                        }
                    ]
                },
                gpus: []
            };
            const sun = Policy.solar(new Date(2026, 2, 20), 0, 0);
            check(sun.dawn < sun.sunrise && sun.sunrise < sun.noon && sun.noon < sun.sunset && sun.sunset < sun.dusk, "Solar ordering");
            check(Math.abs((sun.sunset - sun.sunrise) / 3600000 - 12) < .4, "Equinox day length");
            check(Policy.solar(new Date(2026, 5, 21), 89, 0).sunrise === null, "Polar sun has no fabricated crossing");
            check(Policy.solar(new Date(), "", "") === null, "No implicit location");
            check(Policy.readiness({
                lowPower: true,
                offline: true
            }).label === "LOW POWER", "Battery priority");
            check(Policy.readiness({
                offline: true
            }).label === "OFFLINE", "Offline readiness");
            check(Policy.readiness({
                known: false
            }).label === "CHECKING", "Unknown is not ready");
            check(Policy.upcoming([
                {
                    at: 10
                },
                {
                    at: 30
                }
            ], 20, false).at === 30, "Expired events excluded");
        }
        function capture(name) {
            geometry();
            view.grabToImage(r => {
                check(r.saveToFile(Quickshell.env("CEDAR_SCREENSHOT_DIR") + "/" + name + ".png"), "Screenshot saved");
            });
        }
        Timer {
            interval: 700
            running: true
            repeat: true
            onTriggered: {
                if (window.step === 0) {
                    window.check(!window.textTree(view).includes("PRIVATE EVENT"), "Privacy hides event titles");
                    window.capture("trailwatch-desktop");
                } else if (window.step === 1) {
                    view.width = 3440;
                    view.height = 1440;
                    window.implicitWidth = 3440;
                    window.implicitHeight = 1440;
                } else if (window.step === 2)
                    window.capture("trailwatch-ultrawide");
                else if (window.step === 3) {
                    view.width = 1366;
                    view.height = 768;
                    window.implicitWidth = 1366;
                    window.implicitHeight = 768;
                } else if (window.step === 4)
                    window.capture("trailwatch-laptop");
                else if (window.step === 5) {
                    view.width = 800;
                    view.height = 900;
                    window.implicitWidth = 800;
                    window.implicitHeight = 900;
                } else if (window.step === 6)
                    window.capture("trailwatch-stacked");
                else if (window.step === 7) {
                    view.width = 480;
                    view.height = 800;
                    window.implicitWidth = 480;
                    window.implicitHeight = 800;
                    Config.set("reducedMotion", true);
                } else if (window.step === 8) {
                    window.capture("trailwatch-narrow");
                    window.check(Theme.reducedMotion, "Reduced motion reaches UI");
                    view.terminal.field.text = "fixture-response";
                    view.terminal.submit();
                    window.check(window.submits === 1 && view.terminal.field.text === "", "Submit clears response");
                    view.terminal.field.text = "discard";
                    auth.clearInputs();
                    window.check(view.terminal.field.text === "", "Controller clears fields");
                    auth.busy = true;
                } else if (window.step === 9) {
                    window.check(!view.terminal.field.enabled, "Busy disables input");
                    auth.busy = false;
                    Config.set("lockPrivacy", false);
                    Config.set("lockAgendaDetails", true);
                } else if (window.step === 10) {
                    window.check(window.textTree(view).includes("PRIVATE EVENT"), "Opt-in event title");
                    Trailwatch.shielded = true;
                } else if (window.step === 11) {
                    window.check(!window.textTree(view).includes("PRIVATE EVENT"), "Session shield hides title");
                    Config.set("latitude", "");
                    Config.set("longitude", "");
                    Network.data = {
                        available: false,
                        label: "Unavailable",
                        devices: [],
                        saved: []
                    };
                    Trailwatch.extra = {
                        at: 0,
                        failed: null,
                        reminders: null,
                        agenda: {
                            status: "unconfigured",
                            events: []
                        },
                        gpus: []
                    };
                } else if (window.step === 12) {
                    window.capture("trailwatch-unavailable");
                    auth.status = "Password not accepted. Try again.";
                } else if (window.step === 13) {
                    window.check(view.terminal.field.activeFocus, "Focus restored after checking");
                    view.terminal.field.text = "fixture";
                    keyboard.keyClick(Qt.Key_U, Qt.ControlModifier);
                    window.check(view.terminal.field.text === "", "Ctrl+U clears password");
                    keyboard.keyClick(Qt.Key_A);
                    window.check(view.terminal.field.text === "a", "Keyboard input reaches password");
                    keyboard.keyClick(Qt.Key_Escape);
                    window.check(view.terminal.field.text === "", "Escape clears without unlocking");
                    view.terminal.field.text = "fixture";
                    keyboard.keyClick(Qt.Key_Tab);
                    window.check(!view.terminal.field.activeFocus, "Tab leaves field for controls");
                    view.terminal.refocus();
                    console.log("PASS: Trailwatch layout, privacy, authentication UI, solar and readiness");
                    Qt.quit();
                }
                window.step++;
            }
        }
    }
}
