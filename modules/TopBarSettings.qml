import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../components/SettingsSchema.js" as Schema

ColumnLayout {
    id: root
    property string highlightKey: ""
    spacing: 16
    SettingsSection {
        heading: "Shape"; caption: "CEDAR Strata uses one continuous frame. Adjust its height and transparency."
        SettingsFields { page: "bar"; cards: false; highlightKey: root.highlightKey; Layout.fillWidth: true }
    }

    SettingsSection {
        objectName: "modules"
        heading: "Modules"
        caption: "Signals sit in the center. Connections, audio, the clock and Quick Controls share the right rail. Optional detail recedes as space narrows."
        Repeater {
            model: Schema.modules
            SettingRow {
                required property var modelData
                Layout.fillWidth: true
                title: modelData.label
                description: modelData.key === "activeWindow" ? "Shows the focused application when space permits." : ""
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
