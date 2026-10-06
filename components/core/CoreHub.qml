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
    // The top signal is the card above; others are one line each, three at most.
    readonly property var others: CoreService.rows.filter(r => r.id !== root.activity?.id)
    property bool allOthers: false
    Repeater {
        model: root.allOthers ? root.others : root.others.slice(0, 3)
        StationButton {
            required property var modelData
            Layout.fillWidth: true
            implicitHeight: 34
            hint: modelData.subtitle
            Accessible.name: modelData.title
            onClicked: CoreService.model.selectedId = modelData.id
            contentItem: RowLayout {
                spacing: 10
                Rectangle { implicitWidth: 5; implicitHeight: 5; radius: 3; color: modelData.priority >= 3 || ["recording", "microphone", "camera"].includes(modelData.type) ? Theme.ember : modelData.priority === 2 ? Theme.amber : Theme.teal }
                Text { Layout.fillWidth: true; text: modelData.title; textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: Theme.small; color: Theme.text; elide: Text.ElideRight }
                Text { text: modelData.icon || ""; textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: Theme.small; color: Theme.muted }
            }
        }
    }
    StationButton {
        visible: root.others.length > 3
        text: root.allOthers ? "Show fewer" : (root.others.length - 3) + " more"
        checked: root.allOthers
        onClicked: root.allOthers = !root.allOthers
    }
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 1
        color: Qt.alpha(Theme.teal, .15)
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
