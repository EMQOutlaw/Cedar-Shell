import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../services"
ColumnLayout {
    spacing:16
    SettingsSurface {
        GlowText {text:"Specialized controls";font.family:Theme.labelFont;font.pixelSize:Theme.title}
        Repeater {
            model:[{label:"Desktop Setup",page:"setup",detail:"Ownership, providers and recovery"},{label:"Application Theming",page:"application-theming",detail:"Preview and apply native application palettes"},{label:"Dynamic Island",page:"core",detail:"CEDAR Core activity sources and thresholds"},{label:"Time & Date",page:"time",detail:"Clock format and calendar display"},{label:"Field Notes",page:"notes",detail:"Drawing, text and export preferences"},{label:"Dictation",page:"dictation",detail:"Microphone and voice typing"}]
            StationButton {
                required property var modelData
                Layout.fillWidth:true;implicitHeight:58;text:modelData.label
                onClicked:SettingsService.navigate(modelData.page, "")
                contentItem:ColumnLayout {GlowText {text:parent.parent.modelData.label;font.family:Theme.labelFont;font.pixelSize:Theme.title} GlowText {text:parent.parent.modelData.detail;font.pixelSize:Theme.small;color:Theme.muted;Layout.fillWidth:true;wrapMode:Text.WordWrap}}
            }
        }
    }
}
