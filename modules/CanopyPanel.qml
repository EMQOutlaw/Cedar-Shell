import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."
import "../components"
import "../services"

Rectangle {
    id: root
    property bool active: false
    // The topic this panel renders; the drop lags it while it cross-fades.
    property string topic: Canopy.topic
    // The drop draws the silhouette itself; the harness and fallbacks keep this frame.
    property bool framed: true
    // Standalone look (no tabs, footer or big title); the drop lags this while closing.
    property bool standalone: Canopy.standalone
    // Panel x of the control this panel descends from, or -1 for the centre.
    property real tieX: -1
    // Panels descend from the Core pill, so they share its chamfered silhouette.
    color: Theme.transparent
    clip: true
    ChamferFrame {
        visible: root.framed
        anchors.fill: parent
        cut: 12
        fill: Qt.alpha(Theme.background, Math.max(.96, Config.panelOpacity))
        stroke: Qt.alpha(Forest.accent, .25)
    }
    // A short lit line at the top edge ties the panel to the pill above it.
    Rectangle {
        visible: root.framed
        x: root.tieX >= 0 ? Math.round(Math.max(14, Math.min(root.tieX - width / 2, parent.width - width - 14))) : Math.round((parent.width - width) / 2)
        y: 0; width: 64; height: 2; radius: 1; color: Forest.accent; opacity: .7
        Behavior on x { enabled: !Theme.reducedMotion; NumberAnimation { duration: Theme.transition; easing.type: Easing.OutCubic } }
    }
    CedarAtmosphere {
        anchors.fill: parent
        anchors.margins: 8
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
    // The panel hugs its content; CanopyWindow shrinks the visible frame and mask
    // to this height without resizing the native surface.
    readonly property real preferredHeight: Math.ceil(layout.implicitHeight + 40)
    ColumnLayout {
        id: layout
        anchors.fill: parent
        anchors.margins: 20
        spacing: 12
        RowLayout {
            // Field Station brings its own header and close control.
            visible: !(root.standalone && root.topic === "station")
            Layout.fillWidth: true
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                GlowText {
                    // Hidden when a standalone panel's content carries its own heading.
                    visible: !(root.standalone && ["network", "go"].includes(root.topic))
                    text: Canopy.titleFor(root.topic).toUpperCase()
                    color: Forest.accent
                    font.family: Theme.labelFont
                    font.pixelSize: 20
                    font.letterSpacing: 2
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
                GlowText {
                    visible: Canopy.peeking
                    text: "PEEK · click the bar control to open"
                    color: Theme.muted
                    font.pixelSize: 10
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
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
        GridLayout {
            visible: !Canopy.peeking && !root.standalone && Canopy.tabs.length > 0
            Layout.fillWidth: true
            columns: Math.min(Canopy.tabs.length, root.width < 600 ? 4 : 8)
            uniformCellWidths: true
            columnSpacing: 4; rowSpacing: 4
            Repeater {
                model: Canopy.tabs
                StationButton {
                    id: tab
                    required property string modelData
                    Layout.fillWidth: true
                    implicitHeight: 28
                    checked: root.topic === modelData
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
                            trails: "Trails",
                            station: "Station",
                            go: "Apps"
                        })[modelData]
                    background: ChamferFrame {
                        cut: 5
                        fill: tab.checked ? Qt.alpha(Forest.accent, .10) : tab.hovered ? Qt.alpha(Theme.teal, .05) : Theme.transparent
                        stroke: tab.visualFocus ? Theme.green : tab.checked ? Qt.alpha(Forest.accent, .5) : Qt.alpha(Theme.teal, .12)
                        strokeWidth: tab.visualFocus ? 2 : 1
                    }
                    contentItem: Text { text: tab.text.toUpperCase(); textFormat: Text.PlainText; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; font.family: Theme.dataFont; font.pixelSize: 9; font.letterSpacing: 1.2; color: tab.checked ? Forest.accent : Theme.text; elide: Text.ElideRight }
                    onClicked: Canopy.open(modelData)
                }
            }
        }
        GlowText {
            visible: Canopy.peeking
            Layout.fillWidth: true
            Layout.fillHeight: true
            wrapMode: Text.WordWrap
            text: root.topic === "audio" ? (Audio.sink?.description || "No output") + " · " + Audio.label : root.topic === "network" ? Network.label : root.topic === "bluetooth" ? (BluetoothService.adapter?.enabled ? "Bluetooth on" : "Bluetooth off") : Forest.phrase
            color: Theme.text
        }
        ScrollView {
            visible: !Canopy.peeking
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: loader.implicitHeight
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
                        trails: trails,
                        station: station,
                        go: go
                    })[root.topic]
            }
        }
        RowLayout {
            visible: !Canopy.peeking && !root.standalone
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
                objectName: "fullSettings"
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
    Component {
        id: go
        GoCanopy {
            active: root.active
        }
    }
    Component {
        id: station
        FieldStation {
            active: root.active
            bare: !root.framed
        }
    }
}
