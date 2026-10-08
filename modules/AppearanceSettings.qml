import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../services"
ColumnLayout {
    id: root
    property string highlightKey:""
    spacing:16
    readonly property var themes: SettingsInfo.data.themes || []
    readonly property string current: (SettingsInfo.data.theme || "").toLowerCase()

    SettingsSection {
        objectName:"theme"
        heading:"Theme"; caption:"Palettes apply to this shell immediately. Add local JSON palettes to the CEDAR themes folder; your applications keep running."
        badge:SettingsInfo.data.theme || ""; badgeColor:Theme.green
        Row { spacing:6; Repeater { model:[Theme.background,Theme.surface,Theme.elevated,Theme.border,Theme.green,Theme.teal,Theme.amber,Theme.ember,Theme.text]; Rectangle { required property color modelData; width:28; height:28; radius:6; color:modelData; border.color:Qt.alpha(Theme.text,.12) } } }
        GridLayout {
            Layout.fillWidth:true; columns:root.width<560 ? 2:3; columnSpacing:10; rowSpacing:10
            Repeater {
                model:root.themes
                StationButton {
                    id:tile
                    required property var modelData
                    readonly property bool inUse:modelData.name.toLowerCase()===root.current
                    Layout.fillWidth:true; Layout.preferredWidth:180; implicitHeight:128
                    checked:inUse; enabled:!SettingsInfo.busy
                    Accessible.name:modelData.label+(inUse ? ", in use":"")
                    onClicked:if(!inUse)SettingsInfo.run({action:"theme",name:modelData.name})
                    background:Rectangle {
                        radius:10; color:Theme.surface; clip:true
                        border.width:tile.visualFocus ? Theme.focusWidth:tile.inUse ? 2:1
                        border.color:tile.visualFocus || tile.inUse ? Theme.green:tile.hovered ? Qt.alpha(Theme.teal,.45):Qt.alpha(Theme.teal,.14)
                    }
                    contentItem:ColumnLayout {
                        spacing:6
                        Rectangle {
                            Layout.fillWidth:true; Layout.fillHeight:true; radius:6; color:Theme.background; clip:true
                            Image { anchors.fill:parent; source:Config.imageSource(tile.modelData.preview); fillMode:Image.PreserveAspectCrop; sourceSize.width:480; asynchronous:true }
                            Text { anchors.centerIn:parent; visible:!tile.modelData.preview; text:"Aa"; font.family:Theme.labelFont; font.pixelSize:28; color:Theme.muted }
                        }
                        RowLayout {
                            Layout.fillWidth:true
                            Text { Layout.fillWidth:true; text:tile.modelData.label; textFormat:Text.PlainText; font.family:Theme.dataFont; font.pixelSize:Theme.small; color:tile.inUse ? Theme.green:Theme.text; elide:Text.ElideRight }
                            Text { visible:tile.inUse; text:"IN USE"; font.family:Theme.dataFont; font.pixelSize:9; font.letterSpacing:1.2; color:Theme.green }
                        }
                    }
                }
            }
        }
        GlowText { visible:!root.themes.length; text:"No installed themes were found."; color:Theme.muted; font.pixelSize:Theme.small }
    }

    SettingsSection {
        heading:"Typography"; caption:"Display type for headings, monospace for controls and readings."
        Rectangle {
            Layout.fillWidth:true; implicitHeight:specimen.implicitHeight+28; radius:8; color:Theme.background; border.color:Qt.alpha(Theme.teal,.12)
            ColumnLayout {
                id:specimen; anchors.left:parent.left; anchors.right:parent.right; anchors.top:parent.top; anchors.margins:14; spacing:6
                Text { Layout.fillWidth:true; text:"Field notes, clearly spoken."; font.family:Theme.labelFont; font.pixelSize:Math.round(28*Theme.fontScale); color:Theme.green; wrapMode:Text.WordWrap }
                Text { Layout.fillWidth:true; text:"THE WOODS ARE QUIET.  ·  Aa Bb Cc  ·  0123456789  ·  12:48"; font.family:Theme.dataFont; font.pixelSize:Theme.normal; color:Theme.text; wrapMode:Text.WordWrap }
                Text { Layout.fillWidth:true; text:Theme.labelFont+"  /  "+Theme.dataFont+"  ·  "+Math.round(Theme.fontScale*100)+"%"; font.family:Theme.dataFont; font.pixelSize:10; color:Theme.muted; elide:Text.ElideRight }
            }
        }
        SettingsFields { page:"appearance"; groups:["Typography"]; cards:false; highlightKey:root.highlightKey; Layout.fillWidth:true }
    }

    SettingsSection {
        heading:"Panels"; caption:"Shape and depth for Settings, Canopy and Field Station."
        GridLayout {
            Layout.fillWidth:true; columns:root.width<620 ? 1:2; columnSpacing:16; rowSpacing:8
            SettingsFields { page:"appearance"; groups:["Interface"]; cards:false; highlightKey:root.highlightKey; Layout.fillWidth:true }
            // Live miniature of a panel at the current radius and opacity.
            Item {
                Layout.preferredWidth:root.width<620 ? -1:220; Layout.fillWidth:root.width<620; implicitHeight:130
                Rectangle { anchors.fill:parent; radius:8; color:Theme.background; border.color:Qt.alpha(Theme.teal,.1)
                    Rectangle { anchors.fill:parent; anchors.margins:1; radius:8; gradient:Gradient { GradientStop { position:0; color:Qt.alpha(Theme.green,.10) } GradientStop { position:1; color:Qt.alpha(Theme.teal,.02) } } }
                }
                Rectangle {
                    anchors.centerIn:parent; width:parent.width-44; height:parent.height-36
                    radius:Math.min(height/2,Config.panelRadius*.6); color:Qt.alpha(Theme.background,Config.panelOpacity); border.color:Qt.alpha(Theme.teal,.3)
                    Column {
                        anchors.left:parent.left; anchors.top:parent.top; anchors.margins:12; spacing:6
                        Text { text:"CEDAR"; font.family:Theme.labelFont; font.pixelSize:16; color:Theme.green }
                        Rectangle { width:90; height:4; radius:2; color:Qt.alpha(Theme.teal,.4) }
                        Rectangle { width:60; height:4; radius:2; color:Qt.alpha(Theme.teal,.2) }
                    }
                }
            }
        }
    }

    SettingsSection {
        heading:"Motion & light"; caption:"Ambient light follows real activity. Reduced Motion stops every decorative cycle."
        SettingsFields { page:"appearance"; groups:["Motion & light"]; cards:false; highlightKey:root.highlightKey; Layout.fillWidth:true }
    }
    SettingsSection {
        objectName:"barEffects"
        heading:"Bar effects"
        caption:"The bar's animation identity: the Heartwood instrument, Rootlines, Kinetic Type, Whispers and Canopy Pulse. Every effect is state-driven and still while nothing changes; Reduced Motion and the Off preset keep the bar static."
        badge:Config.saved.motionPreset === "off" ? "Static" : Config.saved.motionPreset.charAt(0).toUpperCase() + Config.saved.motionPreset.slice(1)
        badgeColor:Config.saved.motionPreset === "off" ? Theme.muted : Theme.green
        SettingsFields { page:"appearance"; groups:["Bar effects"]; cards:false; highlightKey:root.highlightKey; Layout.fillWidth:true }
    }
}
