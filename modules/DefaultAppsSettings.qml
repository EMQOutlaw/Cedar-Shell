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
    property bool moreAssociations: false
    readonly property var mainRoles: ["browser","terminal","files","editor"]
    property string appFilter: ""
    property string roleFilter: ""
    readonly property var roles: DefaultApps.data.roles || []
    readonly property var otherRoles: roles.filter(r => !mainRoles.includes(r.id))
    spacing: 16
    Component.onCompleted: if (active) DefaultApps.refresh()
    onActiveChanged: if (active) DefaultApps.refresh()

    component RoleRow: SettingRow {
        id: row
        required property var modelData
        readonly property var options: DefaultApps.choices(modelData, root.allApps, root.appFilter)
        objectName: modelData.id
        Layout.fillWidth: true
        highlighted: root.highlightKey === modelData.id
        title: modelData.label
        description: modelData.description + (modelData.mixed ? " Some formats currently use different apps." : "") + (options.length === 1 ? " No matching installed app; turn on Show every installed app." : "")
        StationCombo {
            Layout.fillWidth: true
            model: row.options
            textRole: "label"
            enabled: !DefaultApps.busy
            currentIndex: Math.max(0, row.options.findIndex(a => a.id === DefaultApps.selected(row.modelData)))
            onActivated: if (row.options[currentIndex].id) DefaultApps.apply(row.modelData.id, row.options[currentIndex].id)
            Accessible.name: row.modelData.label
        }
    }

    RowLayout {
        Layout.fillWidth: true; spacing: 12
        Rectangle { width: 8; height: 8; radius: 4; color: DefaultApps.error ? Theme.amber : root.roles.length ? Theme.green : Theme.muted }
        GlowText {
            Layout.fillWidth: true; wrapMode: Text.WordWrap; font.pixelSize: Theme.small
            text: DefaultApps.busy ? "Reading application defaults…" : DefaultApps.error || DefaultApps.message || "Changes apply to your user account immediately."
            color: DefaultApps.error ? Theme.amber : Theme.text
        }
        StationButton { text: "Refresh"; enabled: !DefaultApps.busy; onClicked: DefaultApps.refresh() }
    }

    SettingsSection {
        heading: "Everyday apps"; caption: "What opens your links, folders and text. Terminal also sets CEDAR’s quick launch."
        Repeater {
            model: root.mainRoles.map(id => root.roles.find(r => r.id === id)).filter(Boolean)
            RoleRow {}
        }
    }

    SettingsSection {
        heading: "File and link associations"
        caption: root.otherRoles.length + " more kinds of files and links. Your current associations stay until you choose a replacement."
        GridLayout {
            Layout.fillWidth: true; columns: root.width < 600 ? 1 : 2; columnSpacing: 8; rowSpacing: 8
            StationField { Layout.fillWidth: true; placeholderText: "Find a type · PDF, music, torrent…"; Accessible.name: "Filter default application categories"; onTextChanged: root.roleFilter = text.toLowerCase() }
            StationField { Layout.fillWidth: true; placeholderText: "Filter apps by name…"; Accessible.name: "Filter installed applications"; onTextChanged: root.appFilter = text }
        }
        StationToggle {
            Layout.fillWidth: true; label: "Show every installed app"
            description: "Off lists apps that declare support for each type. On allows any installed application."
            checked: root.allApps; onToggled: value => root.allApps = value
        }
        Repeater {
            model: root.otherRoles.filter(role => root.moreAssociations || root.roleFilter || root.highlightKey === role.id)
            RoleRow { visible: !root.roleFilter || (modelData.label + " " + modelData.description).toLowerCase().includes(root.roleFilter) }
        }
        StationButton {
            visible: !root.roleFilter
            text: root.moreAssociations ? "Show fewer" : "Show all " + root.otherRoles.length + " associations"
            checked: root.moreAssociations
            onClicked: root.moreAssociations = !root.moreAssociations
        }
    }

    SettingsSection {
        heading: "Quick launch commands"
        caption: "Optional CEDAR-only overrides used by Go and Core. Choosing an everyday app above updates the matching command. Reset only clears these overrides, never your file associations."
        SettingsFields { Layout.fillWidth: true; page: "apps"; groups: ["Quick launch"]; cards: false; highlightKey: root.highlightKey }
    }
}
