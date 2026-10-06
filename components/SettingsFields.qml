import QtQuick
import QtQuick.Layouts
import ".."
import "SettingsSchema.js" as Schema
// Schema-driven preferences. With cards, each schema group becomes a section;
// without, the chosen groups render as bare rows inside a caller's section.
ColumnLayout {
    id: root
    required property string page
    property string highlightKey: ""
    property var groups: []
    property var exclude: []
    property bool cards: true
    property var captions: ({})
    readonly property var fields: Schema.fields.filter(f => f.page === page && (!groups.length || groups.includes(f.group)) && !exclude.includes(f.group))
    readonly property var groupNames: fields.map(f => f.group).filter((g, i, all) => all.indexOf(g) === i).sort((a, b) => (a === "Advanced") - (b === "Advanced"))
    property bool advanced: highlightKey !== "" && fields.some(f => f.key === highlightKey && f.group === "Advanced")
    spacing: cards ? 16 : 0
    Repeater {
        model: root.cards ? root.groupNames : []
        SettingsSection {
            id: section
            required property string modelData
            readonly property bool collapsible: modelData === "Advanced"
            heading: modelData
            caption: root.captions[modelData] || (collapsible ? "Rarely needed overrides." : "")
            accent: collapsible ? Theme.muted : Theme.teal
            StationButton {
                visible: section.collapsible
                text: root.advanced ? "Hide advanced options" : "Show advanced options"; checked: root.advanced
                onClicked: root.advanced = !root.advanced
            }
            Repeater {
                model: root.fields.filter(f => f.group === section.modelData)
                SettingControl { required property var modelData; visible: !section.collapsible || root.advanced; Layout.fillWidth: true; spec: modelData; highlightKey: root.highlightKey }
            }
        }
    }
    Repeater {
        model: root.cards ? [] : root.fields
        SettingControl { required property var modelData; Layout.fillWidth: true; spec: modelData; highlightKey: root.highlightKey }
    }
}
