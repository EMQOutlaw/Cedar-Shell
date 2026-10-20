import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
ColumnLayout {
    property string highlightKey:""
    spacing:16
    SettingsSurface {
        GlowText {text:"Trailwatch & session security";font.family:Theme.labelFont;font.pixelSize:Theme.title}
        GlowText {text:Config.externalSession ? "Your existing locker owns authentication. Select and verify Trailwatch through Desktop Setup before changing the locker.":"Trailwatch uses the compositor’s secure session-lock protocol and your system authentication. Notification contents remain hidden while locked.";color:Theme.muted;Layout.fillWidth:true;wrapMode:Text.WordWrap}
    }
    SettingsFields {page:"security";highlightKey:parent.highlightKey;Layout.fillWidth:true}
}
