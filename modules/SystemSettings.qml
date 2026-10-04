import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import ".."
import "../components"
import "../services"
ColumnLayout {
    id:root
    property string confirmRestart:""
    property string diagnosticPreview:""
    spacing:12
    Flow {
        Layout.fillWidth:true; spacing:8
        StationButton { text:SettingsInfo.busy ? "Checking…":"Refresh health"; enabled:!SettingsInfo.busy; onClicked:SettingsInfo.refresh(true) }
        StationButton { text:"Preview diagnostics"; onClicked:root.diagnosticPreview=SettingsInfo.report() }
    }
    GlowText { visible:root.diagnosticPreview!==""; text:"Review before sharing. No diagnostics are uploaded automatically."; Layout.fillWidth:true; wrapMode:Text.WordWrap; color:Theme.muted }
    TextArea { visible:root.diagnosticPreview!==""; Layout.fillWidth:true; text:root.diagnosticPreview; textFormat:TextEdit.PlainText; readOnly:true; selectByMouse:true; wrapMode:TextEdit.Wrap; color:Theme.text; background:Rectangle {color:Theme.surface} }
    StationButton { visible:root.diagnosticPreview!==""; text:"Copy reviewed diagnostics"; onClicked:Quickshell.clipboardText=root.diagnosticPreview }
    SettingsHeading { text:"CEDAR updates" }
    GlowText { text:"Manual, signature-verified update candidates only. This private development build has no trusted publisher identity yet. Choose a separately verified key; checks never install automatically."; Layout.fillWidth:true; wrapMode:Text.WordWrap; color:Theme.muted }
    StationField { id:updateArchive; Layout.fillWidth:true; placeholderText:"Local release archive path"; Accessible.name:"Release archive" }
    StationField { id:updateSignature; Layout.fillWidth:true; placeholderText:"Detached signature path"; Accessible.name:"Release signature" }
    StationField { id:updateKey; Layout.fillWidth:true; placeholderText:"Trusted publisher public key path"; Accessible.name:"Trusted public key" }
    StationButton { text:"Review update in terminal"; enabled:updateArchive.text!=="" && updateSignature.text!=="" && updateKey.text!==""; onClicked:Quickshell.execDetached(Config.terminal.concat(["-e","python3",Quickshell.shellPath("scripts/distribution.py"),"update",updateArchive.text,"--signature",updateSignature.text,"--trusted-key",updateKey.text])) }
    Repeater {
        model:SettingsInfo.data.services
        ColumnLayout {
            required property var modelData
            Layout.fillWidth:true; spacing:0
            SettingRow {
                Layout.fillWidth:true; title:modelData.name; description:modelData.status+" · "+modelData.detail
                StationButton { text:"Logs"; enabled:!SettingsInfo.busy; onClicked:SettingsInfo.run({action:"logs",unit:modelData.unit}) }
                StationButton { text:root.confirmRestart===modelData.unit ? "Confirm restart":"Restart"; enabled:!SettingsInfo.busy && modelData.status!=="Unavailable"; onClicked:{if(root.confirmRestart===modelData.unit){root.confirmRestart="";SettingsInfo.run({action:"restart",unit:modelData.unit});}else root.confirmRestart=modelData.unit;} }
            }
            GlowText { visible:root.confirmRestart===modelData.unit; text:"Restarting this service briefly interrupts its function."; color:Theme.amber; Layout.fillWidth:true; wrapMode:Text.WordWrap; font.pixelSize:Theme.small }
            StationButton { visible:root.confirmRestart===modelData.unit; text:"Cancel"; onClicked:root.confirmRestart="" }
        }
    }
    SettingsHeading { visible:SettingsInfo.logs!==""; text:"Service logs" }
    TextArea {
        visible:SettingsInfo.logs!==""; Layout.fillWidth:true; text:SettingsInfo.logs; textFormat:TextEdit.PlainText; readOnly:true; selectByMouse:true; wrapMode:TextEdit.Wrap; color:Theme.text; font.family:Theme.dataFont; font.pixelSize:Theme.small
        background:Rectangle { color:Theme.surface; radius:8 }
    }
    StationButton { visible:SettingsInfo.logs!==""; text:"Copy logs"; onClicked:Quickshell.clipboardText=SettingsInfo.logs }
}
