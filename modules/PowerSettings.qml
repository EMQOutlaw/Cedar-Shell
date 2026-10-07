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

    // Gaming Mode: a transaction over an explicit registry. The list is what
    // really happened the last time it was entered or left, step by step.
    SettingsSection {
        id:gamingSection
        objectName:"gamingMode"
        heading:"Gaming Mode"
        caption:"Super+G, or the Gaming tile in Quick Controls. The desktop quiets itself around the game and restores everything when you leave; a shell that stops mid-game restores it on its next start."
        badge:Gaming.busy ? "Working" : Gaming.active ? Gaming.summary : "Off"
        badgeColor:Gaming.busy ? Theme.amber : Gaming.active ? (Gaming.failures.length ? Theme.amber : Theme.green) : Theme.teal
        function tone(state) { return state==="active"||state==="restored" ? Theme.green : state==="failed" ? Theme.ember : state==="observing"||state==="applying" ? Theme.teal : Theme.muted; }
        function word(state) { return ({active:"Active",restored:"Restored",failed:"Failed",unavailable:"Unavailable",off:"Off",pending:"Waiting",applying:"Applying",observing:"Observing"})[state] || state; }
        RowLayout {
            Layout.fillWidth:true; spacing:8
            StationButton { text:Gaming.busy ? "Working…" : Gaming.active ? "Leave Gaming Mode" : "Enter Gaming Mode"; accent:Gaming.active ? Theme.amber : Theme.green; enabled:!Gaming.busy; onClicked:Gaming.toggle() }
            Item { Layout.fillWidth:true }
            StatusPill { visible:Capabilities.ready; text:Capabilities.gaming.gameModeAvailable ? (Gaming.gameModeActive ? "GameMode · "+Gaming.gameModeClients+" game" : "GameMode installed") : "GameMode not installed"; tone:Gaming.gameModeActive ? Theme.green : Theme.muted }
        }
        // One perimeter line completes once when the mode turns on, then everything is static.
        Rectangle {
            Layout.fillWidth:true; implicitHeight:2; color:Qt.alpha(Theme.teal,.12); radius:1
            Rectangle { id:perimeter; height:parent.height; radius:1; color:Theme.green; width:0; opacity:.9 }
            Connections { target:Gaming; function onActiveChanged() { if (Gaming.active) { perimeter.width=0; sweep.restart(); } else perimeter.width=0; } }
            NumberAnimation { id:sweep; target:perimeter; property:"width"; from:0; to:parent.width; duration:Config.saved.reducedMotion ? 0 : 420; easing.type:Easing.OutCubic }
        }
        Repeater {
            model:Gaming.steps
            SettingRow {
                required property var modelData
                Layout.fillWidth:true; title:modelData.label; description:modelData.detail
                StatusPill { text:gamingSection.word(modelData.state); tone:gamingSection.tone(modelData.state) }
            }
        }
        GlowText { visible:!Gaming.steps.length; text:"Nothing applied yet. The registry below decides what Gaming Mode changes."; color:Theme.muted; font.pixelSize:Theme.small; Layout.fillWidth:true; wrapMode:Text.WordWrap }
        GlowText { visible:Gaming.error!==""; text:Gaming.error; color:Theme.amber; Layout.fillWidth:true; wrapMode:Text.WordWrap; font.pixelSize:Theme.small }
        SettingsFields { page:"power"; groups:["Gaming Mode"]; cards:false; highlightKey:root.highlightKey; Layout.fillWidth:true }
    }

    // Performance mode: the basics only. The pill says whether it is on right
    // now and why, since Automatic follows the power profile and fullscreen focus.
    SettingsSection {
        objectName:"performanceMode"
        heading:"Performance mode"
        caption:"Stops the breathing light, spores, entrance sweeps, spectrum and ambient telemetry. Panels still open and close; nothing you need goes away."
        badge:Config.performanceActive ? "On · "+Config.performanceReason : "Off"
        badgeColor:Config.performanceActive ? Theme.amber : Theme.teal
        SettingsFields { page:"power"; groups:["Performance mode"]; cards:false; highlightKey:root.highlightKey; Layout.fillWidth:true }
    }

    SettingsFields {
        page:"power"; Layout.fillWidth:true; highlightKey:root.highlightKey
        exclude:["Session lock","Performance mode","Gaming Mode"]
        captions:({"Trailwatch privacy":"What the lock screen may reveal. Notification contents never appear there.","Trailwatch controls":"What may be done without unlocking."})
    }
    GlowText { visible:Controls.error!==""; text:Controls.error; color:Theme.amber; Layout.fillWidth:true; wrapMode:Text.WordWrap }
}
