import QtQuick
import QtQuick.Layouts
import Quickshell
import ".."
import "../components"

ColumnLayout {
    id: root
    property bool active: false
    spacing: 24
    SystemClock { id: clock; precision: SystemClock.Minutes; enabled: root.active }
    Text { text: "TIME & DATE"; font.family: Theme.labelFont; font.pixelSize: 26; font.letterSpacing: 2; color: Theme.text }
    Text { Layout.fillWidth: true; text: "Make time feel familiar. Your choice updates every CEDAR clock."; wrapMode: Text.WordWrap; font.family: Theme.dataFont; font.pixelSize: 12; color: Theme.muted }
    StationPanel {
        Layout.fillWidth: true; implicitHeight: 148
        ColumnLayout {
            anchors.fill: parent; spacing: 8
            Text { text: Config.formatTime(clock.date); color: Theme.green; font.family: Theme.labelFont; font.pixelSize: 42 }
            Text { Layout.fillWidth: true; text: Config.formatDate(clock.date); wrapMode: Text.WordWrap; color: Theme.text; font.family: Theme.dataFont; font.pixelSize: 13 }
            Text { text: Qt.formatDateTime(clock.date, "t") + " · System time"; color: Theme.muted; font.family: Theme.dataFont; font.pixelSize: 10 }
        }
    }
    Text { text: "CLOCK FORMAT"; color: Theme.teal; font.family: Theme.dataFont; font.pixelSize: 11; font.letterSpacing: 1 }
    RowLayout {
        Layout.fillWidth: true; spacing: 10
        StationButton { Layout.fillWidth: true; implicitHeight: 44; text: "12 hour · AM / PM"; checked: !Config.clock24; onClicked: Config.set("clock24", false) }
        StationButton { Layout.fillWidth: true; implicitHeight: 44; text: "24 hour · 00–23"; checked: Config.clock24; onClicked: Config.set("clock24", true) }
    }
    Text { text: "DATE FORMAT"; color: Theme.teal; font.family: Theme.dataFont; font.pixelSize: 11; font.letterSpacing: 1 }
    Flow {
        Layout.fillWidth: true; spacing: 8
        Repeater {
            model: [
                {key: "month-first", label: "Month first", sample: "MMM d, yyyy"},
                {key: "day-first", label: "Day first", sample: "d MMM yyyy"},
                {key: "iso", label: "Year first", sample: "yyyy-MM-dd"}
            ]
            StationButton {
                required property var modelData
                implicitHeight: 44
                text: modelData.label
                hint: Qt.formatDateTime(clock.date, modelData.sample)
                checked: Config.dateStyle === modelData.key
                onClicked: Config.set("dateStyle", modelData.key)
            }
        }
    }
    StationToggle { Layout.fillWidth: true; label: "Show weekday"; description: "Include the day name alongside the date."; checked: Config.saved.showWeekday; onToggled: value => Config.set("showWeekday", value) }
    StationToggle { Layout.fillWidth: true; label: "Show date in the top bar"; description: "Turn off for a time-only bar clock."; checked: Config.saved.barShowDate; onToggled: value => Config.set("barShowDate", value) }
}
