import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."
import "../components"
import "../services"

Overlay {
    id: root
    panelName: "themes"
    onVisibleChanged: if (visible) SettingsInfo.refresh(true)
    Loader {
        anchors.centerIn: parent
        width: Math.min(600, root.width - 32); height: Math.min(640, root.height - 32)
        active: root.visible
        sourceComponent: themePicker
    }
    Component {
    id: themePicker
    HudPanel {
        ColumnLayout {
            anchors.fill: parent
            RowLayout {
                GlowText { text: "CHOOSE THE NEXT TRAIL"; font.family: Theme.labelFont; font.pixelSize: 24; color: Theme.green; Layout.fillWidth: true }
                HudButton { text: "×"; onClicked: ShellState.close() }
            }
            GlowText { text: "Local CEDAR palettes. Your desktop session stays running."; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
            ListView {
                Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: 4
                model: SettingsInfo.data.themes
                ScrollBar.vertical: ScrollBar {}
                delegate: HudButton {
                    required property var modelData
                    width: ListView.view.width; text: modelData.label; checked: modelData.name.toLowerCase() === SettingsInfo.data.theme.toLowerCase()
                    onClicked: SettingsInfo.run({action:"theme", name:modelData.name})
                }
            }
        }
    }
    }
}
