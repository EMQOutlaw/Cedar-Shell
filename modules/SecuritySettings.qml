import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
// Lock Screen: what shows and what works while the desktop is locked. The
// session-security posture lives on Privacy & Shield, where it belongs.
ColumnLayout {
    property string highlightKey:""
    spacing:16
    SettingsFields {page:"security";highlightKey:parent.highlightKey;Layout.fillWidth:true}
    GlowText {
        Layout.fillWidth: true; wrapMode: Text.WordWrap; color: Theme.muted; font.pixelSize: Theme.small
        text: "More lock-screen options are pinned for future consideration."
    }
}
