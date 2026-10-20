import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."
import "../services"
ScrollView {
    id: root
    signal chosen(string page)
    contentWidth: availableWidth
    clip: true
    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
    ColumnLayout {
        width: root.availableWidth; spacing: 3
        Repeater {
            model: SettingsService.menu
            ColumnLayout {
                id: group
                required property var modelData
                Layout.fillWidth: true; spacing: 1
                SectionMark {
                    text: group.modelData.label.toUpperCase()
                    tone: Theme.strataMuted; size: 9
                    Layout.topMargin: 8; Layout.leftMargin: 10; Layout.bottomMargin: 3
                }
                Repeater {
                    model: group.modelData.pages.filter(p => p.rail !== false)
                    StationButton {
                        id: row
                        required property var modelData
                        objectName: "settingsNav-" + modelData.id
                        Layout.fillWidth: true; implicitHeight: Math.max(28, Theme.normal + 12)
                        text: modelData.label; checked: (({keybinds:"input",core:"bar","application-theming":"apps",setup:"advanced",time:"input",notes:"input",dictation:"apps"})[SettingsService.page] || SettingsService.page) === modelData.id
                        onClicked: root.chosen(modelData.id)
                        background: ChamferFrame {
                            cut: 4
                            fill: row.checked ? Qt.alpha(Theme.strataAccent, .075) : row.hovered ? Qt.alpha(Theme.strataSurface, .55) : Theme.transparent
                            stroke: row.visualFocus ? Theme.green : row.checked ? Qt.alpha(Theme.strataAccent, .45) : Theme.transparent
                            strokeWidth: row.visualFocus ? Theme.focusWidth : 1
                            topLine: row.checked; topLineColor: Theme.strataAccent; topLineFraction: .23
                        }
                        contentItem: RowLayout {
                            spacing: 10
                            Text { text: row.modelData.icon; font.family: Theme.dataFont; font.pixelSize: Theme.normal; color: row.checked ? Theme.green : Theme.strataMuted; Layout.preferredWidth: 18; horizontalAlignment: Text.AlignHCenter }
                            Text { text: row.modelData.label; font.family: Theme.labelFont; font.pixelSize: Theme.normal; color: row.checked ? Theme.text : Theme.strataMuted; Layout.fillWidth: true; elide: Text.ElideRight }
                        }
                    }
                }
            }
        }
    }
}
