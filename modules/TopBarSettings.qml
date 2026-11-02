import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../components/SettingsSchema.js" as Schema
import "../services"
// Shell & Bar: every bar control on one page. The preview at the top is the
// map — it shows where each section's controls live on the real bar.
ColumnLayout {
    id:root
    property bool active:false
    property string highlightKey:""
    spacing:16
    SettingsBarPreview {id:preview;active:root.active;Layout.fillWidth:true}
    SettingsSurface {
        GlowText {text:"Bar geometry & material";font.family:Theme.labelFont;font.pixelSize:Theme.title}
        SettingsFields {page:"bar";cards:false;highlightKey:root.highlightKey;Layout.fillWidth:true}
        GlowText {text:"CEDAR Strata uses shared fixed padding, module spacing and chamfer geometry. Independent padding, margin and corner-radius controls are not supported by this bar style.";font.pixelSize:Theme.small;color:Theme.muted;Layout.fillWidth:true;wrapMode:Text.WordWrap}
    }
    SettingsSurface {
        // Search anchors: the schema extras emit highlightKeys "modules" and
        // "understory" for this page; these objectNames are the scroll targets.
        objectName: "modules"
        GlowText {text:"Bar modules";font.family:Theme.labelFont;font.pixelSize:Theme.title}
        GlowText {text:"Which controls sit along the bar. CEDAR keeps a stable order and compresses modules as space narrows; arbitrary ordering is not supported by the current Strata layout.";color:Theme.muted;Layout.fillWidth:true;wrapMode:Text.WordWrap}
        Repeater {
            model:Schema.modules
            SettingRow {
                required property var modelData
                Layout.fillWidth:true;title:modelData.label
                StationToggle {Layout.fillWidth:true;accessibleLabel:modelData.label;checked:Config.moduleEnabled(modelData.key);onToggled:value=>Config.setModule(modelData.key,value)}
            }
        }
    }
    SettingsSurface {
        GlowText {text:"Pop-outs & behavior";font.family:Theme.labelFont;font.pixelSize:Theme.title}
        // Canopy visibility and hover previews are the schema-rendered Canopy
        // and Peek controls in the Core section below — one control each.
        GlowText {text:"Canopy is the drop that grows from bar controls; its visibility and hover previews are set in the Core section below. The preview shows the production DropFrame geometry; live panels use the monitor's logical bounds.";color:Theme.muted;Layout.fillWidth:true;wrapMode:Text.WordWrap}
        Flow {Layout.fillWidth:true;spacing:8
            StrataButton {text:preview.expanded ? "Close":"Preview the drop geometry";onClicked:preview.play()}
            StrataButton {text:"Retarget";onClicked:{preview.expanded=true;preview.origin=preview.origin===.1 ? .9:.1;}}
            StrataButton {text:"Clock and date settings";onClicked:SettingsService.navigate("time", "")}
        }
    }
    // The dynamic island and the left rail live here now (one home); the old
    // standalone Dynamic Island page was a second route to the same controls.
    CoreSettings {highlightKey:root.highlightKey;Layout.fillWidth:true}
    SettingsSurface {
        objectName: "understory"
        UnderstorySettings {active:root.active;Layout.fillWidth:true}
    }
}
