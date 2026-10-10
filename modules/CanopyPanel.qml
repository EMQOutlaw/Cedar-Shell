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
    // The tab strip is the header of the tabbed Canopy: Controls first, the
    // first few topics, and the rest behind "More". A standalone panel names
    // itself with a section mark instead. One tagline per topic sits beside
    // the section mark under the strip, in the station's voice.
    readonly property int primaryTabs: width < 600 ? 2 : 3
    readonly property bool secondaryActive: Canopy.tabs.indexOf(topic) >= primaryTabs
    property bool moreOpen: false
    onTopicChanged: moreOpen = false
    readonly property bool nerd: Theme.availableFonts.includes("JetBrainsMono Nerd Font")
    function tabLabel(value) {
        return ({ audio: "Audio", network: "Connections", bluetooth: "Bluetooth", power: "Power", system: "System", weather: "Sky", calendar: "Time",
                  clipboard: "Clipboard", notifications: "Notes", quick: "Controls", trails: "Trails", station: "Station", go: "Apps", startup: "Startup", workspaces: "Spaces" })[value] || value;
    }
    function tagline(value) {
        return ({ quick: "One place. Everything close.", audio: "What is playing, and where.", bluetooth: "Nearby and paired.", system: "Readings from the station.",
                  weather: "The sky over the station.", calendar: "The days ahead.", clipboard: "What you copied, kept here.", notifications: "What asked for you.",
                  trails: "Where you have been.", startup: "What rises with the shell." })[value] || "";
    }
    function sentence(value) { const t = String(value || "").toLowerCase(); return t ? t.charAt(0).toUpperCase() + t.slice(1) + "." : ""; }
    component CanopyTab: StationButton {
        id: tab
        property string topic: ""
        property string label: ""
        text: label
        implicitHeight: 28
        padding: 10
        checked: topic !== "" && root.topic === topic
        Accessible.name: label + " tab"
        background: ChamferFrame {
            cut: 5
            fill: tab.checked ? Qt.alpha(Forest.accent, .10) : tab.hovered ? Qt.alpha(Theme.teal, .05) : Theme.transparent
            stroke: tab.visualFocus ? Theme.green : tab.checked ? Qt.alpha(Forest.accent, .35) : Theme.transparent
            strokeWidth: tab.visualFocus ? 2 : 1
        }
        contentItem: Text { text: tab.text; textFormat: Text.PlainText; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; font.family: Theme.labelFont; font.pixelSize: Math.round(13 * Theme.fontScale); color: tab.checked ? Forest.accent : tab.hovered ? Theme.text : Theme.muted; elide: Text.ElideRight }
        onClicked: if (topic !== "") Canopy.open(topic)
    }
    ColumnLayout {
        id: layout
        anchors.fill: parent
        anchors.margins: 20
        spacing: 12
        RowLayout {
            // Field Station and Power bring their own header and close control.
            visible: !(root.standalone && ["station", "power"].includes(root.topic))
            Layout.fillWidth: true
            spacing: 6
            Flow {
                id: strip
                visible: !Canopy.peeking && !root.standalone && Canopy.tabs.length > 0
                Layout.fillWidth: true
                spacing: 2
                CanopyTab { topic: "quick"; label: "Controls" }
                Repeater {
                    model: Canopy.tabs
                    CanopyTab { required property string modelData; required property int index; visible: index < root.primaryTabs; topic: modelData; label: root.tabLabel(modelData) }
                }
                CanopyTab {
                    visible: Canopy.tabs.length > root.primaryTabs
                    label: (root.secondaryActive ? root.tabLabel(root.topic) : "More") + "  ▾"
                    checked: root.secondaryActive || root.moreOpen
                    hint: "More instruments"
                    onClicked: root.moreOpen = !root.moreOpen
                }
            }
            ColumnLayout {
                visible: !strip.visible
                Layout.fillWidth: true
                spacing: 2
                SectionMark {
                    // Hidden when a standalone panel's content carries its own heading.
                    visible: !(root.standalone && ["network", "go", "workspaces"].includes(root.topic))
                    Layout.fillWidth: true
                    text: Canopy.titleFor(root.topic).toUpperCase()
                    tone: Forest.accent
                    size: 10
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
                iconOnly: true
                implicitWidth: 32; implicitHeight: 28
                text: root.nerd ? (Canopy.pinned ? "󰤰" : "󰐃") : (Canopy.pinned ? "Unpin" : "Pin")
                hint: Canopy.pinned ? "Unpin · keyboard controls return" : "Pin · keep one Canopy visible"
                checked: Canopy.pinned
                onClicked: Canopy.pin()
            }
            StationButton {
                iconOnly: true
                implicitWidth: 32; implicitHeight: 28
                text: root.nerd ? "󰅖" : "×"
                hint: "Close Canopy"
                onClicked: Canopy.close()
            }
        }
        // The instruments behind "More", on their own row while it is open.
        Flow {
            visible: strip.visible && root.moreOpen
            Layout.fillWidth: true
            spacing: 2
            Repeater {
                model: Canopy.tabs
                CanopyTab { required property string modelData; required property int index; visible: index >= root.primaryTabs; topic: modelData; label: root.tabLabel(modelData) }
            }
        }
        // The section mark names the open instrument; its tagline sits opposite.
        RowLayout {
            visible: strip.visible
            Layout.fillWidth: true
            spacing: 12
            SectionMark { text: Canopy.titleFor(root.topic).toUpperCase(); tone: Forest.accent; size: 10 }
            Item { Layout.fillWidth: true }
            Text {
                text: root.tagline(root.topic)
                textFormat: Text.PlainText
                font.family: Theme.labelFont; font.pixelSize: Math.round(12 * Theme.fontScale)
                color: Theme.muted
                elide: Text.ElideRight
                Layout.maximumWidth: root.width * .55
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
                        go: go,
                        startup: startup,
                        workspaces: workspaces
                    })[root.topic]
            }
        }
        // Footer: the forest's word on the left, the two ways onward on the right.
        RowLayout {
            visible: !Canopy.peeking && !root.standalone
            Layout.fillWidth: true
            spacing: 8
            Rectangle { width: 5; height: 5; radius: 3; color: Canopy.pinned ? Theme.green : Forest.accent; opacity: .8; Layout.alignment: Qt.AlignVCenter }
            Text {
                Layout.fillWidth: true
                text: Canopy.pinned ? "Pinned. One instrument stays with you." : root.sentence(Forest.phrase)
                textFormat: Text.PlainText
                font.family: Theme.labelFont; font.pixelSize: Math.round(13 * Theme.fontScale)
                color: Theme.muted
                elide: Text.ElideRight
            }
            StationButton {
                text: "Signals"
                implicitHeight: 28
                onClicked: {
                    Canopy.close();
                    CoreService.expand();
                }
            }
            StationButton {
                objectName: "fullSettings"
                text: "Settings  ↗"
                implicitHeight: 28
                accent: Forest.accent
                onClicked: {
                    Canopy.close();
                    ShellState.settingsPage = "overview";
                    ShellState.open("settings");
                }
            }
        }
    }
    Component {
        id: workspaces
        WorkspaceCanopy { active: root.active }
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
        id: startup
        StartupCanopy {
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
