import QtQuick
import QtQuick.Layouts
import ".."
import "../services"
import "../components"
import "../components/SettingsSchema.js" as Schema
ColumnLayout {
    id: root
    objectName:"inputPage"
    property bool active:false
    property string highlightKey:""
    readonly property var draft: DesktopSettings.inputDraft
    readonly property var base: DesktopSettings.inputBase
    readonly property var edits: DesktopSettings.inputEdits
    readonly property bool dirty: DesktopSettings.inputDirty
    readonly property bool externalChange: DesktopSettings.inputExternalChange
    property bool resetConfirm:false
    readonly property var fields:Schema.inputFields.filter(f=>f.key in draft && (!f.key.startsWith("touchpad:") || DesktopSettings.data.hasTouchpad===true))
    function load(){DesktopSettings.loadInput();}
    function change(key,value){DesktopSettings.editInput(key,value);}
    onActiveChanged:if(active)DesktopSettings.refresh()
    Component.onCompleted:if(!DesktopSettings.inputDirty)load()
    spacing:8
    GlowText { text:"Edit the active values, then Apply. Only changed options are added to CEDAR’s generated configuration."; color:Theme.muted; Layout.fillWidth:true; wrapMode:Text.WordWrap; font.pixelSize:Theme.small }
    SettingsCard {
        visible:root.externalChange; Layout.fillWidth:true
        GlowText { text:"Input configuration changed outside this page. Reload before applying changes to the same options."; color:Theme.amber; Layout.fillWidth:true; wrapMode:Text.WordWrap }
        StationButton { text:"Reload active values"; onClicked:root.load() }
    }
    Repeater {
        model:root.fields
        ColumnLayout {
            required property var modelData
            required property int index
            Layout.fillWidth:true; spacing:2
            SettingsHeading { visible:index===0 || modelData.group!==root.fields[index-1].group; text:modelData.group }
            SettingRow {
                objectName:modelData.key; Layout.fillWidth:true; title:modelData.label; description:modelData.description; highlighted:root.highlightKey===modelData.key; enabled:!DesktopSettings.busy
                StationField { visible:["text","number"].includes(modelData.type); Layout.fillWidth:true; text:String(root.draft[modelData.key] ?? ""); placeholderText:modelData.placeholder || ""; Accessible.name:modelData.label; onCommit:value=>root.change(modelData.key,modelData.type==="number" ? Number(value):value) }
                StationToggle { visible:modelData.type==="toggle"; Layout.fillWidth:true; accessibleLabel:modelData.label; checked:root.draft[modelData.key]===true; onToggled:value=>root.change(modelData.key,value) }
                StationCombo { visible:modelData.type==="choice"; Layout.fillWidth:true; model:modelData.options || []; currentIndex:model.indexOf(root.draft[modelData.key]); Accessible.name:modelData.label; onActivated:root.change(modelData.key,currentText) }
            }
        }
    }
    GlowText { visible:!root.fields.length; text:"Input settings are unavailable. The service message above contains the compositor error."; color:Theme.muted; Layout.fillWidth:true; wrapMode:Text.WordWrap }
    Flow {
        Layout.fillWidth:true; spacing:8; Layout.topMargin:16
        StationButton { text:"Apply input settings"; enabled:root.dirty && !DesktopSettings.busy; onClicked:DesktopSettings.apply({action:"input",values:root.edits,expected:root.base}) }
        StationButton { text:"Discard edits"; enabled:root.dirty; onClicked:root.load() }
        StationButton { text:root.resetConfirm ? "Confirm reset":"Reset Input"; enabled:!DesktopSettings.busy; onClicked:{if(root.resetConfirm){DesktopSettings.apply({action:"reset-input"});root.resetConfirm=false;}else root.resetConfirm=true;} }
        StationButton { visible:root.resetConfirm; text:"Cancel"; onClicked:root.resetConfirm=false }
    }
    GlowText { visible:root.resetConfirm; text:"Removes only CEDAR’s input overrides. Your manually maintained Hyprland configuration takes effect again."; color:Theme.amber; Layout.fillWidth:true; wrapMode:Text.WordWrap; font.pixelSize:Theme.small }
}
