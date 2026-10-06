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
    readonly property bool hasBattery:battery?.isPresent ?? false
    readonly property var profileInfo:({"power-saver":{title:"Power saver",detail:"Longer battery, quieter and cooler."},"balanced":{title:"Balanced",detail:"The everyday default."},"performance":{title:"Performance",detail:"Full speed while plugged in."}})
    spacing:16

    SettingsSection {
        objectName:"powerProfile"
        heading:"Power profile"; caption:"System profiles reported by this computer’s power service."
        badge:root.hasBattery ? Math.round(root.battery.percentage*100)+"% · "+(UPower.onBattery ? "on battery":"plugged in") : ""
        badgeColor:root.hasBattery && UPower.onBattery && root.battery.percentage<.2 ? Theme.amber : Theme.green
        GridLayout {
            Layout.fillWidth:true; columns:root.width<560 ? 1:Math.max(1,Controls.data.profiles.length); columnSpacing:10; rowSpacing:10
            Repeater {
                model:Controls.data.profiles
                StationButton {
                    id:profile
                    required property string modelData
                    readonly property bool inUse:Controls.data.profile===modelData
                    Layout.fillWidth:true; implicitHeight:76; checked:inUse; enabled:!Controls.busy
                    Accessible.name:(root.profileInfo[modelData]?.title || modelData)+(inUse ? ", in use":"")
                    onClicked:if(!inUse)Controls.run({action:"profile",value:modelData})
                    background:Rectangle { radius:10; color:profile.inUse ? Qt.alpha(Theme.green,.07):Theme.background; border.width:profile.inUse || profile.visualFocus ? 2:1; border.color:profile.inUse || profile.visualFocus ? Theme.green : profile.hovered ? Qt.alpha(Theme.teal,.45):Qt.alpha(Theme.teal,.14) }
                    contentItem:ColumnLayout {
                        spacing:3
                        Text { text:root.profileInfo[profile.modelData]?.title || profile.modelData.replace("-"," "); textFormat:Text.PlainText; font.family:Theme.labelFont; font.pixelSize:Math.round(20*Theme.fontScale); color:profile.inUse ? Theme.green:Theme.text }
                        Text { Layout.fillWidth:true; text:root.profileInfo[profile.modelData]?.detail || ""; textFormat:Text.PlainText; font.family:Theme.dataFont; font.pixelSize:10; color:Theme.muted; wrapMode:Text.WordWrap }
                    }
                }
            }
        }
        GlowText { visible:!Controls.data.profiles.length; text:Controls.data.errors?.power || "System power profiles are unavailable on this device."; color:Theme.muted; Layout.fillWidth:true; wrapMode:Text.WordWrap; font.pixelSize:Theme.small }
    }

    SettingsSection {
        heading:"Screen"; caption:"Brightness for a supported backlight, and warmer color after dark."
        SettingRow {
            Layout.fillWidth:true; title:"Brightness"; objectName:"brightness"; description:Brightness.available ? Math.round(Brightness.value*100)+"%":"No supported backlight device detected"
            StationSlider { Layout.fillWidth:true; value:Brightness.value; enabled:Brightness.available; onCommitted: value=>Brightness.change(Math.round(value*100)-Math.round(Brightness.value*100)); Accessible.name:"Brightness" }
        }
        SettingRow {
            Layout.fillWidth:true; title:"Night Light"; description:Controls.data.nightlight===null ? "Night Light control is unavailable.":"Warmer display color after dark."
            StationToggle { Layout.fillWidth:true; accessibleLabel:"Night Light"; checked:Controls.data.nightlight===true; enabled:Controls.data.nightlight!==null && !Controls.busy; onToggled:Controls.run({action:"nightlight"}) }
        }
    }

    SettingsSection {
        objectName:"authentication"
        heading:"Session lock"
        badge:Config.externalSession ? "Existing locker" : "Trailwatch"; badgeColor:Config.externalSession ? Theme.teal : Theme.green
        caption:Config.externalSession ? "Your existing locker manages authentication during this session. Select Trailwatch in the installer to test and change this." : Config.externalIdle ? "Trailwatch handles authentication. Your existing idle timings are preserved; the CEDAR sleep bridge locks before suspend." : "Trailwatch locks the session with your system password."
        SettingsFields { page:"power"; groups:["Session lock"]; cards:false; highlightKey:root.highlightKey; Layout.fillWidth:true }
        SettingRow {
            Layout.fillWidth:true; title:"Test authentication"; enabled:!Config.externalSession
            description:"Opens a local password window without locking, so you can confirm your password works before you rely on the lock."
            StationButton { text:"Test password"; enabled:!Config.externalSession; onClicked:{ShellState.close();ShellState.authTest=true;} }
        }
    }

    SettingsFields {
        page:"power"; Layout.fillWidth:true; highlightKey:root.highlightKey
        exclude:["Session lock"]
        captions:({"Trailwatch privacy":"What the lock screen may reveal. Notification contents never appear there.","Trailwatch controls":"What may be done without unlocking."})
    }
    GlowText { visible:Controls.error!==""; text:Controls.error; color:Theme.amber; Layout.fillWidth:true; wrapMode:Text.WordWrap }
}
