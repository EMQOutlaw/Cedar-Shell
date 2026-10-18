import QtQuick
import Quickshell
import ".."
import "../services"

// One normal, compositor-resizable window. Keep drafts alive when it is hidden.
FloatingWindow {
    id: root
    title: "CEDAR Settings"
    color: Theme.background
    minimumSize: Qt.size(SettingsService.minimumWidth, SettingsService.minimumHeight)
    implicitWidth: SettingsService.windowSize.width
    implicitHeight: SettingsService.windowSize.height
    visible: SettingsService.open
    onVisibleChanged: if (!visible) SettingsService.closeApp()
    onWidthChanged: if (visible) remember.restart()
    onHeightChanged: if (visible) remember.restart()
    Timer { id: remember; interval: 400; onTriggered: SettingsService.rememberWindow(root.width, root.height) }
    SettingsPanel { anchors.fill: parent; active: root.visible }
}
