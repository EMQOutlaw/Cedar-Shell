import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
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

    // What the shell itself costs right now, read from /proc while this page is
    // open. Cheap enough to leave on: one small file every two seconds, and
    // nothing at all once the page closes.
    SettingsSection {
        id:shellCost
        heading:"Shell cost"; caption:"CEDAR's own footprint and sampling cadence, read from /proc while this page is open."
        property string memory:"…"
        property string threads:"…"
        property string switches:"…"
        function label(ms) { return ms ? (ms>=60000 ? Math.round(ms/60000)+" min" : Math.round(ms/1000)+" s") : "off"; }
        FileView { id:shellStatus; path:"/proc/"+Quickshell.processId+"/status"; preload:true; blockLoading:true; printErrors:false }
        Timer {
            interval:2000; running:shellCost.visible && root.visible; repeat:true; triggeredOnStart:true
            onTriggered: {
                shellStatus.reload(); shellStatus.waitForJob();
                const text=String(shellStatus.text() || ""), field=name => (text.match(new RegExp("^"+name+":\\s+(\\d+)","m")) || [])[1];
                const rss=Number(field("VmRSS"));
                shellCost.memory=rss>0 ? (rss/1024).toFixed(0)+" MB" : "Unavailable";
                shellCost.threads=field("Threads") || "Unavailable";
                shellCost.switches=field("voluntary_ctxt_switches") || "Unavailable";
            }
        }
        GridLayout {
            Layout.fillWidth:true; columns:root.width<560 ? 1:3; columnSpacing:12; rowSpacing:12
            Readout { label:"Resident memory"; lit:true; value:shellCost.memory; detail:"This process; helpers and the GPU driver's share are not included" }
            Readout { label:"Threads"; lit:false; value:shellCost.threads; detail:"Render threads, one per window, plus Qt's own" }
            Readout { label:"Ambience"; lit:Motion.active; tone:Motion.active ? Theme.green : !VisualQuality.normal ? Theme.amber : Theme.muted; value:VisualQuality.gaming ? "Gaming Mode" : VisualQuality.efficient ? "Performance mode" : Motion.active ? "Breathing" : "Resting"; detail:!VisualQuality.normal ? VisualQuality.reason : Theme.reducedMotion ? "Reduced Motion is on" : "Pauses after "+Motion.restAfter+" s without input" }
        }
        SettingRow { Layout.fillWidth:true; title:"Telemetry cadence"; description:"CPU, memory and network every "+shellCost.label(SystemStats.fastCadence)+" · temperature every "+shellCost.label(SystemStats.temperatureCadence)+" · disk and uptime every "+shellCost.label(SystemStats.slowCadence)+". Read in-process from /proc and hwmon; only disk usage asks a process."
            StatusPill { text:SystemStats.instrument ? "Instrument" : SystemStats.demanded ? "Ambient" : "Idle"; tone:SystemStats.instrument ? Theme.green : Theme.teal } }
        SettingRow { Layout.fillWidth:true; title:"Wakeups"; description:"Voluntary context switches since the shell started. A quiet desktop should add only a few per second."
            StatusPill { text:shellCost.switches; tone:Theme.teal } }
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
