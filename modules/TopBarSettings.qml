import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../components/SettingsSchema.js" as Schema
import "../services"
ColumnLayout {
    id:root
    property bool active:false
    property string highlightKey:""
    property string tab:"Layout"
    spacing:16
    onHighlightKeyChanged:if(highlightKey)tab=highlightKey==="modules" ? "Modules":highlightKey==="understory" ? "Understory":"Layout"
    SettingsTabs {tabs:["Layout","Modules","Dynamic Island","Understory","Pop-outs","Behavior"];current:root.tab;onChosen:tab=>root.tab=tab}
    SettingsBarPreview {id:preview;active:root.active;Layout.fillWidth:true}
    SettingsSurface {
        visible:root.tab==="Layout"
        GlowText {text:"Bar geometry & material";font.family:Theme.labelFont;font.pixelSize:Theme.title}
        SettingsFields {page:"bar";cards:false;highlightKey:root.highlightKey;Layout.fillWidth:true}
        GlowText {text:"CEDAR Strata uses shared fixed padding, module spacing and chamfer geometry. Independent padding, margin and corner-radius controls are not supported by this bar style.";font.pixelSize:Theme.small;color:Theme.muted;Layout.fillWidth:true;wrapMode:Text.WordWrap}
    }
    SettingsSurface {
        visible:root.tab==="Modules"
        GlowText {text:"Bar modules";font.family:Theme.labelFont;font.pixelSize:Theme.title}
        GlowText {text:"CEDAR keeps a stable order and compresses modules as space narrows. Arbitrary module ordering is not supported by the current Strata layout.";color:Theme.muted;Layout.fillWidth:true;wrapMode:Text.WordWrap}
        Repeater {
            model:Schema.modules
            SettingRow {
                required property var modelData
                Layout.fillWidth:true;title:modelData.label
                StationToggle {Layout.fillWidth:true;accessibleLabel:modelData.label;checked:Config.moduleEnabled(modelData.key);onToggled:value=>Config.setModule(modelData.key,value)}
            }
        }
    }
    CoreSettings {visible:root.tab==="Dynamic Island";highlightKey:root.highlightKey;Layout.fillWidth:true}
    UnderstorySettings {visible:root.tab==="Understory";active:root.active&&visible;Layout.fillWidth:true}
    SettingsSurface {
        visible:root.tab==="Pop-outs"
        GlowText {text:"Surface geometry";font.family:Theme.labelFont;font.pixelSize:Theme.title}
        GlowText {text:"Preview the production DropFrame and Strata geometry. The simulated panel stays inside its preview bounds; live panels use the monitor’s logical bounds.";color:Theme.muted;Layout.fillWidth:true;wrapMode:Text.WordWrap}
        Flow {Layout.fillWidth:true;spacing:8
            StrataButton {text:preview.expanded ? "Close":"Open";onClicked:preview.play()}
            StrataButton {text:"Retarget";onClicked:{preview.expanded=true;preview.origin=preview.origin===.1 ? .9:.1;}}
        }
    }
    SettingsSurface {
        visible:root.tab==="Behavior"
        StationToggle {Layout.fillWidth:true;label:"Canopy pop-outs";checked:Config.saved.canopyEnabled;onToggled:value=>Config.set("canopyEnabled",value)}
        StationToggle {Layout.fillWidth:true;label:"Hover previews";checked:Config.saved.canopyPeek;onToggled:value=>Config.set("canopyPeek",value)}
        StrataButton {text:"Clock and date settings";onClicked:SettingsService.navigate("time", "")}
    }
}
