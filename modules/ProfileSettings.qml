import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../components/core/Profiles.js" as Policy
import "../services"
ColumnLayout {
    id:root
    property string selected:Profiles.current || "balanced"
    readonly property var definition:Profiles.definition(selected)
    readonly property var operations:Profiles.managed(selected)
    spacing:16
    function currentValue(key) {
        if(Policy.configKeys[key])return Config.saved[Policy.configKeys[key]];
        if(key==="power")return Controls.data.profile || undefined;
        if(key==="nightlight")return Controls.data.nightlight;
        return undefined;
    }
    function supported(op) {
        if(op.key==="power")return Controls.data.profiles.includes(op.value);
        if(op.key==="nightlight")return Controls.data.nightlight!==null && Controls.data.nightlight!==undefined;
        if(op.key==="audioScene")return (AudioInstruments.data.scenes || []).some(s=>(s.name || s)===op.value);
        return !!Policy.configKeys[op.key];
    }
    function changeLabel(op) {
        if(!supported(op))return "Unsupported";
        const v=currentValue(op.key);
        if(v===undefined || v===null)return "Current value unknown";
        return v===op.value ? "Unchanged":typeof op.value==="boolean" ? (op.value ? "Enabled":"Disabled"):"Modified";
    }
    GridLayout {
        Layout.fillWidth:true;columns:root.width<650 ? 2:3;columnSpacing:10;rowSpacing:10
        Repeater {
            model:Profiles.definitions
            StationButton {
                id:tile
                required property var modelData
                Layout.fillWidth:true;Layout.minimumWidth:0;implicitHeight:100
                text:modelData.label;checked:root.selected===modelData.id
                onClicked:root.selected=modelData.id
                background:ChamferFrame {cut:7;fill:Qt.alpha(Theme.surface,.8);stroke:tile.visualFocus ? Theme.green:Qt.alpha(Profiles.accentOf(tile.modelData.id),tile.checked ? .65:.2);topLine:tile.checked;topLineColor:Profiles.accentOf(tile.modelData.id)}
                contentItem:ColumnLayout {
                    spacing:6
                    GlowText {text:tile.modelData.label+(Profiles.current===tile.modelData.id ? (Profiles.anyBusy ? " · Working":" · Active"):"");font.family:Theme.labelFont;font.pixelSize:Theme.title;Layout.fillWidth:true;elide:Text.ElideRight}
                    GlowText {text:tile.modelData.line;color:Theme.muted;font.pixelSize:Theme.small;Layout.fillWidth:true;wrapMode:Text.WordWrap}
                }
            }
        }
    }
    SettingsSurface {
        GlowText {text:"Preview changes · "+(root.definition?.label || "");font.family:Theme.labelFont;font.pixelSize:Theme.title}
        GlowText {visible:root.selected==="gaming";text:"Gaming Mode uses its existing capability checks, verified steps and restoration. Power, idle inhibition and visual changes are shown below as the transaction runs.";Layout.fillWidth:true;wrapMode:Text.WordWrap;color:Theme.muted}
        GlowText {visible:!root.operations.length && root.selected!=="gaming";text:"This profile has no configured changes.";color:Theme.muted}
        Repeater {
            model:root.operations
            SettingRow {
                required property var modelData
                Layout.fillWidth:true;title:Profiles.ops[modelData.key].label
                description:(root.currentValue(modelData.key)===undefined || root.currentValue(modelData.key)===null ? "Unknown":Profiles.describe(modelData.key,root.currentValue(modelData.key)))+" → "+Profiles.describe(modelData.key,modelData.value)
                StatusPill {text:root.changeLabel(modelData);tone:root.supported(modelData) ? Theme.strataAccent:Theme.warning}
            }
        }
        Flow {Layout.fillWidth:true;spacing:8
            StrataButton {text:Profiles.anyBusy ? "Working…":"Apply "+(root.definition?.label || "profile");enabled:!Profiles.anyBusy && Profiles.current!==root.selected;onClicked:Profiles.activateChecked(root.selected)}
            StrataButton {text:"Restore previous settings";enabled:!!Profiles.current && !Profiles.anyBusy;onClicked:Profiles.current==="gaming" ? Gaming.deactivate():Profiles.deactivate()}
        }
        GlowText {text:Profiles.settingsFailure || Profiles.summary;Layout.fillWidth:true;wrapMode:Text.WordWrap;color:Profiles.settingsFailure || Profiles.failures.length ? Theme.warning:Theme.strataAccent}
        GlowText {visible:Profiles.error!=="";text:Profiles.error;color:Theme.warning;Layout.fillWidth:true;wrapMode:Text.WordWrap}
        Repeater {
            model:Profiles.current==="gaming" ? Gaming.steps:Profiles.steps
            SettingRow {required property var modelData;Layout.fillWidth:true;title:modelData.label;description:modelData.detail;StatusPill {text:modelData.state;tone:modelData.state==="failed" ? Theme.warning:Theme.strataAccent}}
        }
    }
    SettingsSurface {
        visible:root.selected==="custom"
        GlowText {text:"Custom profile";font.family:Theme.labelFont;font.pixelSize:Theme.title}
        GlowText {text:"Configure the existing Custom profile with its full operation editor.";Layout.fillWidth:true;wrapMode:Text.WordWrap;color:Theme.muted}
        StrataButton {text:"Open profile editor";onClicked:Profiles.openApp()}
    }
}
