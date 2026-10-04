import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../services"
ColumnLayout {
    id:root
    spacing:8
    SettingsHeading { text:"Output"; objectName:"output" }
    SettingRow {
        Layout.fillWidth:true; title:"Output device"; description:"Choose where desktop sound plays."
        StationCombo { Layout.fillWidth:true; model:Audio.outputs; textRole:"description"; currentIndex:Audio.outputs.indexOf(Audio.sink); enabled:count>0; onActivated:Audio.selectOutput(Audio.outputs[currentIndex]) }
    }
    SettingRow {
        Layout.fillWidth:true; title:"Output volume"; description:Audio.audio ? Math.round(Audio.volume*100)+"%" : "No output device available"
        StationSlider { Layout.fillWidth:true; enabled:!!Audio.audio; value:Audio.volume; onMoved:Audio.setVolume(value); Accessible.name:"Output volume" }
        StationButton { text:Audio.muted ? "Unmute":"Mute"; checked:Audio.muted; enabled:!!Audio.audio; onClicked:Audio.toggleMute() }
    }
    SettingsHeading { text:"Input"; objectName:"microphone" }
    SettingRow {
        Layout.fillWidth:true; title:"Microphone"; description:"Choose the default recording device."
        StationCombo { Layout.fillWidth:true; model:Audio.inputs; textRole:"description"; currentIndex:Audio.inputs.indexOf(Audio.source); enabled:count>0; onActivated:Audio.selectInput(Audio.inputs[currentIndex]) }
    }
    SettingRow {
        Layout.fillWidth:true; title:"Input volume"; description:Audio.microphone ? Math.round(Audio.microphone.volume*100)+"%" : "No input device available"
        StationSlider { Layout.fillWidth:true; enabled:!!Audio.microphone; value:Audio.microphone?.volume ?? 0; onMoved:Audio.setMicrophone(value); Accessible.name:"Microphone volume" }
        StationButton { text:Audio.microphone?.muted ? "Unmute":"Mute"; checked:Audio.microphone?.muted ?? false; enabled:!!Audio.microphone; onClicked:Audio.toggleMicrophone() }
    }
    SettingsHeading { text:"Applications"; objectName:"streams" }
    GlowText { visible:!Audio.streams.length; text:"Active playback and recording streams appear here."; color:Theme.muted; Layout.fillWidth:true; wrapMode:Text.WordWrap; Layout.leftMargin:12 }
    Repeater {
        model:Audio.streams
        SettingRow {
            required property var modelData
            Layout.fillWidth:true; title:modelData.description || modelData.name
            description:Math.round(modelData.audio.volume*100)+"%"
            StationSlider { Layout.fillWidth:true; value:modelData.audio.volume; onMoved:modelData.audio.volume=value; Accessible.name:modelData.description+" volume" }
            StationButton { text:modelData.audio.muted ? "Unmute":"Mute"; checked:modelData.audio.muted; onClicked:modelData.audio.muted=!modelData.audio.muted }
        }
    }
}
