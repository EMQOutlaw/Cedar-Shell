import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "../.."
import ".."
import "../../services"
import "../../modules"

// The Signals hub: the foreground signal's card, the rest of the stack, and
// the two ledgers the pill keeps, recent system activities and the
// notification history (the Notifications topic's own list, shown in place).

ColumnLayout {
    id: root
    property var activity: CoreService.foreground
    property bool recent: false
    property bool notices: false
    spacing: 12
    SystemClock {
        id: clock
        enabled: CoreService.expanded
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
            color: Theme.strataText
        }
        GlowText {
            text: Config.formatDate(clock.date)
            color: Theme.strataMuted
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
            detailed: true
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
        SectionMark { text: "ACTIVE NOW"; tone: Theme.strataAccent; Layout.fillWidth: true }
        StrataButton {
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
        StrataButton {
            required property var modelData
            Layout.fillWidth: true
            implicitHeight: 34
            hint: modelData.subtitle
            Accessible.name: modelData.title
            onClicked: CoreService.model.selectedId = modelData.id
            contentItem: RowLayout {
                spacing: 10
                Rectangle { implicitWidth: 5; implicitHeight: 5; radius: 3; color: modelData.priority >= 3 || ["recording", "microphone", "camera"].includes(modelData.type) ? Theme.ember : modelData.priority === 2 ? Theme.amber : Theme.strataAccent }
                Text { Layout.fillWidth: true; text: modelData.title; textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: Theme.small; color: Theme.strataText; elide: Text.ElideRight }
                Text { text: modelData.icon || ""; textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: Theme.small; color: Theme.strataMuted }
            }
        }
    }
    StrataButton {
        visible: root.others.length > 3
        text: root.allOthers ? "Show fewer" : (root.others.length - 3) + " more"
        checked: root.allOthers
        onClicked: root.allOthers = !root.allOthers
    }
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 1
        color: Qt.alpha(Theme.strataAccent, .15)
    }
    Flow {
        Layout.fillWidth: true
        spacing: 6
        StrataButton {
            text: root.notices ? "Hide notifications" : "Notifications" + (NoticeStore.history.length ? " · " + NoticeStore.history.length : "")
            checked: root.notices
            onClicked: { root.notices = !root.notices; if (root.notices) root.recent = false; }
        }
        StrataButton {
            text: root.recent ? "Hide recent" : "Recent activities"
            checked: root.recent
            onClicked: { root.recent = !root.recent; if (root.recent) root.notices = false; }
        }
        StrataButton {
            text: "Check updates"
            enabled: !CoreService.actionBusy
            onClicked: CoreService.run({
                action: "check-updates"
            })
        }
        StrataButton {
            objectName: "upgradeSystemButton"
            text: "Upgrade system"
            hint: "Run Topgrade in a terminal"
            enabled: !CoreService.actionBusy
            onClicked: CoreService.run({ action: "upgrade-system" })
        }
    }
    Loader {
        visible: root.notices
        active: root.notices
        Layout.fillWidth: true
        // Already in view: the list settles at once instead of on the Canopy's entrance clock.
        sourceComponent: NotificationCanopy { beat: (order, span) => 1 }
    }
    ColumnLayout {
        visible: root.recent
        Layout.fillWidth: true
        Repeater {
            model: root.recent ? CoreService.model.history.slice(0, 8) : []
            GlowText {
                required property var modelData
                text: modelData.icon + "  " + modelData.title + " · " + Math.max(0, Math.floor((CoreService.now - modelData.timestamp) / 60000)) + "m"
                color: Theme.strataMuted
                font.pixelSize: Theme.small
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
        }
        GlowText {
            visible: !CoreService.model.history.length
            text: "No recent system activities."
            color: Theme.strataMuted
        }
        StrataButton {
            visible: CoreService.model.history.length > 0
            text: "Clear recent activities"
            onClicked: CoreService.model.clearHistory()
        }
    }
    GlowText {
        visible: root.activity?.id === "updates" && CoreService.packages.length > 0
        text: CoreService.packages.slice(0, 15).join("\n") + (CoreService.packages.length > 15 ? "\n… and more in the update menu" : "")
        color: Theme.strataMuted
        font.pixelSize: Theme.small
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
    }
    GlowText {
        visible: CoreService.error !== "" || CoreService.message !== ""
        text: CoreService.error || CoreService.message
        color: CoreService.error ? Theme.amber : Theme.strataMuted
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        font.pixelSize: Theme.small
    }
}
