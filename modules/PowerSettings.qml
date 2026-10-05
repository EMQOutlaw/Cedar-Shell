import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import ".."
import "../components"
import "../services"
ColumnLayout {
    id:root
    property string highlightKey:""
    readonly property var battery:UPower.displayDevice
    spacing:12
    SettingsHeading { text:"System power profile"; objectName:"powerProfile" }
    Flow {
        Layout.fillWidth:true; spacing:8
        Repeater { model:Controls.data.profiles
            StationButton { required property string modelData; text:modelData.replace("-"," "); checked:Controls.data.profile===modelData; enabled:!Controls.busy; onClicked:Controls.run({action:"profile",value:modelData}) }
        }
    }
    GlowText { visible:!Controls.data.profiles.length; text:Controls.data.errors?.power || "System power profiles are unavailable on this device."; color:Theme.muted; Layout.fillWidth:true; wrapMode:Text.WordWrap }
    SettingsCard {
        visible:root.battery?.isPresent ?? false; Layout.fillWidth:true
        GlowText { text:"Battery · "+Math.round((root.battery?.percentage ?? 0)*100)+"%"; font.family:Theme.labelFont; font.pixelSize:24 }
        GlowText { text:UPower.onBattery ? "Running on battery":"External power connected"; color:Theme.muted }
    }
    SettingRow {
        Layout.fillWidth:true; title:"Brightness"; objectName:"brightness"; description:Brightness.available ? Math.round(Brightness.value*100)+"%":"No supported backlight device detected"
        StationSlider { Layout.fillWidth:true; value:Brightness.value; enabled:Brightness.available; onCommitted: value=>Brightness.change(Math.round(value*100)-Math.round(Brightness.value*100)); Accessible.name:"Brightness" }
    }
    SettingRow {
        Layout.fillWidth:true; title:"Night Light"; description:Controls.data.nightlight===null ? "Night Light control is unavailable.":"Warmer display color after dark."
        StationToggle { Layout.fillWidth:true; accessibleLabel:"Night Light"; checked:Controls.data.nightlight===true; enabled:Controls.data.nightlight!==null && !Controls.busy; onToggled:Controls.run({action:"nightlight"}) }
    }
    SettingsFields { page:"power"; highlightKey:root.highlightKey; Layout.fillWidth:true }
    Flow {
        Layout.fillWidth:true; spacing:8; objectName:"authentication"
        StationButton { text:"Test authentication"; enabled:!Config.externalSession; onClicked:{ShellState.close();ShellState.authTest=true;} }
        StationButton { text:"Lock now"; onClicked:ShellState.lock(false) }
        StationButton { text:"Session actions"; onClicked:ShellState.toggle("power") }
    }
    GlowText { text:Config.externalSession ? "Your existing locker manages authentication during this desktop session. Select Trailwatch in the installer to test and change this integration." : Config.externalIdle ? "Trailwatch handles authentication. Your existing Noctalia idle timings are preserved; the CEDAR sleep bridge locks before suspend." : "Authentication testing opens a local password window without locking your session."; color:Theme.muted; Layout.fillWidth:true; wrapMode:Text.WordWrap; font.pixelSize:Theme.small }
    GlowText { visible:Controls.error!==""; text:Controls.error; color:Theme.amber; Layout.fillWidth:true; wrapMode:Text.WordWrap }
}
