import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../services"
ColumnLayout {
    id: root
    property string highlightKey:""
    property bool browseThemes:false
    spacing:12
    SettingsHeading { text:"Theme"; objectName:"theme" }
    SettingsCard {
        Layout.fillWidth:true
        GlowText { text:SettingsInfo.data.theme; font.family:Theme.labelFont; font.pixelSize:30; color:Theme.green }
        GlowText { text:"Quiet light. Familiar tools."; color:Theme.muted }
        Row { spacing:8; Repeater { model:[Theme.background,Theme.surface,Theme.elevated,Theme.green,Theme.teal,Theme.amber,Theme.ember]; Rectangle { required property color modelData; width:24; height:24; radius:12; color:modelData; border.color:Theme.border } } }
        GlowText { text:"CEDAR themes apply to this shell. Add local JSON palettes in the CEDAR themes folder; your applications and desktop session stay running."; color:Theme.muted; Layout.fillWidth:true; wrapMode:Text.WordWrap; font.pixelSize:Theme.small }
    }
    StationButton { text:root.browseThemes ? "Close theme library":"Browse installed themes"; checked:root.browseThemes; onClicked:root.browseThemes=!root.browseThemes }
    GridLayout {
        visible:root.browseThemes; Layout.fillWidth:true; columns:root.width<550 ? 2:3; columnSpacing:8; rowSpacing:8
        Repeater {
            model:root.browseThemes ? SettingsInfo.data.themes:[]
            ColumnLayout {
                required property var modelData
                Layout.fillWidth:true; Layout.preferredWidth:180; spacing:2
                Rectangle {
                    Layout.fillWidth:true; implicitHeight:82; color:Theme.surface; radius:8; clip:true
                    Image { anchors.fill:parent; source:Config.imageSource(modelData.preview); fillMode:Image.PreserveAspectCrop; sourceSize.width:640; asynchronous:true }
                    GlowText { anchors.centerIn:parent; visible:!modelData.preview; text:modelData.label; color:Theme.muted }
                }
                StationButton { text:modelData.label; Layout.fillWidth:true; checked:modelData.name.toLowerCase()===SettingsInfo.data.theme.toLowerCase(); enabled:!SettingsInfo.busy; onClicked:SettingsInfo.run({action:"theme",name:modelData.name}) }
            }
        }
    }
    SettingsFields { page:"appearance"; highlightKey:root.highlightKey; Layout.fillWidth:true }
    SettingsCard {
        Layout.fillWidth:true
        GlowText { text:"Field notes, clearly spoken."; font.family:Theme.labelFont; font.pixelSize:Math.round(26*Theme.fontScale); Layout.fillWidth:true; wrapMode:Text.WordWrap }
        GlowText { text:"Aa Bb Cc · 0123456789 · 12:48"; font.family:Theme.dataFont; font.pixelSize:Theme.normal; color:Theme.muted; Layout.fillWidth:true; wrapMode:Text.WordWrap }
    }
}
