import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."
import "../components"
import "../services"
ColumnLayout {
    id:root
    property string highlightKey:""
    property string tab:"Wallpapers"
    property string chosen:""
    readonly property var wallpapers:SettingsInfo.data.wallpapers || []
    readonly property string current:SettingsInfo.data.wallpaper || ""
    readonly property string selected:chosen || current
    readonly property bool dirty:chosen!=="" && chosen!==current
    spacing:16
    function discard(){chosen="";}
    onHighlightKeyChanged:if(highlightKey && highlightKey!=="wallpaper")tab="Settings"
    SettingsTabs {tabs:["Wallpapers","Screensavers","Settings"];current:root.tab;onChosen:tab=>root.tab=tab}
    GridLayout {
        visible:root.tab==="Wallpapers";Layout.fillWidth:true;columns:root.width<800 ? 1:2;columnSpacing:16;rowSpacing:16
        GridView {
            id:gallery
            Layout.fillWidth:true;Layout.minimumWidth:0;Layout.preferredWidth:root.width*.58
            implicitHeight:Math.min(440,Math.max(220,Math.ceil(root.wallpapers.length/Math.max(1,Math.floor(width/150)))*116))
            cellWidth:width/Math.max(1,Math.floor(width/150));cellHeight:116
            model:root.wallpapers;clip:true;cacheBuffer:116
            ScrollBar.vertical:ScrollBar {}
            delegate:StationButton {
                id:tile
                required property var modelData
                width:gallery.cellWidth-8;height:gallery.cellHeight-8
                text:modelData.name;hint:modelData.name;checked:root.selected===modelData.path
                onClicked:root.chosen=modelData.path
                background:ChamferFrame {cut:6;fill:Theme.surface;stroke:tile.visualFocus ? Theme.green:tile.checked ? Theme.strataAccent:Qt.alpha(Theme.border,.4);strokeWidth:tile.checked ? 2:1}
                contentItem:ColumnLayout {
                    spacing:5
                    Image {Layout.fillWidth:true;Layout.fillHeight:true;source:Config.imageSource("file://"+tile.modelData.path);sourceSize.width:256;asynchronous:true;cache:true;fillMode:Image.PreserveAspectCrop;clip:true}
                    GlowText {text:tile.modelData.name;font.pixelSize:Theme.small-1;Layout.fillWidth:true;elide:Text.ElideRight}
                }
            }
        }
        SettingsSurface {
            Layout.preferredWidth:300;Layout.alignment:Qt.AlignTop
            Image {
                id:hero;Layout.fillWidth:true;Layout.preferredHeight:190
                source:root.selected ? Config.imageSource("file://"+root.selected):""
                sourceSize.width:900;asynchronous:true;cache:true
                fillMode:Config.saved.wallpaperMode==="fit" ? Image.PreserveAspectFit:Config.saved.wallpaperMode==="stretch" ? Image.Stretch:Image.PreserveAspectCrop;clip:true
            }
            GlowText {text:root.wallpapers.find(w=>w.path===root.selected)?.name || "Select a wallpaper";font.family:Theme.labelFont;font.pixelSize:Theme.title;Layout.fillWidth:true;wrapMode:Text.WordWrap}
            GlowText {text:"Target: all displays\nFit: "+({crop:"Fill screen",fit:"Fit image",stretch:"Stretch"})[Config.saved.wallpaperMode]+"\nPer-display targeting is not supported by this provider.";font.pixelSize:Theme.small;color:Theme.muted;Layout.fillWidth:true;wrapMode:Text.WordWrap}
            Flow {Layout.fillWidth:true;spacing:8
                StrataButton {text:SettingsInfo.busy ? "Applying…":"Apply wallpaper";enabled:root.dirty && !SettingsInfo.busy && hero.status===Image.Ready;onClicked:SettingsInfo.run({action:"wallpaper",path:root.selected})}
                StrataButton {text:"Cancel";enabled:root.dirty && !SettingsInfo.busy;onClicked:root.discard()}
            }
        }
    }
    GlowText {visible:root.tab==="Wallpapers" && !root.wallpapers.length;text:"No images were found. Add a wallpaper folder in Settings.";color:Theme.muted;Layout.fillWidth:true;wrapMode:Text.WordWrap}
    SettingsSurface {
        visible:root.tab==="Screensavers"
        GlowText {text:"Screensaver controls are not available";font.family:Theme.labelFont;font.pixelSize:Theme.title;Layout.fillWidth:true;wrapMode:Text.WordWrap}
        GlowText {text:"CEDAR has no independent screensaver backend in this version. Your existing desktop provider keeps control. Trailwatch is a secure lock screen, not a screensaver; its privacy controls are in Lock Screen & Security.";color:Theme.muted;Layout.fillWidth:true;wrapMode:Text.WordWrap}
    }
    SettingsFields {visible:root.tab==="Settings";page:"desktop";groups:["Background","Advanced"];highlightKey:root.highlightKey;Layout.fillWidth:true}
    WeatherLocationSettings {visible:root.tab==="Settings";highlightKey:root.highlightKey;Layout.fillWidth:true}
}
