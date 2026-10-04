import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../services"
ColumnLayout {
    id:root
    property string highlightKey:""
    property bool browse:false
    spacing:12
    SettingsHeading { text:"Wallpaper · all displays"; objectName:"wallpaper" }
    Rectangle {
        Layout.fillWidth:true; implicitHeight:Math.min(260,width*.45); color:Theme.surface; radius:12; clip:true
        Image { anchors.fill:parent; source:SettingsInfo.data.wallpaper ? "file://"+SettingsInfo.data.wallpaper : ""; fillMode:Image.PreserveAspectCrop; sourceSize.width:640; asynchronous:true }
        GlowText { anchors.centerIn:parent; text:"No wallpaper selected"; visible:!SettingsInfo.data.wallpaper; color:Theme.muted }
    }
    GlowText { text:SettingsInfo.data.wallpaper.split("/").pop() || "Desktop background"; color:Theme.muted; elide:Text.ElideMiddle; Layout.fillWidth:true }
    StationButton { text:root.browse ? "Close wallpaper library":"Change wallpaper"; checked:root.browse; onClicked:root.browse=!root.browse }
    GridLayout {
        visible:root.browse; Layout.fillWidth:true; columns:root.width<540 ? 2:3; columnSpacing:8; rowSpacing:8
        Repeater {
            model:root.browse ? SettingsInfo.data.wallpapers:[]
            ColumnLayout {
                required property var modelData
                Layout.fillWidth:true; Layout.preferredWidth:180
                Rectangle { Layout.fillWidth:true; implicitHeight:90; color:Theme.surface; radius:8; clip:true
                    Image { anchors.fill:parent; source:Config.imageSource(modelData.thumb || ("file://"+modelData.path)); fillMode:Image.PreserveAspectCrop; sourceSize.width:640; asynchronous:true }
                }
                StationButton { Layout.fillWidth:true; text:modelData.name || modelData.path.split("/").pop(); enabled:!SettingsInfo.busy; checked:modelData.path===SettingsInfo.data.wallpaper; onClicked:SettingsInfo.run({action:"wallpaper",path:modelData.path}) }
            }
        }
    }
    GlowText { visible:root.browse && !SettingsInfo.data.wallpapers.length; text:"No images found in the current theme’s background library."; color:Theme.muted; Layout.fillWidth:true; wrapMode:Text.WordWrap }
    WeatherLocationSettings { Layout.fillWidth:true }
    SettingsFields { page:"desktop"; highlightKey:root.highlightKey; Layout.fillWidth:true }
}
