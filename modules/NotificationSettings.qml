import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../services"
ColumnLayout {
    id: root
    property string highlightKey: ""
    readonly property var history: NoticeStore.history || []
    readonly property int critical: history.filter(n => n.critical).length
    spacing: 16
    GridLayout {
        Layout.fillWidth: true; columns: root.width < 600 ? 1 : 3; columnSpacing: 12; rowSpacing: 12
        Readout {
            label: "Popups"; lit: Config.saved.notificationsEnabled && !Config.saved.doNotDisturb
            value: !Config.saved.notificationsEnabled ? "Off" : Config.saved.doNotDisturb ? "Quiet" : "On"
            detail: !Config.saved.notificationsEnabled ? "Messages are still kept in history." : Config.saved.doNotDisturb ? "Only critical alerts appear." : "Cards appear for " + Config.saved.notificationSeconds + " seconds."
        }
        Readout { label: "History"; lit: root.history.length > 0; tone: Theme.teal; value: root.history.length + " kept"; detail: "Open it from the notification button on the bar." }
        Readout { label: "Critical"; lit: root.critical > 0; tone: Theme.amber; value: String(root.critical); detail: "Critical alerts stay until you dismiss them." }
    }
    SettingsFields {
        page: "notifications"; highlightKey: root.highlightKey; Layout.fillWidth: true
        captions: ({"Popups": "When CEDAR asks for your attention. History keeps recording either way."})
    }
}
