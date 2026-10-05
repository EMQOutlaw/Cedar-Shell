import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."
import "../components"
import "../services"

Rectangle {
    id: root
    property bool active: false
    color: Qt.alpha(Theme.background, Math.max(.96, Config.panelOpacity))
    radius: Config.panelRadius
    border.color: Qt.alpha(Forest.accent, .25)
    border.width: 1
    clip: true
    CedarAtmosphere {
        anchors.fill: parent
        active: root.active && !Canopy.peeking && Forest.state !== "HUNT" && Config.saved.ambientIntensity > 0
        opacity: Config.saved.ambientIntensity * .22
    }
    HoverHandler {
        onHoveredChanged: {
            if (hovered)
                Canopy.holdPeek();
            else
                Canopy.leavePeek();
        }
    }
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 12
        RowLayout {
            Layout.fillWidth: true
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                GlowText {
                    text: "◈  " + Canopy.title.toUpperCase()
                    color: Forest.accent
                    font.family: Theme.labelFont
                    font.pixelSize: 24
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
                GlowText {
                    visible: Canopy.peeking
                    text: "PEEK · click Open for controls"
                    color: Theme.muted
                    font.pixelSize: 10
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
            }
            StationButton {
                visible: Canopy.peeking
                text: "Open"
                onClicked: Canopy.open(Canopy.topic)
            }
            StationButton {
                visible: !Canopy.peeking
                text: Canopy.pinned ? "Unpin" : "Pin"
                hint: "Keep one Canopy visible. Unpin to use keyboard controls."
                checked: Canopy.pinned
                onClicked: Canopy.pin()
            }
            StationButton {
                text: "×"
                hint: "Close Canopy"
                onClicked: Canopy.close()
            }
        }
        Flow {
            visible: !Canopy.peeking
            Layout.fillWidth: true
            spacing: 4
            Repeater {
                model: Canopy.topics
                StationButton {
                    required property string modelData
                    text: ({
                            audio: "Audio",
                            network: "Connections",
                            bluetooth: "Bluetooth",
                            power: "Power",
                            system: "System",
                            weather: "Sky",
                            calendar: "Time",
                            clipboard: "Clipboard",
                            notifications: "Notes",
                            quick: "Quick",
                            trails: "Trails"
                        })[modelData]
                    implicitHeight: 30
                    checked: Canopy.topic === modelData
                    onClicked: Canopy.open(modelData)
                }
            }
        }
        GlowText {
            visible: Canopy.peeking
            Layout.fillWidth: true
            Layout.fillHeight: true
            wrapMode: Text.WordWrap
            text: Canopy.topic === "audio" ? (Audio.sink?.description || "No output") + " · " + Audio.label : Canopy.topic === "network" ? Network.label : Canopy.topic === "bluetooth" ? (BluetoothService.adapter?.enabled ? "Bluetooth on" : "Bluetooth off") : Forest.phrase
            color: Theme.text
        }
        ScrollView {
            visible: !Canopy.peeking
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: availableWidth
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            Loader {
                id: loader
                asynchronous: true
                width: parent.width
                active: root.active && !Canopy.peeking
                sourceComponent: ({
                        audio: audio,
                        network: network,
                        bluetooth: bluetooth,
                        power: power,
                        system: system,
                        weather: weather,
                        calendar: calendar,
                        clipboard: clipboard,
                        notifications: notifications,
                        quick: quick,
                        trails: trails
                    })[Canopy.topic]
            }
        }
        RowLayout {
            visible: !Canopy.peeking
            Layout.fillWidth: true
            GlowText {
                Layout.fillWidth: true
                text: Canopy.pinned ? "PINNED · one instrument stays with you" : ""
                color: Theme.muted
                font.pixelSize: 10
                elide: Text.ElideRight
            }
            StationButton {
                text: "Signals"
                onClicked: {
                    Canopy.close();
                    CoreService.expand();
                }
            }
            StationButton {
                text: "Full Settings"
                onClicked: {
                    Canopy.close();
                    ShellState.settingsPage = "overview";
                    ShellState.open("settings");
                }
            }
        }
    }
    Component {
        id: audio
        AudioCanopy {
            active: root.active
        }
    }
    Component {
        id: network
        ConnectionSettings {
            active: root.active
        }
    }
    Component {
        id: bluetooth
        BluetoothSettings {}
    }
    Component {
        id: system
        SystemCanopy {
            active: root.active
        }
    }
    Component {
        id: weather
        WeatherCanopy {}
    }
    Component {
        id: calendar
        CalendarCanopy {}
    }
    Component {
        id: clipboard
        ClipboardCanopy {}
    }
    Component {
        id: notifications
        NotificationCanopy {}
    }
    Component {
        id: trails
        TrailCanopy {}
    }
    Component {
        id: power
        SessionControls {
            embedded: true
        }
    }
    Component {
        id: quick
        QuickControls {
            active: root.active
        }
    }
}
