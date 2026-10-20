import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../services"
ColumnLayout {
    id:root
    property bool active:false
    property string highlightKey:""
    spacing:16
    SettingsSurface {
        GlowText {text:"Motion presets";font.family:Theme.labelFont;font.pixelSize:Theme.title}
        Flow {
            Layout.fillWidth:true;spacing:8
            Repeater {
                model:[{label:"CEDAR Default",value:"balanced",reduced:false},{label:"Calm",value:"calm",reduced:false},{label:"Expressive",value:"expressive",reduced:false},{label:"Minimal",value:"off",reduced:false},{label:"Reduced Motion",value:"off",reduced:true}]
                StrataButton {
                    required property var modelData
                    text:modelData.label;checked:Config.saved.motionPreset===modelData.value && Config.saved.reducedMotion===modelData.reduced
                    onClicked:{Config.set("motionPreset",modelData.value);Config.set("reducedMotion",modelData.reduced);}
                }
            }
        }
        GlowText {text:"Presets use CEDAR’s shared motion policy. Performance and Gaming modes shorten transitions automatically.";color:Theme.muted;font.pixelSize:Theme.small;Layout.fillWidth:true;wrapMode:Text.WordWrap}
    }
    SettingsSurface {
        GlowText {text:"Motion laboratory";font.family:Theme.labelFont;font.pixelSize:Theme.title}
        SettingsBarPreview {id:preview;active:root.active;Layout.fillWidth:true}
        Flow {
            Layout.fillWidth:true;spacing:8
            StrataButton {text:preview.expanded ? "Contract surface":"Expand surface";onClicked:preview.play()}
            StrataButton {text:"Retarget pop-out";onClicked:{preview.expanded=true;preview.origin=preview.origin===.5 ? .82:.5;preview.previewText="Retargeted";}}
            StrataButton {text:"Kinetic label";onClicked:{preview.expanded=true;preview.previewText=preview.previewText==="Your environment" ? "Your flow":"Your environment";}}
        }
        GlowText {text:"Grow "+VisualQuality.ms(Theme.morphGrow)+" ms · Contract "+VisualQuality.ms(Theme.morphShrink)+" ms · "+(VisualQuality.functionalMotion ? "Shared transitions":"Motion disabled");color:Theme.muted;font.pixelSize:Theme.small;Layout.fillWidth:true;wrapMode:Text.WordWrap}
    }
    SettingsFields {page:"animations";highlightKey:root.highlightKey;Layout.fillWidth:true}
}
