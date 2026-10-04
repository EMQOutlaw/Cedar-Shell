import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "../.."
import ".."
import "../../services"

ColumnLayout {
    id: root
    property var activity: CoreService.foreground
    property bool recent: false
    spacing: 12
    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }
    ColumnLayout {
        visible: !root.activity
        Layout.fillWidth: true
        spacing: 4
        GlowText {
            text: Config.formatTime(clock.date)
            font.pixelSize: 36
            font.family: Theme.dataFont
            color: Theme.text
        }
        GlowText {
            text: Config.formatDate(clock.date)
            color: Theme.muted
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }
    }
    Loader {
        Layout.fillWidth: true
        active: !!root.activity
        sourceComponent: activity?.type === "media" ? media : activity?.type === "volume" || activity?.type === "brightness" ? volume : details
    }
    Component {
        id: media
        CoreMedia {
            detailed: CoreService.expanded
        }
    }
    Component {
        id: volume
        CoreVolume {
            volume: root.activity?.type === "volume"
        }
    }
    Component {
        id: details
        CoreDetails {
            activity: root.activity
        }
    }
    RowLayout {
        Layout.fillWidth: true
        GlowText {
            text: "ACTIVE NOW"
            color: Theme.teal
            Layout.fillWidth: true
            font.pixelSize: Theme.small
        }
        StationButton {
            visible: root.activity && !["recording", "microphone", "camera", "volume", "brightness"].includes(root.activity.type)
            text: "Dismiss"
            onClicked: CoreService.dismiss(root.activity.id)
        }
    }
    ListView {
        id: list
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(160, contentHeight)
        clip: true
        spacing: 4
        model: CoreService.rows
        keyNavigationEnabled: true
        ScrollBar.vertical: ScrollBar {}
        Keys.onReturnPressed: if (currentItem)
            currentItem.clicked()
        delegate: StationButton {
            required property var modelData
            width: ListView.view.width
            implicitHeight: 42
            text: modelData.icon + "  " + modelData.title
            checked: root.activity?.id === modelData.id
            hint: modelData.subtitle
            onClicked: CoreService.model.selectedId = modelData.id
        }
    }
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 1
        color: Qt.alpha(Theme.teal, .15)
    }
    RowLayout {
        Layout.fillWidth: true
        StationField {
            id: minutes
            Layout.fillWidth: true
            placeholderText: "Timer · minutes"
            Accessible.name: "Timer duration in minutes"
            validator: DoubleValidator {
                bottom: 1 / 60
                top: 1440
            }
            onAccepted: start.clicked()
        }
        StationButton {
            id: start
            text: "Start timer"
            enabled: !CoreService.timer.active && minutes.acceptableInput && Number(minutes.text) > 0
            onClicked: {
                if (CoreService.timer.start(Number(minutes.text) * 60)) {
                    CoreService.model.selectedId = "timer";
                    minutes.text = "";
                }
            }
        }
    }
    Flow {
        Layout.fillWidth: true
        spacing: 6
        StationButton {
            text: root.recent ? "Hide recent" : "Recent activities"
            checked: root.recent
            onClicked: root.recent = !root.recent
        }
        StationButton {
            text: "Check updates"
            enabled: !CoreService.actionBusy
            onClicked: CoreService.run({
                action: "check-updates"
            })
        }
        StationButton {
            text: "Settings"
            onClicked: {
                CoreService.collapse();
                ShellState.settingsPage = "core";
                ShellState.open("settings");
            }
        }
    }
    ColumnLayout {
        visible: root.recent
        Layout.fillWidth: true
        Repeater {
            model: root.recent ? CoreService.model.history.slice(0, 8) : []
            GlowText {
                required property var modelData
                text: modelData.icon + "  " + modelData.title + " · " + Math.max(0, Math.floor((CoreService.now - modelData.timestamp) / 60000)) + "m"
                color: Theme.muted
                font.pixelSize: Theme.small
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
        }
        GlowText {
            visible: !CoreService.model.history.length
            text: "No recent system activities."
            color: Theme.muted
        }
        StationButton {
            visible: CoreService.model.history.length > 0
            text: "Clear recent activities"
            onClicked: CoreService.model.clearHistory()
        }
    }
    GlowText {
        visible: root.activity?.id === "updates" && CoreService.packages.length > 0
        text: CoreService.packages.slice(0, 15).join("\n") + (CoreService.packages.length > 15 ? "\n… and more in the update menu" : "")
        color: Theme.muted
        font.pixelSize: Theme.small
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
    }
    GlowText {
        visible: CoreService.error !== "" || CoreService.message !== ""
        text: CoreService.error || CoreService.message
        color: CoreService.error ? Theme.amber : Theme.muted
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        font.pixelSize: Theme.small
    }
}
