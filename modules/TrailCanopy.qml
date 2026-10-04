import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../services"
ColumnLayout {
    spacing:12
    StationToggle {Layout.fillWidth:true;label:"Remember Trails";description:"Session-only CEDAR navigation and application identity. No window titles or page content. Cleared on lock or when disabled.";checked:Config.saved.forestTrails;onToggled:value=>Config.set("forestTrails",value)}
    StationButton {text:"Clear trail";onClicked:Forest.clearTrails()}
    Repeater {
        model:Forest.trails
        StationButton {
            required property var modelData
            Layout.fillWidth:true
            text:modelData.label+" · "+Config.formatTime(new Date(modelData.at))
            enabled:["canopy","settings","surface"].includes(modelData.kind)
            onClicked:{if(modelData.kind==="canopy")Canopy.open(modelData.target);else {if(modelData.kind==="settings")ShellState.settingsPage=modelData.target;ShellState.open(modelData.kind==="settings"?"settings":modelData.target);}}
        }
    }
    GlowText {visible:!Forest.trails.length;Layout.fillWidth:true;wrapMode:Text.WordWrap;text:Config.saved.forestTrails?"Your next navigation will start a trail.":"Trails are off.";color:Theme.muted}
}
