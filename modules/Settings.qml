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
    // Screen geometry is already in logical pixels; do not multiply by the
    // output scale. A remembered size from a larger monitor is only an initial
    // hint, clamped to leave room for the compositor's frame and desktop bar.
    implicitWidth: Math.max(SettingsService.minimumWidth, Math.min(SettingsService.windowSize.width, (screen?.width || 1280) - 48))
    implicitHeight: Math.max(SettingsService.minimumHeight, Math.min(SettingsService.windowSize.height, (screen?.height || 840) - 80))
    visible: SettingsService.open
    onVisibleChanged: if (!visible) SettingsService.closeApp()
    onWidthChanged: if (visible) remember.restart()
    onHeightChanged: if (visible) remember.restart()
    Timer { id: remember; interval: 400; onTriggered: SettingsService.rememberWindow(root.width, root.height) }
    SettingsPanel { anchors.fill: parent; active: root.visible }
}
