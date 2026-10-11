import QtQuick
import QtQuick.Layouts
import Quickshell
import ".."
import "../components"
import "../services"

ColumnLayout {
    id: root
    property int offset: 0
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
        StrataButton { text: "Today"; onClicked: root.offset = 0 }
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
                readonly property bool today: root.offset === 0 && day === clock.date.getDate()
                Layout.fillWidth: true
                implicitHeight: Math.round(34 * Theme.fontScale)
                ChamferFrame {
                    anchors.fill: parent
                    visible: cell.today
                    cut: Theme.strataCut / 2
                    fill: Qt.tint(Theme.strataFoundation, Qt.alpha(Theme.strataAccent, .12))
                    stroke: Qt.alpha(Theme.strataAccent, .65)
                }
                GlowText {
                    anchors.centerIn: parent
                    text: cell.day > 0 && cell.day <= root.days ? String(cell.day) : ""
                    color: cell.today ? Theme.strataAccent : Theme.strataText
                }
            }
        }
    }
    GlowText {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: "Calendar accounts are not connected."
        font.pixelSize: Theme.small
        color: Theme.strataMuted
    }
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
