import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../services"

ColumnLayout {
    id: root
    property string highlightKey: ""
    property bool active: true
    property bool allApps: false
    property string appFilter: ""
    property string roleFilter: ""
    spacing: 12
    Component.onCompleted: if (active)
        DefaultApps.refresh()
    onActiveChanged: if (active)
        DefaultApps.refresh()
    GlowText {
        text: "Choose what opens your links and files. Changes apply to your user account immediately; Terminal controls CEDAR’s quick launch."
        color: Theme.muted
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
    }
    StationField {
        Layout.fillWidth: true
        placeholderText: "Find a default · browser, PDF, music…"
        Accessible.name: "Filter default application categories"
        onTextChanged: root.roleFilter = text.toLowerCase()
    }
    RowLayout {
        Layout.fillWidth: true
        StationField {
            Layout.fillWidth: true
            placeholderText: "Filter applications by name…"
            Accessible.name: "Filter installed applications"
            onTextChanged: root.appFilter = text
        }
        StationButton {
            text: "Refresh"
            enabled: !DefaultApps.busy
            onClicked: DefaultApps.refresh()
        }
    }
    SettingRow {
        Layout.fillWidth: true
        title: "Show all installed apps"
        description: "Off shows matching apps for each category. On allows choosing any installed application."
        StationToggle {
            checked: root.allApps
            onToggled: root.allApps = checked
        }
    }
    GlowText {
        visible: DefaultApps.busy || DefaultApps.error !== "" || DefaultApps.message !== ""
        text: DefaultApps.busy ? "Reading application defaults…" : DefaultApps.error || DefaultApps.message
        color: DefaultApps.error ? Theme.amber : Theme.teal
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
    }
    Repeater {
        model: DefaultApps.data.roles
        SettingRow {
            id: row
            required property var modelData
            readonly property var options: DefaultApps.choices(modelData, root.allApps, root.appFilter)
            objectName: modelData.id
            Layout.fillWidth: true
            visible: !root.roleFilter || (modelData.label + " " + modelData.description).toLowerCase().includes(root.roleFilter)
            highlighted: root.highlightKey === modelData.id
            title: modelData.label
            description: modelData.description + (modelData.mixed ? " Some formats currently use different apps." : "") + (options.length === 1 ? " No matching installed app; try Show all installed apps." : "")
            StationCombo {
                Layout.fillWidth: true
                model: row.options
                textRole: "label"
                enabled: !DefaultApps.busy
                currentIndex: Math.max(0, row.options.findIndex(a => a.id === DefaultApps.selected(row.modelData)))
                onActivated: if (row.options[currentIndex].id)
                    DefaultApps.apply(row.modelData.id, row.options[currentIndex].id)
                Accessible.name: row.modelData.label
            }
        }
    }
    SettingsHeading {
        text: "Advanced quick-launch commands"
    }
    GlowText {
        text: "Optional CEDAR-only overrides. Selecting an app above updates its matching quick-launch command. Reset below resets these overrides, not your file associations."
        color: Theme.muted
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
    }
    SettingsFields {
        Layout.fillWidth: true
        page: "apps"
        highlightKey: root.highlightKey
    }
}
