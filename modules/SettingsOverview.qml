import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../services"
ColumnLayout {
    id: root
    signal navigate(string page, string anchor)
    spacing: 16
    SettingsCard {
        Layout.fillWidth:true
        GlowText { text:SettingsInfo.data.hostname; font.family:Theme.labelFont; font.pixelSize:32; Layout.fillWidth:true; elide:Text.ElideRight }
        GlowText { text:SettingsInfo.data.os + " · " + SettingsInfo.data.kernel; color:Theme.muted; Layout.fillWidth:true; wrapMode:Text.WordWrap }
        GlowText { text:"UPTIME  " + SystemStats.uptime; color:Theme.teal; font.pixelSize:Theme.small }
    }
    GridLayout {
        Layout.fillWidth:true; columns:root.width<600 ? 1:2; columnSpacing:16; rowSpacing:16
        Repeater {
            model:[
                {title:"Display",detail:DesktopSettings.data.monitors.map(m=>m.name+" · "+m.width+" × "+m.height+" · "+Math.round(m.refreshRate)+" Hz").join("\n") || "Display information unavailable",page:"displays",action:"Arrange displays"},
                {title:"Appearance",detail:SettingsInfo.data.theme+"\n"+Config.barStyle+" bar",page:"appearance",action:"Personalize CEDAR"},
                {title:"Connections",detail:Network.label+"\nBluetooth "+(BluetoothService.adapter?.enabled ? "on":"off"),page:"connections",action:"Manage connections"},
                {title:"Power",detail:Controls.data.profile || "System power profiles unavailable",page:"power",action:"Power & session"}
            ]
            SettingsCard {
                required property var modelData
                Layout.fillWidth:true; Layout.preferredWidth:280; Layout.fillHeight:true
                GlowText { text:modelData.title; font.family:Theme.labelFont; font.pixelSize:23 }
                GlowText { text:modelData.detail; color:Theme.muted; Layout.fillWidth:true; wrapMode:Text.WordWrap; font.pixelSize:Theme.small }
                StationButton { text:modelData.action+"  →"; onClicked:root.navigate(modelData.page,"") }
            }
        }
    }
    SettingsHeading { text:"Quick paths" }
    Flow {
        Layout.fillWidth:true; spacing:8
        StationButton { text:"Wallpaper"; onClicked:root.navigate("desktop","wallpaper") }
        StationButton { text:"Keybinds"; onClicked:root.navigate("keybinds","") }
        StationButton { text:"System health"; onClicked:root.navigate("system","") }
        StationButton { text:"Time & date"; onClicked:root.navigate("time","") }
    }
}
