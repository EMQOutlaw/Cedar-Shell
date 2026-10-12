import QtQuick
import QtQuick.Layouts
import Quickshell
import ".."
import "../components"
import "../services"

ColumnLayout {
    id: root
    property int offset: 0
    property int selectedDay: new Date().getDate()
    property bool manage: false
    readonly property var selectedDate: new Date(month.getFullYear(), month.getMonth(), Math.min(selectedDay, days))
    readonly property var agenda: CalendarFeeds.eventsOn(selectedDate)
    onMonthChanged: CalendarFeeds.viewMonth(month)
    Component.onCompleted: CalendarFeeds.viewMonth(month)
    readonly property var month: new Date(clock.date.getFullYear(), clock.date.getMonth() + offset, 1)
    readonly property int days: new Date(month.getFullYear(), month.getMonth() + 1, 0).getDate()
    spacing: 16
    SystemClock { id: clock; precision: SystemClock.Minutes }
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 4
        GlowText {
            text: Config.formatTime(clock.date)
            font.family: Theme.dataFont
            font.pixelSize: Math.round(34 * Theme.fontScale)
            color: Theme.strataText
        }
        GlowText {
            Layout.fillWidth: true
            text: Config.formatDate(clock.date, true)
            color: Theme.strataMuted
            wrapMode: Text.WordWrap
        }
    }
    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Qt.alpha(Theme.strataGrain, .6) }
    RowLayout {
        Layout.fillWidth: true
        StrataButton { text: "‹"; hint: "Previous month"; iconOnly: true; onClicked: root.offset-- }
        GlowText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: Qt.formatDateTime(root.month, "MMMM yyyy").toUpperCase()
            font.family: Theme.labelFont
            font.pixelSize: Math.round(22 * Theme.fontScale)
            font.letterSpacing: 1.4
            color: Theme.strataAccent
            elide: Text.ElideRight
        }
        StrataButton { text: "›"; hint: "Next month"; iconOnly: true; onClicked: root.offset++ }
        StrataButton { text: "Today"; onClicked: { root.offset = 0; root.selectedDay = clock.date.getDate(); } }
    }
    GridLayout {
        Layout.fillWidth: true
        columns: 7
        uniformCellWidths: true
        rowSpacing: 5; columnSpacing: 5
        Repeater {
            model: ["S", "M", "T", "W", "T", "F", "S"]
            GlowText {
                required property string modelData
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: modelData
                font.family: Theme.dataFont
                font.pixelSize: Theme.small
                color: Theme.strataMuted
            }
        }
        Repeater {
            model: 42
            Item {
                id: cell
                required property int index
                readonly property int day: index - root.month.getDay() + 1
                readonly property bool selected: day === root.selectedDate.getDate()
                readonly property int eventCount: day > 0 && day <= root.days ? CalendarFeeds.eventsOn(new Date(root.month.getFullYear(), root.month.getMonth(), day)).length : 0
                readonly property bool today: root.offset === 0 && day === clock.date.getDate()
                Layout.fillWidth: true
                implicitHeight: Math.round(34 * Theme.fontScale)
                ChamferFrame {
                    anchors.fill: parent
                    visible: cell.today || cell.selected
                    cut: Theme.strataCut / 2
                    fill: Qt.tint(Theme.strataFoundation, Qt.alpha(Theme.strataAccent, .12))
                    stroke: Qt.alpha(Theme.strataAccent, cell.selected ? .85 : .35)
                }
                Rectangle {
                    visible: cell.eventCount > 0; width: 4; height: 4; radius: 2
                    anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 2
                    color: Theme.strataAccent
                }
                MouseArea { anchors.fill: parent; enabled: cell.day > 0 && cell.day <= root.days; onClicked: root.selectedDay = cell.day; cursorShape: Qt.PointingHandCursor }
                Accessible.role: Accessible.Button
                Accessible.name: cell.day > 0 && cell.day <= root.days ? cell.day + ", " + cell.eventCount + " events" : ""
                activeFocusOnTab: cell.day > 0 && cell.day <= root.days
                Keys.onReturnPressed: root.selectedDay = cell.day
                Keys.onSpacePressed: root.selectedDay = cell.day
                GlowText {
                    anchors.centerIn: parent
                    text: cell.day > 0 && cell.day <= root.days ? String(cell.day) : ""
                    color: cell.today ? Theme.strataAccent : Theme.strataText
                }
            }
        }
    }
    RowLayout {
        Layout.fillWidth: true
        SectionMark { Layout.fillWidth: true; text: Qt.formatDateTime(root.selectedDate, "ddd, MMM d").toUpperCase(); tone: Theme.strataAccent }
        StrataButton { text: CalendarFeeds.busy ? "Refreshing…" : "Refresh"; enabled: CalendarFeeds.configured && !CalendarFeeds.busy && !Config.localOnly; onClicked: CalendarFeeds.refresh(true) }
        StrataButton { text: root.manage ? "Done" : "Calendars"; checked: root.manage; onClicked: root.manage = !root.manage }
    }
    GlowText {
        visible: Config.localOnly
        Layout.fillWidth: true; wrapMode: Text.WordWrap; font.pixelSize: Theme.small; color: Theme.amber
        text: "Local-only mode is on. Saved events and file imports work offline. Turn it off in Settings → Desktop → Privacy to refresh connected calendars."
    }
    StrataButton { visible: Config.localOnly; text: "Open privacy settings"; onClicked: { ShellState.settingsPage = "desktop"; ShellState.open("settings"); } }
    GlowText {
        visible: CalendarFeeds.error !== "" || CalendarFeeds.message !== ""
        Layout.fillWidth: true; wrapMode: Text.WordWrap; font.pixelSize: Theme.small
        color: CalendarFeeds.error ? Theme.amber : Theme.strataMuted
        text: CalendarFeeds.error || CalendarFeeds.message
    }
    GlowText {
        visible: CalendarFeeds.sources.some(s => s.enabled && s.status === "error") && !root.manage
        Layout.fillWidth: true; wrapMode: Text.WordWrap; font.pixelSize: Theme.small; color: Theme.amber
        text: "A calendar could not refresh. Saved events are shown where available. Open Calendars for details."
    }
    GlowText {
        visible: root.agenda.length === 0 && !CalendarFeeds.busy
        Layout.fillWidth: true; wrapMode: Text.WordWrap; font.pixelSize: Theme.small; color: Theme.strataMuted
        text: !CalendarFeeds.configured ? "Connect Google or Proton to see your events here." : "No saved events for this day."
    }
    Repeater {
        model: root.agenda
        Rectangle {
            id: eventCard
            required property var modelData
            property bool expanded: false
            Layout.fillWidth: true
            implicitHeight: eventContent.implicitHeight + 20
            radius: 6; color: Qt.alpha(Theme.strataAccent, .035)
            border.color: Qt.alpha(modelData.color, .35)
            ColumnLayout {
                id: eventContent
                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 10
                spacing: 5
                RowLayout {
                    Layout.fillWidth: true
                    GlowText {
                        Layout.fillWidth: true; color: eventCard.modelData.color; font.pixelSize: Theme.small
                        text: eventCard.modelData.allDay ? "All day" : Config.formatTime(new Date(eventCard.modelData.start)) + " – " + Config.formatTime(new Date(eventCard.modelData.end))
                    }
                    GlowText { text: eventCard.modelData.calendar + (eventCard.modelData.stale ? " · saved" : ""); color: Theme.strataMuted; font.pixelSize: Theme.small - 1; elide: Text.ElideRight; Layout.maximumWidth: root.width * .55 }
                }
                GlowText { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: eventCard.modelData.title; color: Theme.strataText }
                GlowText { visible: text !== ""; Layout.fillWidth: true; wrapMode: Text.WordWrap; text: eventCard.modelData.location; color: Theme.strataMuted; font.pixelSize: Theme.small }
                StrataButton { visible: eventCard.modelData.description !== ""; text: eventCard.expanded ? "Hide details" : "Details"; onClicked: eventCard.expanded = !eventCard.expanded }
                GlowText { visible: eventCard.expanded; Layout.fillWidth: true; wrapMode: Text.WordWrap; text: eventCard.modelData.description; color: Theme.strataMuted; font.pixelSize: Theme.small }
            }
        }
    }
    GlowText { visible: CalendarFeeds.truncated; Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "This month has more than 5,000 events. Hide calendars to narrow the view."; color: Theme.amber; font.pixelSize: Theme.small }
    Loader { Layout.fillWidth: true; active: root.manage || !CalendarFeeds.configured; sourceComponent: Component { CalendarConnections {} } }
    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Qt.alpha(Theme.strataGrain, .6) }
    SectionMark { text: "TIMER"; tone: Theme.strataAccent }
    RowLayout {
        Layout.fillWidth: true
        StrataField {
            id: minutes
            Layout.fillWidth: true
            placeholderText: "Minutes (1–1440)"
            validator: IntValidator { bottom: 1; top: 1440 }
        }
        StrataButton { text: "Start"; enabled: minutes.acceptableInput; onClicked: CoreService.timer.start(Number(minutes.text) * 60, "Timer") }
    }
    GlowText {
        text: CoreService.timer.active ? Media.elapsed(CoreService.timer.remaining) + (CoreService.timer.paused ? " · paused" : "") : CoreService.timer.completed ? "Timer complete" : "No active timer"
        color: Theme.strataAccent
    }
    RowLayout {
        StrataButton { text: CoreService.timer.paused ? "Resume" : "Pause"; enabled: CoreService.timer.active; onClicked: CoreService.timer.toggle() }
        StrataButton { text: CoreService.timer.completed ? "Dismiss" : "Cancel"; enabled: CoreService.timer.active || CoreService.timer.completed; onClicked: CoreService.timer.cancel() }
    }
}
