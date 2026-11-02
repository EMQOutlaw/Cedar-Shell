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
    onActiveChanged:if(active)Shield.refresh()
    Component.onCompleted:if(active)Shield.refresh()
    SettingsFields {page:"privacy";groups:["Privacy"];highlightKey:root.highlightKey;Layout.fillWidth:true}
    // Session security (the locker, its protocol and authentication) belongs
    // with the protections that surround it — moved here from the Lock Screen
    // page when that became its own thing.
    SettingsSurface {
        objectName: "sessionSecurity"
        GlowText {text:"Trailwatch & session security";font.family:Theme.labelFont;font.pixelSize:Theme.title}
        GlowText {text:Config.externalSession ? "Your existing locker owns authentication. Select and verify Trailwatch through Desktop Setup before changing the locker.":"Trailwatch uses the compositor's secure session-lock protocol and your system authentication. Notification contents remain hidden while locked.";color:Theme.muted;Layout.fillWidth:true;wrapMode:Text.WordWrap}
    }
    ShieldPages {embedded:true;Layout.fillWidth:true;implicitHeight:760;onClosed:SettingsService.closeApp()}
}
