import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import ".."
import "../components"
import "../services"
ColumnLayout {
    id: root
    property var stateData: ({applications:[],presets:[],conflicts:{possibleOwners:[]}})
    property var options: ({})
    property var plan: null
    property string message: "Discovering application appearance support…"
    readonly property bool busy: service.busy
    property string action: "status"
    property string selected: ""
    property bool showAll: false
    readonly property bool dirty: stateData.settings !== undefined && JSON.stringify(options) !== JSON.stringify(stateData.settings)
    function discard() { options=JSON.parse(JSON.stringify(stateData.settings)); plan=null; }
    spacing: 14
    function setOption(key,value) { let next=Object.assign({},options); next[key]=value; options=next; plan=null; }
    function setOverride(key,value) {
        if (!selected) return;
        let overrides=JSON.parse(JSON.stringify(options.overrides || {}));
        let row=overrides[selected] || {};
        if (value === "") delete row[key]; else row[key]=value;
        overrides[selected]=row; setOption("overrides",overrides);
    }
    function request(which) {
        action=which; message="Working…";
        service.send({action:which,options:options,previewId:plan ? plan.id:""});
    }
    Component.onCompleted: request("status")
    ServiceRequest {
        id: service; script:"scripts/application_theming.py"; timeoutMs:90000
        onFailed: error => { root.message=error; root.plan=null; }
        onResult: result => {
            if (root.action==="refresh") { root.stateData=result; root.options=result.settings; }
            else if (root.action==="status") { root.stateData=result; root.options=result.settings; root.message=result.interrupted ? "An interrupted update needs recovery.":(result.last.paused ? "Synchronization paused after restore. Preview and Apply to resume.":"Select applications, preview the changes, then apply."); }
            else if (root.action==="preview") { root.plan=result; root.message=result.changes.length+" configuration changes ready for review."; }
            else { root.plan=null; root.message=(result.changed || 0)+" changes applied. Reopen applications marked for restart."; service.send({action:"status"}); root.action="refresh"; }
            if (root.action==="refresh" && result.applications) { root.stateData=result; root.options=result.settings; }
        }
    }
    GlowText { text:"Application Theming"; font.pixelSize:24; color:Theme.green }
    StationToggle { Layout.fillWidth:true; label:"Synchronize supported applications with CEDAR"; description:"Only selected integrations are managed. Existing settings are backed up before changes."; checked:root.options.enabled===true; onToggled:value=>root.setOption("enabled",value) }
    GlowText { Layout.fillWidth:true; visible:root.stateData.conflicts.possibleOwners.length>0; text:"Other appearance configurations detected: "+root.stateData.conflicts.possibleOwners.join(", ")+". Choose ownership before applying."; wrapMode:Text.WordWrap; color:Theme.amber; font.pixelSize:Theme.small }
    GridLayout {
        Layout.fillWidth:true; columns:root.width>800 ? 3:1; columnSpacing:18; rowSpacing:18
        ColumnLayout {
            Layout.fillWidth:true; Layout.alignment:Qt.AlignTop; Layout.preferredWidth:200; spacing:10
            GlowText { text:"Palette"; color:Theme.teal }
            Repeater {
                model:root.stateData.presets
                StationButton { required property var modelData; Layout.fillWidth:true; text:modelData.name; checked:root.options.preset===modelData.id; onClicked:{root.setOption("preset",modelData.id);root.setOption("variant",modelData.mode);root.setOption("inherit",false);} }
            }
            Rectangle {
                Layout.fillWidth:true; implicitHeight:150; radius:Theme.panelRadius
                color:root.plan ? root.plan.theme.tokens["background.primary"]:Theme.background
                border.color:root.plan ? root.plan.theme.tokens["border.default"]:Theme.border
                Behavior on color { ColorAnimation { duration:Theme.reducedMotion ? 0:180 } }
                Column {
                    anchors.fill:parent; anchors.margins:16; spacing:12
                    Text { text:root.plan ? root.plan.theme.name:"Preview palette"; color:root.plan ? root.plan.theme.tokens["text.primary"]:Theme.text; font.family:Theme.dataFont }
                    Repeater {
                        model:["accent.primary","accent.secondary","status.warning"]
                        Rectangle { required property string modelData; width:100; height:16; radius:8; color:root.plan ? root.plan.theme.tokens[modelData]:Theme.teal; Behavior on color { ColorAnimation { duration:Theme.reducedMotion ? 0:180 } } }
                    }
                }
            }
            StationToggle { Layout.fillWidth:true; label:"Inherit CEDAR theme"; checked:root.options.inherit===true; onToggled:value=>root.setOption("inherit",value) }
            StationToggle { Layout.fillWidth:true; label:"Wallpaper colors"; description:"Extracts one frame; cached and debounced."; checked:root.options.wallpaper===true; onToggled:value=>root.setOption("wallpaper",value) }
            StationToggle { Layout.fillWidth:true; label:"Lock accent"; checked:root.options.lockedAccent===true; onToggled:value=>root.setOption("lockedAccent",value) }
        }
        ScrollView {
            id: coverage; Layout.fillWidth:true; Layout.alignment:Qt.AlignTop; Layout.preferredWidth:380; Layout.preferredHeight:600
            contentWidth:availableWidth; clip:true; ScrollBar.horizontal.policy:ScrollBar.AlwaysOff
            ColumnLayout {
            width:coverage.availableWidth; spacing:8
            GlowText { text:"Application coverage"; color:Theme.teal }
            StationToggle { Layout.fillWidth:true; label:"Show missing applications"; checked:root.showAll; onToggled:value=>root.showAll=value }
            Repeater {
                model:root.stateData.applications.filter(a=>a.installed || root.showAll)
                Rectangle {
                    id: appCard
                    required property var modelData
                    Layout.fillWidth:true; implicitHeight:appContent.implicitHeight+20; radius:Theme.controlRadius
                    color:root.selected===modelData.id ? Theme.elevated:Theme.surface; border.color:Theme.border
                    ColumnLayout {
                        id:appContent; anchors.fill:parent; anchors.margins:10; spacing:5
                        RowLayout {
                            Layout.fillWidth:true
                            Image { source:Quickshell.iconPath(appCard.modelData.icon,true); sourceSize.width:22; sourceSize.height:22; Layout.preferredWidth:22; Layout.preferredHeight:22 }
                            StationButton { Layout.fillWidth:true; text:appCard.modelData.name; onClicked:root.selected=appCard.modelData.id }
                        }
                        StationToggle { Layout.fillWidth:true; label:appCard.modelData.category+" · "+appCard.modelData.capability; checked:(root.options.apps || []).includes(appCard.modelData.id); busy:!appCard.modelData.installed || appCard.modelData.capability==="unsupported"; onToggled:value=>{let ids=(root.options.apps || []).filter(id=>id!==appCard.modelData.id);if(value)ids.push(appCard.modelData.id);root.setOption("apps",ids);} }
                        GlowText { Layout.fillWidth:true; text:appCard.modelData.method; wrapMode:Text.WordWrap; font.pixelSize:Theme.small; color:Theme.muted }
                        GlowText { Layout.fillWidth:true; text:appCard.modelData.status+(appCard.modelData.restartRequired ? " · Restart required":"")+(appCard.modelData.shared ? " · Shared toolkit settings":""); wrapMode:Text.WordWrap; font.pixelSize:Theme.small; color:Theme.teal }
                    }
                }
            }
        }
        }
        ColumnLayout {
            Layout.fillWidth:true; Layout.alignment:Qt.AlignTop; Layout.preferredWidth:240; spacing:10
            GlowText { text:"Fine tuning"; color:Theme.teal }
            Repeater {
                model:[{id:"managed",label:"CEDAR Managed"},{id:"external",label:"External Managed"},{id:"independent",label:"Independent"}]
                StationButton { required property var modelData; Layout.fillWidth:true; text:modelData.label; checked:root.options.mode===modelData.id; onClicked:root.setOption("mode",modelData.id) }
            }
            StationField { Layout.fillWidth:true; visible:root.options.mode==="external"; placeholderText:"Absolute palette JSON path"; text:root.options.externalSource || ""; onTextEdited:root.setOption("externalSource",text) }
            RowLayout {
                StationButton { text:"Dark"; checked:root.options.variant==="dark"; onClicked:root.setOption("variant","dark") }
                StationButton { text:"Light"; checked:root.options.variant==="light"; onClicked:root.setOption("variant","light") }
            }
            GlowText { text:"Accent (#RRGGBB, optional)"; color:Theme.muted; font.pixelSize:Theme.small }
            StationField { Layout.fillWidth:true; text:root.options.accent || ""; onTextEdited:root.setOption("accent",text) }
            StationToggle { Layout.fillWidth:true; label:"Integrate fonts"; checked:root.options.fonts===true; onToggled:value=>root.setOption("fonts",value) }
            StationField { Layout.fillWidth:true; placeholderText:"Terminal font family"; text:root.options.fontFamily || ""; onTextEdited:root.setOption("fontFamily",text) }
            StationField { Layout.fillWidth:true; placeholderText:"Interface font family"; text:root.options.uiFont || ""; onTextEdited:root.setOption("uiFont",text) }
            StationField { Layout.fillWidth:true; placeholderText:"Font size"; text:String(root.options.fontSize || 11); onTextEdited:root.setOption("fontSize",Number(text)) }
            StationField { Layout.fillWidth:true; placeholderText:"Icon theme (optional)"; text:root.options.iconTheme || ""; onTextEdited:root.setOption("iconTheme",text) }
            GlowText { text:"Supported terminal opacity"; color:Theme.muted; font.pixelSize:Theme.small }
            Slider { Layout.fillWidth:true; from:.65; to:1; stepSize:.01; value:root.options.opacity===undefined ? 1:root.options.opacity; onMoved:root.setOption("opacity",value) }
            GlowText { Layout.fillWidth:true; text:root.selected ? "Override: "+root.selected:"Select an application to tune it"; wrapMode:Text.WordWrap; color:Theme.teal }
            StationField { Layout.fillWidth:true; enabled:root.selected!==""; placeholderText:"Application accent (empty inherits)"; text:((root.options.overrides || {})[root.selected] || {}).accent || ""; onTextEdited:root.setOverride("accent",text) }
            RowLayout {
                enabled:root.selected!==""
                StationButton { text:"Dark"; onClicked:root.setOverride("variant","dark") }
                StationButton { text:"Light"; onClicked:root.setOverride("variant","light") }
                StationButton { text:"Inherit"; onClicked:root.setOverride("variant","") }
            }
            StationField { Layout.fillWidth:true; enabled:root.selected!==""; placeholderText:"App opacity (empty inherits)"; text:((root.options.overrides || {})[root.selected] || {}).opacity===undefined ? "":String(root.options.overrides[root.selected].opacity); onTextEdited:root.setOverride("opacity",text==="" ? "":Number(text)) }
        }
    }
    GlowText { Layout.fillWidth:true; text:root.message; wrapMode:Text.WordWrap; color:Theme.text }
    GlowText { Layout.fillWidth:true; visible:ApplicationTheming.lastError!==""; text:ApplicationTheming.lastError; wrapMode:Text.WordWrap; color:Theme.amber }
    Repeater {
        model:root.plan ? root.plan.reports:[]
        GlowText { required property var modelData; Layout.fillWidth:true; text:modelData.id+": "+modelData.status+" — "+modelData.detail; wrapMode:Text.WordWrap; font.pixelSize:Theme.small; color:modelData.status==="Blocked" ? Theme.amber:Theme.muted }
    }
    Repeater {
        model:root.plan ? root.plan.changes:[]
        GlowText { required property var modelData; Layout.fillWidth:true; text:modelData.path; wrapMode:Text.WrapAnywhere; font.pixelSize:Theme.small; color:Theme.muted }
    }
    Flow {
        Layout.fillWidth:true; spacing:8
        StationButton { text:"Preview"; enabled:!service.busy; onClicked:root.request("preview") }
        StationButton { text:"Apply"; enabled:!service.busy && root.plan!==null && !root.plan.reports.some(r=>r.status==="Blocked"); onClicked:root.request("apply") }
        StationButton { text:"Restore Previous"; enabled:!service.busy && root.stateData.canRestore===true; onClicked:root.request("restore") }
        StationButton { text:"Reset CEDAR Overrides"; enabled:!service.busy && root.stateData.ownership>0; onClicked:root.request("reset") }
        StationButton { text:"Recover interrupted update"; visible:root.stateData.interrupted===true; enabled:!service.busy; onClicked:root.request("recover") }
    }
}
