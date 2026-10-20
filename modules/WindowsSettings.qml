import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import ".."
import "../components"
ColumnLayout {
    spacing:16
    SettingsSurface {
        GlowText {text:"Live workspaces";font.family:Theme.labelFont;font.pixelSize:Theme.title}
        GlowText {text:"Switch to a workspace below. Layout rules continue to belong to your Hyprland configuration.";Layout.fillWidth:true;wrapMode:Text.WordWrap;color:Theme.muted}
        Flow {
            Layout.fillWidth:true;spacing:8
            Repeater {
                model:Hyprland.workspaces.values
                StrataButton {required property var modelData;text:modelData.name || String(modelData.id);checked:modelData.active;onClicked:modelData.activate()}
            }
        }
        GlowText {visible:!Hyprland.workspaces.values.length;text:"Hyprland has not reported any workspaces.";color:Theme.muted;Layout.fillWidth:true;wrapMode:Text.WordWrap}
    }
    SettingsSurface {
        GlowText {text:"Layout configuration · unavailable here";font.family:Theme.labelFont;font.pixelSize:Theme.title;Layout.fillWidth:true;wrapMode:Text.WordWrap}
        GlowText {text:"This version has no safe Settings editor for gaps, window borders, rounding, tiling rules or scratchpads. Your existing compositor configuration remains authoritative. Input, keybind and display editors use their own verified CEDAR-owned fragments.";Layout.fillWidth:true;wrapMode:Text.WordWrap;color:Theme.muted}
    }
}
