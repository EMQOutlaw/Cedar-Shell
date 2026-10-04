import QtQuick
import Quickshell
import "../.."
import "../../modules"
import "../../services"

ShellRoot {
    FloatingWindow {
        id: window
        visible: true
        implicitWidth: 960
        implicitHeight: 800
        color: Theme.background
        CanopyPanel {
            id: panel
            width: window.previewWidth
            height: parent.height
            active: true
        }
        Component.onCompleted: {
            AudioInstruments.data = {
                outputs: [
                    {
                        id: 1,
                        name: "speakers",
                        label: "Speakers"
                    }
                ],
                inputs: [],
                streams: [
                    {
                        id: 3,
                        serial: "42",
                        label: "Browser",
                        output: 1
                    }
                ],
                scenes: [
                    {
                        name: "Music",
                        output: {
                            label: "Speakers",
                            volume: .5,
                            muted: false
                        },
                        microphone: null,
                        streams: []
                    }
                ],
                eq: {
                    available: false,
                    reason: "No DSP backend connected."
                },
                spectrumAvailable: false
            };
            NoticeStore.history = [
                {
                    id: 101,
                    app: "Test app",
                    summary: "Fixture notification",
                    body: "A real history layout test.",
                    timestamp: Date.now(),
                    critical: false
                }
            ];
            Weather.hours = [
                {
                    time: "13:00",
                    temperature: "67°F",
                    rain: 18
                },
                {
                    time: "14:00",
                    temperature: "65°F",
                    rain: 34
                }
            ];
        }
        property int previewWidth: 960
        property int step: 0
        function check(ok, msg) {
            if (!ok) {
                console.error("FAIL: " + msg);
                Qt.exit(1);
            }
        }
        Timer {
            id: capture
            interval: 200
            onTriggered: panel.grabToImage(r => r.saveToFile(Quickshell.env("CEDAR_SCREENSHOT_DIR") + "/canopy-" + Canopy.topic + "-" + window.previewWidth + ".png"))
        }
        Timer {
            interval: 420
            running: true
            repeat: true
            onTriggered: {
                if (window.step < Canopy.topics.length * 2) {
                    window.previewWidth = window.step < Canopy.topics.length ? 960 : 480;
                    Canopy.open(Canopy.topics[window.step % Canopy.topics.length]);
                    capture.restart();
                    window.step++;
                    return;
                }
                if (window.step === Canopy.topics.length * 2) {
                    Config.set("forestTrails", true);
                    Forest.record("settings", "Settings / Displays", "displays");
                    window.check(Forest.trails.length > 0, "Trails opt-in records navigation");
                    Canopy.open("audio");
                    Canopy.pin();
                    ShellState.open("settings");
                    window.check(Canopy.shown && Canopy.pinned, "Pinned Canopy survives another surface");
                    Canopy.open("network");
                    window.check(Canopy.topic === "network" && Canopy.pinned, "Only one pinned surface");
                    Config.set("clipboardHistory", true);
                    Clipboard.clear();
                    Clipboard.accept({
                        kind: "text",
                        payload: "Test clipboard item",
                        label: "Text"
                    });
                    window.check(Clipboard.items.length === 1, "Opt-in clipboard capture");
                    ShellState.locked = true;
                    window.check(!Canopy.shown && !Canopy.pinned && !Forest.trails.length && !Clipboard.items.length, "Lock clears private session history and pinning");
                    ShellState.locked = false;
                    Config.set("forestTrails", false);
                    Forest.record("settings", "Hidden", "system");
                    window.check(Forest.trails.length === 0, "Trails disabled means no tracking");
                    console.log("PASS: Canopy pages, pinning, opt-in history and lock privacy");
                    Qt.quit();
                }
            }
        }
    }
}
