// MOCK — Thicket panic posture: Shield hero card + Quick Controls tile.
// Fixture state only; rendered offscreen by tests/check_thicket_mock.py.
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../.."
import "../../components"
import "../../services"

ShellRoot {
    FloatingWindow {
        id: window
        visible: true
        implicitWidth: 1000
        implicitHeight: 660
        color: Theme.background

        property bool engaged: false
        property bool tiles: false
        property string engagedSince: "4:52 PM" // FIXTURE — wiring binds the real engaged-at timestamp persisted across the lock

        // Hold order matters: lock is LAST — it is terminal within the
        // transaction and can never be rolled back from inside the lock.
        property var holds: [
            { glyph: Theme.nerdGlyph("󰖔", "N"), label: "Network",       detail: "radio off — nothing leaves the machine" },
            { glyph: Theme.nerdGlyph("󰍭", "M"), label: "Microphone",     detail: "muted at the source" },
            { glyph: Theme.nerdGlyph("󰂛", "D"), label: "Do not disturb", detail: "notices held at the door" },
            { glyph: Theme.nerdGlyph("󰙅", "P"), label: "Privacy",        detail: "notice bodies blanked while locked" },
            { glyph: Theme.nerdGlyph("󰌾", "L"), label: "Lock screen",    detail: "Trailwatch keeps the gate — always the final hold" }
        ]

        Item {
            id: panel
            anchors.fill: parent

            // ================= hero card =================
            Item {
                anchors.fill: parent
                visible: !window.tiles

                ChamferFrame {
                    anchors.fill: parent; anchors.margins: 14
                    cut: Theme.chamfer
                    fill: Qt.alpha(Theme.strataFoundation, .96)
                    stroke: window.engaged ? Qt.alpha(Theme.ember, .5) : Qt.alpha(Theme.teal, .18)
                    topLine: true
                    topLineColor: window.engaged ? Theme.ember : Theme.teal
                }
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 34; spacing: 13

                    GlowText { text: "SHIELD / POSTURE"; font.pixelSize: 10; font.letterSpacing: 1.4; color: window.engaged ? Theme.ember : Theme.teal }
                    RowLayout {
                        Layout.fillWidth: true
                        GlowText {
                            text: "THE THICKET"
                            font.family: Theme.labelFont; font.pixelSize: Math.round(22 * Theme.fontScale); font.weight: Font.DemiBold; font.letterSpacing: 6
                            color: window.engaged ? Theme.ember : Theme.text
                            Layout.fillWidth: true
                        }
                        GlowText {
                            visible: window.engaged
                            text: "SHELTERED SINCE " + window.engagedSince
                            font.pixelSize: 10; font.letterSpacing: 1.4; color: Theme.ember
                        }
                    }
                    GlowText {
                        Layout.fillWidth: true; wrapMode: Text.WordWrap
                        font.pixelSize: Theme.small; color: Theme.muted
                        text: window.engaged
                              ? "You are in the brush. The radio is off, the microphone is mute, the door is held. Step out and every hold releases in reverse."
                              : "One gesture and the desktop steps into the brush: network off, microphone muted, do-not-disturb, notices blanked, and Trailwatch holds the gate. Leaving restores every step."
                    }
                    Item { Layout.fillWidth: true; implicitHeight: 1; Rectangle { width: parent.width; height: 1; color: Qt.alpha(window.engaged ? Theme.ember : Theme.teal, .28) } }

                    // ---- the five holds ----------------------------------
                    Repeater {
                        model: window.holds
                        Item {
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            Layout.preferredHeight: 44
                            ChamferFrame {
                                anchors.fill: parent; cut: 6
                                fill: window.engaged ? Qt.alpha(Theme.ember, .05) : Qt.alpha(Theme.strataFoundation, .5)
                                stroke: window.engaged ? Qt.alpha(Theme.ember, .35) : Qt.alpha(Theme.strataAccent, .14)
                            }
                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14; spacing: 12
                                GlowText { text: modelData.glyph; font.pixelSize: 15; color: window.engaged ? Theme.ember : Theme.strataMuted }
                                ColumnLayout {
                                    spacing: 1; Layout.fillWidth: true
                                    GlowText { text: modelData.label; font.family: Theme.labelFont; font.pixelSize: 14; color: window.engaged ? Theme.text : Theme.strataText }
                                    GlowText { text: modelData.detail; font.pixelSize: 10; color: Theme.muted }
                                }
                                GlowText {
                                    text: window.engaged ? "HELD" : "WILL HOLD"
                                    font.pixelSize: 9; font.letterSpacing: 1.6
                                    color: window.engaged ? Theme.ember : Theme.muted
                                }
                                Rectangle { width: 6; height: 6; radius: 3; color: window.engaged ? Theme.ember : Theme.strataMuted; opacity: window.engaged ? 1 : .5 }
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }

                    // ---- the gesture: press-and-hold, never a bare tap ------
                    Item {
                        Layout.fillWidth: true; Layout.preferredHeight: 56
                        Accessible.name: window.engaged ? "Leave the Thicket: press and hold to release every hold" : "Enter the Thicket: press and hold to engage five privacy holds"
                        Accessible.role: Accessible.Button
                        ChamferFrame {
                            anchors.fill: parent; cut: 10
                            fill: window.engaged ? Qt.alpha(Theme.green, .08) : Qt.alpha(Theme.ember, .10)
                            stroke: window.engaged ? Qt.alpha(Theme.green, .55) : Qt.alpha(Theme.ember, .6)
                            line: true; lineColor: window.engaged ? Theme.green : Theme.ember; lineFraction: .5
                        }
                        // The hold-to-confirm meter (mocked mid-press at 35%):
                        // the gesture only fires when this fills.
                        Rectangle {
                            anchors.left: parent.left; anchors.bottom: parent.bottom
                            anchors.leftMargin: 12; anchors.bottomMargin: 4
                            width: (parent.width - 24) * .35; height: 2; radius: 1
                            color: window.engaged ? Theme.green : Theme.ember; opacity: .8
                        }
                        ColumnLayout {
                            anchors.centerIn: parent; spacing: 1
                            GlowText {
                                Layout.alignment: Qt.AlignHCenter
                                text: window.engaged ? "LEAVE THE THICKET" : "ENTER THE THICKET"
                                font.family: Theme.labelFont; font.pixelSize: 15; font.weight: Font.DemiBold; font.letterSpacing: 3
                                color: window.engaged ? Theme.green : Theme.ember
                            }
                            GlowText {
                                Layout.alignment: Qt.AlignHCenter
                                text: window.engaged ? "press and hold to release · everything returns" : "press and hold · one guarded transaction · failure rolls the first four back"
                                font.pixelSize: 9; color: Theme.muted
                            }
                        }
                    }
                    GlowText {
                        Layout.fillWidth: true
                        text: "Five holds, one transaction. If any step fails, the rest roll back before the gate closes — the desktop never half-hides."
                        font.pixelSize: 10; color: Theme.muted; wrapMode: Text.WordWrap
                    }
                }
            }

            // ================= quick controls tiles =================
            RowLayout {
                anchors.centerIn: parent
                visible: window.tiles
                spacing: 18
                // NOTE for wiring: this pair must be real QuickControls `Tile`
                // instances (that inline component wants extracting to
                // components/ first) — the on-state accent is strataAccent like
                // every other lit tile, not a one-off ember.
                Repeater {
                    model: [false, true]
                    Item {
                        required property bool modelData
                        Layout.preferredWidth: 300; Layout.preferredHeight: 64
                        Accessible.name: "Thicket: " + (modelData ? "Sheltered, all quiet" : "5 holds armed")
                        ChamferFrame {
                            anchors.fill: parent; cut: Theme.strataCut
                            fill: modelData ? Qt.alpha(Theme.strataAccent, .06) : Qt.alpha(Theme.strataFoundation, .6)
                            stroke: modelData ? Qt.alpha(Theme.strataAccent, .45) : Qt.alpha(Theme.strataAccent, .14)
                            line: modelData; lineColor: Theme.strataAccent; lineFraction: .6
                        }
                        ColumnLayout {
                            anchors.fill: parent; anchors.margins: 12; spacing: 3
                            RowLayout {
                                Layout.fillWidth: true; spacing: 8
                                Text { text: Theme.nerdGlyph("󰒃", "T"); textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: 15; color: modelData ? Theme.strataAccent : Theme.strataMuted }
                                Text { Layout.fillWidth: true; text: "Thicket"; textFormat: Text.PlainText; font.family: Theme.labelFont; font.pixelSize: Math.round(15 * Theme.fontScale); color: modelData ? Theme.strataAccent : Theme.strataText; elide: Text.ElideRight }
                                Rectangle { width: 5; height: 5; radius: 3; color: modelData ? Theme.strataAccent : Theme.strataMuted; opacity: modelData ? 1 : .5; Layout.alignment: Qt.AlignVCenter }
                            }
                            Text { Layout.fillWidth: true; text: modelData ? "Sheltered · all quiet" : "5 holds armed"; textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: 10; color: Theme.strataMuted; elide: Text.ElideRight }
                        }
                    }
                }
            }
        }

        // ---- capture steps ------------------------------------------------
        property int step: 0
        Timer {
            interval: 300; running: !Quickshell.env("CEDAR_MOCK_LIVE"); repeat: true
            onTriggered: {
                const dir = Quickshell.env("CEDAR_SCREENSHOT_DIR");
                if (window.step === 0) {
                    window.engaged = false; window.tiles = false;
                    panel.grabToImage(r => r.saveToFile(dir + "/thicket-armed.png"));
                } else if (window.step === 1) {
                    window.engaged = true;
                    panel.grabToImage(r => r.saveToFile(dir + "/thicket-engaged.png"));
                } else if (window.step === 2) {
                    window.tiles = true;
                    panel.grabToImage(r => r.saveToFile(dir + "/thicket-tiles.png"));
                } else {
                    console.log("PASS: Thicket mock — 3 renders");
                    Qt.quit();
                }
                window.step++;
            }
        }
    }
}
