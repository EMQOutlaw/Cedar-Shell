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
    readonly property var services:SettingsInfo.data.services || []
    function tone(status) { return status==="Healthy" ? Theme.green : status==="Failed" ? Theme.ember : status==="Unavailable" ? Theme.muted : Theme.amber; }
    spacing:16

    GridLayout {
        Layout.fillWidth:true; columns:root.width<560 ? 1:3; columnSpacing:12; rowSpacing:12
        Readout { label:"Healthy"; lit:true; value:String(root.services.filter(s=>s.status==="Healthy").length); detail:"Running as expected" }
        Readout { label:"Failed"; lit:root.services.some(s=>s.status==="Failed"); tone:Theme.ember; value:String(root.services.filter(s=>s.status==="Failed").length); detail:"Reported failed by systemd" }
        Readout { label:"Not here"; lit:false; value:String(root.services.filter(s=>s.status==="Unavailable").length); detail:"Not installed or not used on this computer" }
    }

    SettingsSection {
        heading:"Services"; caption:"The system services CEDAR depends on. Restarting briefly interrupts what a service does."
        badge:SettingsInfo.busy ? "Checking" : ""
        StationButton { text:SettingsInfo.busy ? "Checking…":"Check again"; enabled:!SettingsInfo.busy; onClicked:SettingsInfo.refresh(true) }
        Repeater {
            model:root.services
            ColumnLayout {
                required property var modelData
                Layout.fillWidth:true; spacing:0
                SettingRow {
                    Layout.fillWidth:true; title:modelData.name; description:modelData.detail
                    StatusPill { text:modelData.status; tone:root.tone(modelData.status) }
                    StationButton { text:"Logs"; enabled:!SettingsInfo.busy && modelData.status!=="Unavailable"; onClicked:SettingsInfo.run({action:"logs",unit:modelData.unit}) }
                    StationButton { text:root.confirmRestart===modelData.unit ? "Confirm":"Restart"; accent:root.confirmRestart===modelData.unit ? Theme.amber:Theme.teal; enabled:!SettingsInfo.busy && modelData.status!=="Unavailable"; onClicked:{if(root.confirmRestart===modelData.unit){root.confirmRestart="";SettingsInfo.run({action:"restart",unit:modelData.unit});}else root.confirmRestart=modelData.unit;} }
                }
                RowLayout {
                    visible:root.confirmRestart===modelData.unit; Layout.fillWidth:true; Layout.leftMargin:12; spacing:8
                    GlowText { text:"Restart "+modelData.name+"? It is briefly interrupted."; color:Theme.amber; Layout.fillWidth:true; wrapMode:Text.WordWrap; font.pixelSize:Theme.small }
                    StationButton { text:"Cancel"; onClicked:root.confirmRestart="" }
                }
            }
        }
        GlowText { visible:!root.services.length; text:"Service health is unavailable."; color:Theme.muted; font.pixelSize:Theme.small }
    }

    SettingsSection {
        visible:SettingsInfo.logs!==""
        heading:"Service logs"; caption:"Recent entries, with common secrets and identifiers redacted. Review before sharing."
        TextArea {
            Layout.fillWidth:true; text:SettingsInfo.logs; textFormat:TextEdit.PlainText; readOnly:true; selectByMouse:true; wrapMode:TextEdit.Wrap; color:Theme.text; font.family:Theme.dataFont; font.pixelSize:Theme.small
            background:Rectangle { color:Theme.background; radius:8; border.color:Qt.alpha(Theme.teal,.12) }
        }
        StationButton { text:"Copy logs"; onClicked:Quickshell.clipboardText=SettingsInfo.logs }
    }

    SettingsSection {
        heading:"Diagnostics"; caption:"A report about this desktop for troubleshooting. Nothing is uploaded; you review it before copying."
        StationButton { text:root.diagnosticPreview ? "Rebuild report":"Build report"; onClicked:root.diagnosticPreview=SettingsInfo.report() }
        TextArea { visible:root.diagnosticPreview!==""; Layout.fillWidth:true; text:root.diagnosticPreview; textFormat:TextEdit.PlainText; readOnly:true; selectByMouse:true; wrapMode:TextEdit.Wrap; color:Theme.text; font.family:Theme.dataFont; font.pixelSize:Theme.small; background:Rectangle { color:Theme.background; radius:8; border.color:Qt.alpha(Theme.teal,.12) } }
        StationButton { visible:root.diagnosticPreview!==""; text:"Copy reviewed report"; onClicked:{Quickshell.clipboardText=root.diagnosticPreview;SettingsInfo.message="Diagnostics copied.";} }
    }

    SettingsSection {
        heading:"CEDAR updates"; badge:"Manual only"
        caption:"Signature-verified update candidates only. This private development build has no trusted publisher identity yet, so choose a separately verified key. Nothing installs automatically."
        StationField { id:updateArchive; Layout.fillWidth:true; placeholderText:"Local release archive path"; Accessible.name:"Release archive" }
        StationField { id:updateSignature; Layout.fillWidth:true; placeholderText:"Detached signature path"; Accessible.name:"Release signature" }
        StationField { id:updateKey; Layout.fillWidth:true; placeholderText:"Trusted publisher public key path"; Accessible.name:"Trusted public key" }
        StationButton { text:"Review update in terminal"; enabled:updateArchive.text!=="" && updateSignature.text!=="" && updateKey.text!==""; onClicked:Quickshell.execDetached(Config.terminal.concat(["-e","python3",Quickshell.shellPath("scripts/distribution.py"),"update",updateArchive.text,"--signature",updateSignature.text,"--trusted-key",updateKey.text])) }
    }
}
