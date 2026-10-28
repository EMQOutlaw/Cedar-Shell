import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../services"

// Trail Rewind: the day's Forest trail as a scrubbable timeline. It replays
// history; it never restores windows or state. Trails are session-only and
// clear on lock, so after a lock this drop shows the empty state.
ColumnLayout {
    id: root
    spacing: 12
    focus: true

    // Chronological view of the trail (Forest.trails is newest-first, and a
    // breadcrumb dropped at a past moment lands out of order — sort by `at`).
    readonly property var events: Forest.trails.slice().sort((a, b) => a.at - b.at)
    property int selectedIndex: events.length - 1
    onEventsChanged: if (selectedIndex >= events.length) selectedIndex = events.length - 1
    readonly property var selected: selectedIndex >= 0 && selectedIndex < events.length ? events[selectedIndex] : null
    readonly property bool breadcrumbs: true

    readonly property double dayStart: events.length ? Math.floor(events[0].at / 3600000) * 3600000 : 0
    readonly property double dayEnd: events.length ? Math.ceil(Math.max(Date.now(), events[events.length - 1].at) / 3600000) * 3600000 : 1
    readonly property double daySpan: Math.max(3600000, dayEnd - dayStart)
    function frac(at) { return Math.max(0, Math.min(1, (at - dayStart) / daySpan)); }
    function kindColor(kind) {
        return kind === "application" ? Theme.teal
             : kind === "canopy"      ? Theme.green
             : kind === "surface"     ? Theme.strataAccent
             : kind === "breadcrumb"  ? Theme.danger
             : Theme.muted;
    }
    function kindName(kind) {
        return kind === "application" ? "Applications"
             : kind === "canopy"      ? "Canopy"
             : kind === "surface"     ? "Surfaces"
             : kind === "breadcrumb"  ? "Breadcrumbs"
             : "Settings";
    }
    function kindGlyph(kind) {
        return Theme.nerdGlyph(
            kind === "application" ? "󰀻" : kind === "canopy" ? "󰕰" : kind === "surface" ? "󰓅" : kind === "breadcrumb" ? "󰓹" : "󰒓",
            kind === "application" ? "A" : kind === "canopy" ? "C" : kind === "surface" ? "S" : kind === "breadcrumb" ? "!" : "·");
    }
    function when(at) { return Config.formatTime(new Date(at)); }
    readonly property bool canReturn: !!selected && ["canopy", "settings", "surface"].includes(selected.kind)
    readonly property string neighborLine: {
        if (!selected || selected.kind !== "breadcrumb") return "";
        const i = selectedIndex;
        const prev = events.slice(0, i).reverse().find(e => e.kind !== "breadcrumb");
        const next = events.slice(i + 1).find(e => e.kind !== "breadcrumb");
        if (!prev && !next) return "";
        if (!prev) return "Before " + next.label + " (" + when(next.at) + ") — the trail's first mark";
        if (!next) return "After " + prev.label + " (" + when(prev.at) + ") — the trail's latest mark";
        return "Between " + prev.label + " (" + when(prev.at) + ") and " + next.label + " (" + when(next.at) + ")";
    }
    function returnTo() {
        if (!canReturn) return;
        if (selected.kind === "canopy") Canopy.open(selected.target);
        else { if (selected.kind === "settings") ShellState.settingsPage = selected.target; ShellState.open(selected.kind === "settings" ? "settings" : selected.target); }
    }

    Keys.onLeftPressed: if (selectedIndex > 0) selectedIndex--
    Keys.onRightPressed: if (selectedIndex < events.length - 1) selectedIndex++
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Home) selectedIndex = 0;
        else if (event.key === Qt.Key_End) selectedIndex = events.length - 1;
    }
    Keys.onReturnPressed: returnTo()

    // ---- header -----------------------------------------------------------
    RowLayout {
        Layout.fillWidth: true
        GlowText {
            visible: events.length > 0
            text: {
                const crumbs = events.filter(e => e.kind === "breadcrumb").length;
                return events.length + " events on the trail · " + crumbs + (crumbs === 1 ? " breadcrumb" : " breadcrumbs") + " dropped by you";
            }
            font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; elide: Text.ElideRight
        }
        GlowText {
            visible: events.length > 0
            text: events.length ? when(events[0].at) + " — " + when(events[events.length - 1].at) : ""
            font.pixelSize: 10; font.letterSpacing: 1.2; color: Theme.muted
        }
    }

    // ---- timeline ----------------------------------------------------------
    Item {
        id: timeline
        Layout.fillWidth: true
        Layout.preferredHeight: 78
        visible: events.length > 0

        Repeater {
            model: Math.min(25, Math.round(root.daySpan / 3600000) + 1)
            Item {
                required property int index
                readonly property double at: root.dayStart + index * 3600000
                x: root.frac(at) * timeline.width
                anchors.top: parent.top
                Rectangle { x: -0.5; width: 1; height: 8; color: Qt.alpha(Theme.muted, .35) }
                GlowText {
                    anchors.top: parent.top; anchors.topMargin: 10
                    x: index === 0 ? 0 : Math.min(timeline.width - root.frac(at) * timeline.width - width, -width / 2)
                    visible: index % 2 === 0
                    text: Qt.formatDateTime(new Date(at), "h AP")
                    font.pixelSize: 9; color: Theme.muted
                }
            }
        }

        Rectangle {
            id: track
            anchors.left: parent.left; anchors.right: parent.right
            anchors.top: parent.top; anchors.topMargin: 36
            height: 6; radius: 3
            color: Qt.alpha(Theme.strataMuted, .18)
            Rectangle {
                width: root.selected ? root.frac(root.selected.at) * track.width : 0
                height: parent.height; radius: 3
                color: Qt.alpha(Theme.teal, .35)
            }
        }

        // Bootprints on the log. Click one to make it the moment.
        Repeater {
            model: root.events
            Item {
                required property var modelData
                required property int index
                x: root.frac(modelData.at) * timeline.width
                anchors.top: parent.top; anchors.topMargin: 32
                Accessible.name: root.kindName(modelData.kind) + " at " + root.when(modelData.at)
                readonly property bool sel: root.selectedIndex === index
                Rectangle {
                    x: -4; y: 0; width: 8; height: 8; rotation: 45
                    color: sel ? root.kindColor(modelData.kind) : Qt.alpha(root.kindColor(modelData.kind), .75)
                    border.width: sel ? 2 : 0
                    border.color: Theme.text
                }
                Rectangle {
                    visible: sel
                    x: -8; y: -4; width: 16; height: 16; rotation: 45
                    color: "transparent"
                    border.width: 1; border.color: root.kindColor(modelData.kind)
                }
                MouseArea {
                    x: -8; y: -6; width: 16; height: 20
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.selectedIndex = index
                }
            }
        }

        // Scrubber: always sits on the selected event.
        Item {
            id: scrubber
            visible: root.selected !== null
            x: root.selected ? root.frac(root.selected.at) * timeline.width : 0
            anchors.top: parent.top; anchors.topMargin: 24
            width: 0
            Accessible.name: "Trail position " + (root.selected ? root.when(root.selected.at) : "")
            Accessible.role: Accessible.Slider
            GlowText {
                x: Math.max(-x0, Math.min(timeline.width - scrubber.x - implicitWidth, -implicitWidth / 2))
                property real x0: scrubber.x
                y: -4
                text: root.selected ? root.when(root.selected.at) : ""
                font.pixelSize: 10; font.weight: Font.DemiBold; color: Theme.ember
            }
            Rectangle { x: -0.5; y: 14; width: 1; height: 46; color: Theme.ember }
            Rectangle { x: -5; y: 12; width: 10; height: 10; rotation: 45; color: Theme.ember }
        }
    }

    // ---- the selected moment ------------------------------------------------
    ChamferFrame {
        Layout.fillWidth: true
        Layout.preferredHeight: 118
        visible: events.length > 0 && root.selected !== null
        cut: 8
        fill: Qt.alpha(Theme.strataFoundation, .6)
        stroke: Qt.alpha(root.kindColor(root.selected ? root.selected.kind : "settings"), .4)
        RowLayout {
            anchors.fill: parent; anchors.margins: 16; spacing: 16
            ColumnLayout {
                spacing: 2
                GlowText { text: root.selected ? root.when(root.selected.at) : ""; font.pixelSize: 24; font.weight: Font.DemiBold; color: Theme.text }
                GlowText { text: root.selected ? root.selected.kind.toUpperCase() : ""; font.pixelSize: 9; font.letterSpacing: 1.6; color: root.kindColor(root.selected ? root.selected.kind : "settings") }
            }
            Item { Layout.preferredWidth: 1; Layout.fillHeight: true; Rectangle { width: 1; height: parent.height; color: Qt.alpha(Theme.teal, .18) } }
            ColumnLayout {
                Layout.fillWidth: true; spacing: 4
                RowLayout {
                    spacing: 8
                    GlowText { text: root.kindGlyph(root.selected ? root.selected.kind : "settings"); font.pixelSize: 15; color: root.kindColor(root.selected ? root.selected.kind : "settings") }
                    GlowText { text: root.selected ? root.selected.label : ""; font.family: Theme.labelFont; font.pixelSize: 15; color: Theme.text; Layout.fillWidth: true; elide: Text.ElideRight }
                }
                GlowText {
                    visible: root.neighborLine !== ""
                    text: root.neighborLine
                    font.pixelSize: 10; color: Theme.muted; Layout.fillWidth: true; elide: Text.ElideRight
                }
                GlowText {
                    visible: root.selected !== null && root.selected.kind === "breadcrumb"
                    text: "Dropped by you"
                    font.pixelSize: 10; color: Theme.muted
                }
            }
            StrataButton {
                Layout.alignment: Qt.AlignVCenter
                text: "RETURN TO"
                enabled: root.canReturn
                Accessible.name: root.canReturn ? "Return to " + (root.selected ? root.selected.label : "") : "Nothing to return to"
                onClicked: root.returnTo()
            }
        }
    }

    // ---- legend + actions ---------------------------------------------------
    RowLayout {
        visible: events.length > 0
        Layout.fillWidth: true; spacing: 14
        Repeater {
            model: ["application", "canopy", "surface", "settings", "breadcrumb"]
            RowLayout {
                required property string modelData
                spacing: 6
                Rectangle { width: 7; height: 7; rotation: 45; color: root.kindColor(modelData) }
                GlowText { text: root.kindName(modelData); font.pixelSize: 10; color: Theme.muted }
            }
        }
        Item { Layout.fillWidth: true }
        GlowText { text: "← → SCRUB"; font.pixelSize: 9; font.letterSpacing: 1.4; color: Theme.muted }
    }
    RowLayout {
        Layout.fillWidth: true
        GlowText {
            visible: events.length > 0
            Layout.fillWidth: true
            text: "Rewind replays the trail; it never restores windows or state. The trail stays on this machine and clears on lock."
            font.pixelSize: 10; color: Theme.muted; wrapMode: Text.WordWrap
        }
        StationButton {
            visible: Config.saved.forestTrails
            text: "Drop a breadcrumb"
            Accessible.name: "Drop a breadcrumb at the selected moment"
            onClicked: Forest.dropBreadcrumb("Marked " + (root.selected ? root.when(root.selected.at) : root.when(Date.now())), root.selected ? root.selected.at : Date.now())
        }
    }

    // ---- empty states --------------------------------------------------------
    ColumnLayout {
        visible: events.length === 0
        Layout.fillWidth: true
        Layout.topMargin: 24; Layout.bottomMargin: 24
        spacing: 6
        GlowText { Layout.alignment: Qt.AlignHCenter; text: Theme.nerdGlyph("󰓹", "·"); font.pixelSize: 28; color: Theme.muted }
        GlowText {
            Layout.alignment: Qt.AlignHCenter
            text: Config.saved.forestTrails ? "No trail under today's leaves yet." : "Trails are off."
            font.pixelSize: Theme.normal; color: Theme.muted
        }
        GlowText {
            Layout.alignment: Qt.AlignHCenter
            visible: Config.saved.forestTrails
            text: "Your navigation starts a line you can rewind."
            font.pixelSize: Theme.small; color: Theme.muted
        }
        StationToggle {
            Layout.fillWidth: true
            label: "Remember Trails"
            description: "Session-only CEDAR navigation and application identity. No window titles or page content. Cleared on lock or when disabled."
            checked: Config.saved.forestTrails
            onToggled: value => Config.set("forestTrails", value)
        }
    }
}
