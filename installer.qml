import QtQuick
import Quickshell
import "installer/ui"

// CEDAR Installer: a standalone Quickshell program (qs -p installer.qml). It
// lives at the source root because Quickshell imports stay inside the root
// of the program it starts; the pages are in installer/ui. It needs CEDAR's
// Theme and shared components from the source tree it is installing, never
// an installed CEDAR. The window and the engine process both run as the
// user; only a package transaction asks for privilege, through polkit or
// the terminal that started the installer.
ShellRoot {
    settings.watchFiles: false
    InstallerModel { id: model }
    FloatingWindow {
        id: window
        title: "CEDAR Installer"
        visible: true
        implicitWidth: 1120; implicitHeight: 720
        minimumSize: Qt.size(880, 600)
        color: Theme.background
        Item {
            anchors.fill: parent
            SystemVisual {
                id: visual
                model: model
                visible: model.stage !== "welcome"
                width: Math.round(parent.width * .44)
                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            }
            StagePane {
                model: model
                anchors { left: visual.visible ? visual.right : parent.left; right: parent.right; top: parent.top; bottom: parent.bottom }
            }
        }
    }
}
