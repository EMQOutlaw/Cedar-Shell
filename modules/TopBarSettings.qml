import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../components/SettingsSchema.js" as Schema

ColumnLayout {
    id: root
    property string highlightKey: ""
    spacing: 16
    readonly property var layouts: [
        {key:"cedar", title:"CEDAR", detail:"Original angular frame"},
        {key:"floating", title:"Floating", detail:"Rounded, with edge spacing"},
        {key:"minimal", title:"Full Width", detail:"Clean, edge to edge"},
        {key:"islands", title:"Islands", detail:"Workspaces, clock and status apart"},
        {key:"center", title:"Center", detail:"Compact, around the clock"},
        {key:"split", title:"Split", detail:"Two edge groups, open center"}
    ]

    SettingsSection {
        objectName: "barStyle"
        heading: "Layout"; caption: "Every layout keeps CEDAR Core centered on the display. Changes are saved as you choose."
        badge: root.layouts.find(l => l.key === Config.barStyle)?.title || ""; badgeColor: Theme.green
        GridLayout {
            Layout.fillWidth: true; columns: root.width < 560 ? 2 : 3; columnSpacing: 10; rowSpacing: 10
            Repeater {
                model: root.layouts
                StationButton {
                    id: tile
                    required property var modelData
                    readonly property bool inUse: Config.barStyle === modelData.key
                    Layout.fillWidth: true; Layout.preferredWidth: 170; implicitHeight: 108
                    checked: inUse
                    Accessible.name: modelData.title + " bar layout" + (inUse ? ", in use" : "")
                    onClicked: Config.set("barStyle", modelData.key)
                    background: Rectangle {
                        radius: 10; color: tile.inUse ? Qt.alpha(Theme.green, .06) : Theme.background
                        border.width: tile.inUse || tile.visualFocus ? 2 : 1
                        border.color: tile.inUse || tile.visualFocus ? Theme.green : tile.hovered ? Qt.alpha(Theme.teal, .45) : Qt.alpha(Theme.teal, .14)
                    }
                    contentItem: ColumnLayout {
                        spacing: 6
                        BarLayoutPreview { Layout.fillWidth: true; implicitHeight: 42; style: tile.modelData.key }
                        Text { text: tile.modelData.title.toUpperCase(); textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: Theme.small; font.letterSpacing: 1; color: tile.inUse ? Theme.green : Theme.text }
                        Text { Layout.fillWidth: true; text: tile.modelData.detail; textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: 10; color: Theme.muted; elide: Text.ElideRight }
                    }
                }
            }
        }
    }

    SettingsSection {
        heading: "Shape"; caption: "Height, spacing and transparency apply to every layout; margin and corners apply where the bar is detached."
        SettingsFields { page: "bar"; cards: false; highlightKey: root.highlightKey; Layout.fillWidth: true }
    }

    SettingsSection {
        objectName: "modules"
        heading: "Modules"
        caption: "What appears on the bar. The center always opens Quick Controls, with network status beside it; available space decides which edge modules fit."
        Repeater {
            model: Schema.modules
            SettingRow {
                required property var modelData
                Layout.fillWidth: true
                title: modelData.label
                description: modelData.key === "activeWindow" ? "Shown in the CEDAR, Floating and Full Width layouts." : ""
                StationToggle {
                    Layout.fillWidth: true
                    accessibleLabel: modelData.label
                    checked: Config.moduleEnabled(modelData.key)
                    onToggled: value => Config.setModule(modelData.key, value)
                }
            }
        }
    }
}
