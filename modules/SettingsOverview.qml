import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../services"
ColumnLayout {
    id: root
    objectName: "settingsHome"
    property bool active: false
    spacing: 18
    readonly property var monitors: DesktopSettings.data.monitors.filter(m=>!m.disabled)
    onActiveChanged: if(active && !Shield.ready) Shield.refresh()
    Component.onCompleted: if(active && !Shield.ready) Shield.refresh()
    component Summary: StationButton {
        property string heading: ""
        property string value: ""
        property string detail: ""
        property string symbol: ""
        property string destination: ""
        Layout.fillWidth: true; Layout.minimumWidth: 0
        implicitHeight: Math.max(108, summaryBody.implicitHeight+28)
        text: heading; hint: "Open " + heading
        onClicked: SettingsService.navigate(destination, "")
        background: ChamferFrame {
            cut: 7; fill: Qt.alpha(Theme.strataSurface,.68)
            stroke: parent.visualFocus ? Theme.green : Qt.alpha(Theme.strataAccent,.22)
            strokeWidth: parent.visualFocus ? Theme.focusWidth : 1
            topLine: parent.hovered; topLineColor: Theme.strataAccent; topLineFraction:.2
        }
        contentItem: RowLayout {
            id:summaryBody; spacing:12
            Text { text:parent.parent.symbol; font.family:Theme.labelFont; font.pixelSize:28; color:Theme.strataAccent; Layout.preferredWidth:30; horizontalAlignment:Text.AlignHCenter }
            ColumnLayout {
                spacing:5; Layout.fillWidth:true
                GlowText { text:summaryBody.parent.heading; font.pixelSize:Theme.small; color:Theme.muted; Layout.fillWidth:true; elide:Text.ElideRight }
                GlowText { text:summaryBody.parent.value; font.family:Theme.labelFont; font.pixelSize:21*Theme.fontScale; Layout.fillWidth:true; elide:Text.ElideRight }
                GlowText { text:summaryBody.parent.detail; font.pixelSize:Theme.small-1; color:Theme.muted; Layout.fillWidth:true; wrapMode:Text.WordWrap }
            }
        }
    }
    GridLayout {
        Layout.fillWidth:true; columns:root.width<700 ? 2:4; columnSpacing:10; rowSpacing:10
        Summary { heading:"Desktop Profile"; value:Profiles.current ? Profiles.currentLabel:"No profile"; detail:Profiles.anyBusy ? "Applying changes…":Profiles.settingsFailure || Profiles.failures.length || Gaming.failures.length ? "Needs attention":Profiles.current ? "Active":"Your current preferences"; symbol:"△"; destination:"profiles" }
        Summary { heading:"Appearance"; value:SettingsInfo.data.theme || "Unknown"; detail:"CEDAR palette · "+(Config.saved.reducedMotion ? "Reduced motion":"Shared materials"); symbol:"◐"; destination:"appearance" }
        Summary { heading:"System Version"; value:SettingsInfo.data.version || "Unavailable"; detail:SettingsInfo.data.channel || "Channel unavailable"; symbol:"♧"; destination:"about" }
        Summary { heading:"Update Status"; value:SettingsInfo.action==="update-check" && SettingsInfo.busy ? "Checking…":({current:"Verified current",available:"Update available",error:"Check failed"})[SettingsInfo.data.updateStatus?.state] || "Not checked"; detail:SettingsInfo.data.updateStatus?.checkedAt ? "Checked "+Qt.formatDateTime(new Date(SettingsInfo.data.updateStatus.checkedAt*1000),"MMM d, HH:mm"):"Open Updates to verify"; symbol:"↻"; destination:"system" }
    }
    GridLayout {
        Layout.fillWidth:true; columns:root.width<850 ? 1:2; columnSpacing:16; rowSpacing:16
        SettingsSurface {
            padding:18; selected:true
            Layout.preferredWidth:Math.max(420,root.width*.68)
            GlowText { text:"System at a glance"; font.family:Theme.labelFont; font.pixelSize:Theme.title }
            Item {
                Layout.fillWidth:true; implicitHeight:Math.max(160,Math.min(270,width*.34))
                SettingsBackdrop { anchors.fill:parent; strength:.95 }
            }
            GridLayout {
                Layout.fillWidth:true; columns:width<600 ? 2:4; columnSpacing:14; rowSpacing:14
                Repeater {
                    model:[
                        {label:"Displays",value:root.monitors.length ? root.monitors.length+" connected":"Unavailable",detail:root.monitors.map(m=>m.width+"×"+m.height).join(" · "),icon:"▣"},
                        {label:"Audio output",value:Audio.sink?.description || "Unavailable",detail:Audio.audio ? (Audio.muted ? "Muted":Math.round(Audio.volume*100)+"% volume"):"No output reported",icon:"♫"},
                        {label:"Network",value:Network.data.available ? Network.label:"Unavailable",detail:Network.data.available ? Network.statusDescription:"Provider unavailable",icon:"⌁"},
                        {label:"Shield",value:Shield.ready ? Shield.headline:"Not yet verified",detail:Shield.ready ? Shield.onCount+" protections active":"Open Privacy & Shield",icon:"⬡"}]
                    ColumnLayout {
                        required property var modelData
                        Layout.fillWidth:true; Layout.minimumWidth:0; spacing:4
                        GlowText { text:modelData.icon+"  "+modelData.label; color:Theme.strataAccent; font.pixelSize:Theme.small; Layout.fillWidth:true; elide:Text.ElideRight }
                        GlowText { text:modelData.value; font.family:Theme.labelFont; font.pixelSize:Theme.normal; Layout.fillWidth:true; wrapMode:Text.WordWrap }
                        GlowText { text:modelData.detail; color:Theme.muted; font.pixelSize:Theme.small-1; Layout.fillWidth:true; elide:Text.ElideRight }
                    }
                }
            }
        }
        SettingsSurface {
            Layout.preferredWidth:250; Layout.alignment:Qt.AlignTop
            GlowText { text:"Quick actions"; font.family:Theme.labelFont; font.pixelSize:Theme.title }
            Repeater {
                model:[{label:"Change wallpaper",page:"desktop",icon:"▧"},{label:"Adjust bar settings",page:"bar",icon:"━"},{label:"Manage keybinds",page:"keybinds",icon:"⌘"},{label:"Check for updates",page:"system",icon:"↻"}]
                StationButton {
                    required property var modelData
                    objectName:"settingsQuick-"+modelData.page
                    Layout.fillWidth:true; implicitHeight:48
                    text:modelData.icon+"   "+modelData.label+"   →"
                    onClicked:SettingsService.navigate(modelData.page, "")
                    background:ChamferFrame { cut:5; fill:Qt.alpha(Theme.background,.55); stroke:parent.visualFocus ? Theme.green:Qt.alpha(Theme.strataAccent,.17) }
                }
            }
            GlowText { text:"Updates are reviewed before anything is installed."; font.pixelSize:Theme.small; color:Theme.muted; Layout.fillWidth:true; wrapMode:Text.WordWrap }
        }
    }
}
