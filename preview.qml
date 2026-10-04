import QtQuick
import QtQuick.Layouts
import Quickshell
import "components"
import "modules"
import "services"
ShellRoot {
    settings.watchFiles: false
    FloatingWindow {
        visible: true
        title: "CEDAR isolated preview · local fixtures · no desktop takeover"
        implicitWidth: 960; implicitHeight: 800
        color: Theme.background
        ColumnLayout {
            anchors.fill: parent; anchors.margins: 12
            GlowText { text: "ISOLATED PREVIEW · local fixtures / no lock, wallpaper or notification ownership"; Layout.fillWidth: true; wrapMode: Text.WordWrap; color: Theme.amber }
            CanopyPanel { Layout.fillWidth: true; Layout.fillHeight: true; active: true }
        }
        Component.onCompleted: { Canopy.open("quick"); }
    }
}
