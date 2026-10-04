import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../components/SettingsSchema.js" as Schema

ColumnLayout {
    id: root
    property string highlightKey: ""
    spacing: Theme.gap
    SettingsHeading {
        text: "Bar layout"
        objectName: "barStyle"
    }
    GlowText {
        text: "Choose a bar layout in CEDAR’s own colors and angular style. Changes are saved automatically."
        color: Theme.muted
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }
    GridLayout {
        Layout.fillWidth: true
        columns: root.width < 490 ? 1 : 3
        columnSpacing: 8
        rowSpacing: 8
        Repeater {
            model: [
                {
                    key: "cedar",
                    title: "CEDAR",
                    detail: "Original angular frame"
                },
                {
                    key: "floating",
                    title: "FLOATING",
                    detail: "Rounded with edge spacing"
                },
                {
                    key: "minimal",
                    title: "FULL WIDTH",
                    detail: "Clean, edge-to-edge bar"
                },
                {
                    key: "islands",
                    title: "ISLANDS",
                    detail: "Workspaces, clock, and status in separate islands"
                },
                {
                    key: "center",
                    title: "CENTER",
                    detail: "A compact bar grouped around the clock"
                },
                {
                    key: "split",
                    title: "SPLIT",
                    detail: "Two edge groups with an open center"
                }
            ]
            ColumnLayout {
                id: preset
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredWidth: 160
                spacing: 4
                BarLayoutPreview {
                    Layout.fillWidth: true
                    implicitHeight: 42
                    style: preset.modelData.key
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Config.set("barStyle", preset.modelData.key)
                    }
                }
                StationButton {
                    Layout.fillWidth: true
                    implicitHeight: 48
                    text: preset.modelData.title
                    checked: Config.barStyle === preset.modelData.key
                    onClicked: Config.set("barStyle", preset.modelData.key)
                }
                GlowText {
                    Layout.fillWidth: true
                    text: preset.modelData.detail
                    font.pixelSize: Theme.small
                    color: Theme.muted
                    wrapMode: Text.WordWrap
                }
            }
        }
    }
    SettingsFields {
        page: "bar"
        highlightKey: root.highlightKey
        Layout.fillWidth: true
    }
    SettingsHeading {
        text: "Modules"
        objectName: "modules"
    }
    GlowText {
        text: "Changes appear immediately. The center opens Quick Controls; network status lives beside it. Audio and Full Settings are available in the shared Canopy. Available space determines which edge modules are shown."
        color: Theme.muted
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        font.pixelSize: Theme.small
    }
    Repeater {
        model: Schema.modules
        SettingRow {
            required property var modelData
            Layout.fillWidth: true
            title: modelData.label
            description: modelData.key === "activeWindow" ? "Available in CEDAR, Floating, and Full Width layouts." : ""
            StationToggle {
                Layout.fillWidth: true
                accessibleLabel: modelData.label
                checked: Config.moduleEnabled(modelData.key)
                onToggled: value => Config.setModule(modelData.key, value)
            }
        }
    }
}
