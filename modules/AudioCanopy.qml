import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Pipewire
import ".."
import "../components"
import "../components/core"
import "../services"

ColumnLayout {
    id:root
    property bool active:false
    property bool meterEnabled:false
    spacing:14
    SettingsHeading {text:"On the air"}
    CoreMedia { Layout.fillWidth:true; detailed:root.active }
    StationToggle {Layout.fillWidth:true;label:"Spectrum";description:"Real playback spectrum; active only while this instrument is visible.";checked:Config.saved.audioSpectrum;enabled:AudioInstruments.data.spectrumAvailable;onToggled:value=>Config.set("audioSpectrum",value)}
    AudioSpectrum {Layout.fillWidth:true;visible:Config.saved.audioSpectrum && !Theme.reducedMotion;active:root.active && visible && AudioInstruments.data.spectrumAvailable}
    AudioSettings {Layout.fillWidth:true}
    SettingsHeading {text:"Microphone instrument"}
    StationToggle {Layout.fillWidth:true;label:"Monitor input level";description:"Opens a live meter for the selected microphone while this panel is visible.";checked:root.meterEnabled;enabled:!!Audio.source;onToggled:value=>root.meterEnabled=value}
    PwNodePeakMonitor {id:peak;node:Audio.source;enabled:root.active && root.meterEnabled && !Config.testMode}
    Rectangle {Layout.fillWidth:true;implicitHeight:5;radius:2;color:Theme.border;Rectangle {height:parent.height;width:Math.max(0,Math.min(1,peak.peak))*parent.width;radius:2;color:Theme.green}}
    SettingsHeading {text:"Routing instrument"}
    GlowText {Layout.fillWidth:true;wrapMode:Text.WordWrap;color:Theme.muted;text:"Move a playing application to an output. Stream volume remains above."}
    StationButton {text:"Refresh devices and routes";enabled:!AudioInstruments.busy;onClicked:AudioInstruments.refresh()}
    Repeater {
        model:AudioInstruments.data.streams
        SettingRow {
            required property var modelData
            Layout.fillWidth:true;title:modelData.label;description:"Playback output"
            StationCombo {Layout.fillWidth:true;model:AudioInstruments.data.outputs;textRole:"label";currentIndex:AudioInstruments.data.outputs.findIndex(o=>o.id===modelData.output);enabled:!AudioInstruments.busy;onActivated:AudioInstruments.run({action:"route",stream:modelData.id,serial:modelData.serial,output:AudioInstruments.data.outputs[currentIndex].name})}
        }
    }
    GlowText {visible:!AudioInstruments.data.streams.length;Layout.fillWidth:true;wrapMode:Text.WordWrap;text:"No routable playback streams are available.";color:Theme.muted}
    SettingsHeading {text:"Equalizer / DSP"}
    GlowText {Layout.fillWidth:true;wrapMode:Text.WordWrap;color:Theme.muted;text:AudioInstruments.data.eq.reason}
    GlowText {Layout.fillWidth:true;wrapMode:Text.WordWrap;font.pixelSize:Theme.small;color:Theme.muted;text:"Graphical and parametric EQ, device EQ presets, noise suppression and other filters require an integrated DSP backend. CEDAR is not processing your audio."}
    SettingsHeading {text:"Audio scenes"}
    GlowText {Layout.fillWidth:true;wrapMode:Text.WordWrap;color:Theme.muted;text:"Save the current devices, master and microphone levels, mute states, and application routes/levels (one saved route per app). Up to eight scenes. Disconnected devices prevent application of a scene."}
    RowLayout {
        Layout.fillWidth:true
        StationField {id:sceneName;Layout.fillWidth:true;placeholderText:"Scene name";maximumLength:48}
        StationButton {text:"Save current";enabled:sceneName.text.trim()!=="" && !AudioInstruments.busy;onClicked:AudioInstruments.run({action:"save-scene",name:sceneName.text})}
    }
    Repeater {
        model:AudioInstruments.data.scenes
        SettingRow {
            required property var modelData
            Layout.fillWidth:true;title:modelData.name
            description:modelData.output.label+" · "+Math.round(modelData.output.volume*100)+"%"+(modelData.output.muted?" · muted":"")+"\nMic: "+(modelData.microphone ? modelData.microphone.label+(modelData.microphone.muted?" · muted":" · "+Math.round(modelData.microphone.volume*100)+"%") : "not saved")+"\nApplication routes: "+modelData.streams.map(s=>s.label+" → "+s.output+" ("+Math.round(s.volume*100)+"%)").join(", ")
            StationButton {text:"Apply";enabled:!AudioInstruments.busy;onClicked:AudioInstruments.run({action:"apply-scene",name:modelData.name})}
            StationButton {text:"Delete";enabled:!AudioInstruments.busy;onClicked:AudioInstruments.run({action:"delete-scene",name:modelData.name})}
        }
    }
    GlowText {Layout.fillWidth:true;wrapMode:Text.WordWrap;visible:AudioInstruments.error!=="";text:AudioInstruments.error;color:Theme.amber}
}
