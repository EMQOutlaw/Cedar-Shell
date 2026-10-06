import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../services"
ColumnLayout {
    id:root
    spacing:16
    // A large live level with its own mute; used for output and microphone.
    component Level: RowLayout {
        id:level
        property real value:0
        property bool muted:false
        property bool available:false
        property string name:""
        signal moved(real value)
        signal toggled()
        Layout.fillWidth:true; spacing:14
        Text { Layout.preferredWidth:84; text:!level.available ? "—" : level.muted ? "MUTED" : Math.round(level.value*100)+"%"; font.family:Theme.labelFont; font.pixelSize:Math.round(30*Theme.fontScale); color:level.muted || !level.available ? Theme.muted : Theme.green }
        StationSlider { Layout.fillWidth:true; enabled:level.available; value:level.value; onMoved:level.moved(value); Accessible.name:level.name }
        StationButton { text:level.muted ? "Unmute":"Mute"; checked:level.muted; accent:level.muted ? Theme.amber : Theme.teal; enabled:level.available; onClicked:level.toggled() }
    }

    SettingsSection {
        objectName:"output"
        heading:"Output"; caption:"Where desktop sound plays."
        badge:Audio.outputs.length+(Audio.outputs.length===1 ? " device":" devices")
        StationCombo { Layout.fillWidth:true; model:Audio.outputs; textRole:"description"; currentIndex:Audio.outputs.indexOf(Audio.sink); enabled:count>0; Accessible.name:"Output device"; onActivated:Audio.selectOutput(Audio.outputs[currentIndex]) }
        Level { name:"Output volume"; available:!!Audio.audio; value:Audio.volume; muted:Audio.muted; onMoved:value=>Audio.setVolume(value); onToggled:Audio.toggleMute() }
        GlowText { visible:!Audio.audio; text:"No output device is available."; color:Theme.muted; font.pixelSize:Theme.small }
    }

    SettingsSection {
        objectName:"microphone"
        heading:"Microphone"; caption:"The default recording device."
        badge:Audio.inputs.length+(Audio.inputs.length===1 ? " device":" devices")
        StationCombo { Layout.fillWidth:true; model:Audio.inputs; textRole:"description"; currentIndex:Audio.inputs.indexOf(Audio.source); enabled:count>0; Accessible.name:"Microphone"; onActivated:Audio.selectInput(Audio.inputs[currentIndex]) }
        Level { name:"Microphone volume"; available:!!Audio.microphone; value:Audio.microphone?.volume ?? 0; muted:Audio.microphone?.muted ?? false; onMoved:value=>Audio.setMicrophone(value); onToggled:Audio.toggleMicrophone() }
        GlowText { visible:!Audio.microphone; text:"No input device is available."; color:Theme.muted; font.pixelSize:Theme.small }
    }

    SettingsSection {
        objectName:"streams"
        heading:"Applications"; caption:"Apps playing or recording right now. Their volume is separate from the device level."
        badge:Audio.streams.length ? Audio.streams.length+" active" : ""
        Repeater {
            model:Audio.streams
            SettingRow {
                required property var modelData
                Layout.fillWidth:true; title:modelData.description || modelData.name
                description:modelData.audio.muted ? "Muted" : Math.round(modelData.audio.volume*100)+"%"
                StationSlider { Layout.fillWidth:true; value:modelData.audio.volume; onMoved:modelData.audio.volume=value; Accessible.name:(modelData.description || modelData.name)+" volume" }
                StationButton { text:modelData.audio.muted ? "Unmute":"Mute"; checked:modelData.audio.muted; onClicked:modelData.audio.muted=!modelData.audio.muted }
            }
        }
        GlowText { visible:!Audio.streams.length; text:"Nothing is playing or recording."; color:Theme.muted; font.pixelSize:Theme.small }
    }
}
