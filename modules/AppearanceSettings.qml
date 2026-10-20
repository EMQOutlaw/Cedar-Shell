import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../components/SettingsSchema.js" as Schema
import "../services"
ColumnLayout {
    id: root
    property bool active:false
    property string highlightKey:""
    property string tab:"Themes"
    readonly property bool dirty:SettingsInfo.themePreview!==null
    readonly property var preview:SettingsInfo.themePreview
    readonly property var themes:SettingsInfo.data.themes || []
    readonly property string current:(SettingsInfo.data.theme || "").toLowerCase()
    spacing:16
    function discard(){SettingsInfo.themePreview=null;}
    function selectTheme(name, accent=""){SettingsInfo.run({action:"theme-preview",name:name,accent:accent});}
    onHighlightKeyChanged: {
        const f=Schema.fields.find(f=>f.key===highlightKey);
        if(f)tab=f.group==="Typography" ? "Typography":"Surfaces";
    }
    SettingsTabs { tabs:["Themes","Colors","Surfaces","Typography","Living Edge","Grain"];current:root.tab;onChosen:tab=>root.tab=tab }
    SettingsBarPreview { active:root.active;palette:root.preview?.palette || ({});Layout.fillWidth:true }
    SettingsSurface {
        visible:root.tab==="Themes" || root.tab==="Colors"
        GlowText { text:root.tab==="Themes" ? "Installed themes":"Theme accents";font.family:Theme.labelFont;font.pixelSize:Theme.title }
        GridLayout {
            visible:root.tab==="Themes";Layout.fillWidth:true;columns:root.width<600 ? 2:3;columnSpacing:10;rowSpacing:10
            Repeater {
                model:root.themes
                StationButton {
                    id:tile
                    required property var modelData
                    readonly property bool selected:(root.preview?.name || root.current)===modelData.name
                    readonly property var palette:modelData.palette || ({})
                    Layout.fillWidth:true;Layout.minimumWidth:0;implicitHeight:140
                    text:modelData.label;checked:selected;enabled:!SettingsInfo.busy
                    onClicked:root.selectTheme(modelData.name)
                    background:ChamferFrame {cut:7;fill:tile.palette.background || Theme.background;stroke:tile.visualFocus ? Theme.green:Qt.alpha(Theme.strataAccent,tile.selected ? .7:.2);topLine:tile.selected;topLineColor:Theme.strataAccent}
                    contentItem:ColumnLayout {
                        spacing:8
                        Rectangle {
                            Layout.fillWidth:true;implicitHeight:52;radius:Theme.controlRadius
                            color:tile.palette.surface || Theme.surface
                            Row {anchors.centerIn:parent;spacing:6;Repeater {model:[tile.palette.green || Theme.green,tile.palette.teal || Theme.teal,tile.palette.amber || Theme.amber,tile.palette.text || Theme.text];Rectangle {required property color modelData;width:18;height:18;radius:9;color:modelData}}}
                        }
                        GlowText {text:tile.modelData.label; color:tile.palette.text || Theme.text;font.family:Theme.labelFont;font.pixelSize:Theme.normal;Layout.fillWidth:true;elide:Text.ElideRight}
                        GlowText {text:(tile.modelData.mode==="light" ? "Light":"Dark")+(tile.modelData.name===root.current ? " · Active":tile.selected ? " · Preview":"");color:tile.palette.muted || Theme.muted;font.pixelSize:Theme.small;Layout.fillWidth:true;elide:Text.ElideRight}
                    }
                }
            }
        }
        GlowText {visible:!root.themes.length;text:"No installed themes were found.";color:Theme.muted;Layout.fillWidth:true;wrapMode:Text.WordWrap}
        Flow {
            visible:root.tab==="Colors";Layout.fillWidth:true;spacing:8
            Repeater {
                model:["green","teal","amber","ember"]
                StationButton {
                    required property string modelData
                    text:modelData.charAt(0).toUpperCase()+modelData.slice(1)
                    accent:root.preview?.palette?.[modelData] || Theme[modelData]
                    checked:root.preview?.accent===modelData;enabled:!SettingsInfo.busy && root.themes.length>0
                    onClicked:root.selectTheme(root.preview?.name || (root.themes.find(t=>t.name===root.current)?.name || root.themes[0].name),modelData)
                }
            }
        }
        GlowText {text:"Selections preview locally. Apply changes CEDAR’s palette; application palettes remain separately managed.";color:Theme.muted;font.pixelSize:Theme.small;Layout.fillWidth:true;wrapMode:Text.WordWrap}
        Flow {
            Layout.fillWidth:true;spacing:8
            StrataButton {text:SettingsInfo.busy ? "Working…":"Apply theme";enabled:root.dirty && !SettingsInfo.busy;onClicked:SettingsInfo.run(Object.assign({action:"theme-apply"},root.preview))}
            StrataButton {text:"Cancel preview";enabled:root.dirty && !SettingsInfo.busy;onClicked:root.discard()}
            StrataButton {text:"Restore previous theme";enabled:SettingsInfo.data.themeRestoreAvailable===true && !SettingsInfo.busy;onClicked:SettingsInfo.run({action:"theme-restore"})}
        }
    }
    SettingsFields {visible:root.tab==="Typography";page:"appearance";groups:["Typography"];highlightKey:root.highlightKey;Layout.fillWidth:true}
    SettingsFields {visible:root.tab==="Surfaces";page:"appearance";groups:["Interface"];highlightKey:root.highlightKey;Layout.fillWidth:true}
    SettingsSurface {
        visible:root.tab==="Living Edge" || root.tab==="Grain"
        GlowText {text:root.tab==="Living Edge" ? "CEDAR’s living surface":"Strata grain";font.family:Theme.labelFont;font.pixelSize:Theme.title}
        GlowText {text:root.tab==="Living Edge" ? "Edge light uses the shared Rootlines, Heartwood and morph surfaces. Adjust their activity in Animations & Effects. Independent edge intensity and global blur controls are not available in this backend.":"Grain is part of Strata’s retained surface geometry. Its contrast follows the active palette; there is no separate grain texture or intensity setting.";color:Theme.muted;Layout.fillWidth:true;wrapMode:Text.WordWrap}
        StrataButton {visible:root.tab==="Living Edge";text:"Open Animations & Effects";onClicked:SettingsService.navigate("animations", "effectIntensity")}
    }
}
