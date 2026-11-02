import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../services"
// Advanced: only the controls that can break a desktop if used wrong. The
// page itself is flagged advanced:true, so it hides from the navigation until
// "Show advanced" is on; everything everyday lives on its own page.
ColumnLayout {
    spacing:16
    SettingsSurface {
        GlowText {text:"Specialized controls";font.family:Theme.labelFont;font.pixelSize:Theme.title}
        GlowText {text:"These pages can break your desktop if used incorrectly — ownership handovers, provider recovery and native application palettes. They are here because there is no safer place for them.";color:Theme.muted;Layout.fillWidth:true;wrapMode:Text.WordWrap}
        Repeater {
            model:[{label:"Desktop Setup",page:"setup",detail:"Ownership, providers and recovery"},{label:"Application Theming",page:"application-theming",detail:"Preview and apply native application palettes"}]
            StationButton {
                required property var modelData
                Layout.fillWidth:true;implicitHeight:58;text:modelData.label
                onClicked:SettingsService.navigate(modelData.page, "")
                contentItem:ColumnLayout {GlowText {text:parent.parent.modelData.label;font.family:Theme.labelFont;font.pixelSize:Theme.title} GlowText {text:parent.parent.modelData.detail;font.pixelSize:Theme.small;color:Theme.muted;Layout.fillWidth:true;wrapMode:Text.WordWrap}}
            }
        }
    }
}
