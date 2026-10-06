import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../services"
ColumnLayout {
    id:root
    property string highlightKey:""
    readonly property var wallpapers: SettingsInfo.data.wallpapers || []
    readonly property string current: SettingsInfo.data.wallpaper || ""
    spacing:16

    SettingsSection {
        objectName:"wallpaper"
        heading:"Wallpaper"; caption:"Shown on every display. Choose an image from the current theme’s background library."
        Rectangle {
            Layout.fillWidth:true; implicitHeight:Math.min(280,width*.42); color:Theme.background; radius:10; clip:true; border.color:Qt.alpha(Theme.teal,.14)
            Image { id:hero; anchors.fill:parent; anchors.margins:1; source:root.current ? Config.imageSource("file://"+root.current) : ""; fillMode:Config.saved.wallpaperMode==="fit" ? Image.PreserveAspectFit : Config.saved.wallpaperMode==="stretch" ? Image.Stretch : Image.PreserveAspectCrop; sourceSize.width:1280; asynchronous:true }
            Rectangle {
                anchors.left:parent.left; anchors.right:parent.right; anchors.bottom:parent.bottom; height:44
                gradient:Gradient { GradientStop { position:0; color:Qt.alpha(Theme.background,0) } GradientStop { position:1; color:Qt.alpha(Theme.background,.85) } }
                Text { anchors.left:parent.left; anchors.bottom:parent.bottom; anchors.margins:12; text:root.current.split("/").pop() || "No wallpaper selected"; textFormat:Text.PlainText; font.family:Theme.dataFont; font.pixelSize:Theme.small; color:Theme.text; elide:Text.ElideMiddle; width:parent.width-24 }
            }
        }
        GridLayout {
            Layout.fillWidth:true; columns:root.width<560 ? 3:5; columnSpacing:8; rowSpacing:8
            Repeater {
                model:root.wallpapers
                StationButton {
                    id:thumb
                    required property var modelData
                    readonly property bool inUse:modelData.path===root.current
                    Layout.fillWidth:true; Layout.preferredWidth:120; implicitHeight:72
                    checked:inUse; enabled:!SettingsInfo.busy
                    hint:modelData.name || modelData.path.split("/").pop()
                    onClicked:if(!inUse)SettingsInfo.run({action:"wallpaper",path:modelData.path})
                    background:Rectangle { radius:8; color:Theme.background; border.width:thumb.inUse || thumb.visualFocus ? 2:1; border.color:thumb.inUse || thumb.visualFocus ? Theme.green : thumb.hovered ? Qt.alpha(Theme.teal,.5) : Qt.alpha(Theme.teal,.14) }
                    contentItem:Item {
                        Image { anchors.fill:parent; anchors.margins:-4; source:Config.imageSource(thumb.modelData.thumb || ("file://"+thumb.modelData.path)); fillMode:Image.PreserveAspectCrop; sourceSize.width:320; asynchronous:true; layer.enabled:false }
                    }
                }
            }
        }
        GlowText { visible:!root.wallpapers.length; text:"No images found in the current theme’s background library."; color:Theme.muted; Layout.fillWidth:true; wrapMode:Text.WordWrap; font.pixelSize:Theme.small }
        SettingsFields { page:"desktop"; groups:["Background"]; cards:false; highlightKey:root.highlightKey; Layout.fillWidth:true }
    }

    WeatherLocationSettings { highlightKey:root.highlightKey }

    SettingsSection {
        heading:"Privacy"; badge:Config.localOnly ? "Local only" : "External allowed"; badgeColor:Config.localOnly ? Theme.green : Theme.amber
        caption:"What CEDAR may contact on your behalf. Local desktop controls keep working either way."
        SettingsFields { page:"desktop"; groups:["Privacy"]; cards:false; highlightKey:root.highlightKey; Layout.fillWidth:true }
    }

    SettingsFields { page:"desktop"; groups:["Advanced"]; highlightKey:root.highlightKey; Layout.fillWidth:true }
}
