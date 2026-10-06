import QtQuick
import Quickshell
import ".."
import "../services"

// Shared centered entry on secondary monitors or when activity Core is disabled.
Row {
    property string outputName: ""
    objectName: "barCoreControls"
    spacing: 2
    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }
    BarButton {
        objectName: "fallbackCoreHeader"
        height: parent.height
        implicitWidth: Math.min(220, Math.max(36, contentItem.implicitWidth + 20))
        text: Config.moduleEnabled("clock") ? Config.barClock(clock.date) : "◈"
        hint: "Quick Controls"
        enabled: !ShellState.locked
        checked: Canopy.shown && Canopy.topic === "quick"
        onClicked: Canopy.toggleQuick(parent.outputName)
    }
    NetworkIndicator {
        visible: Config.moduleEnabled("network")
        height: parent.height
        outputName: parent.outputName
        inline: true
    }
}
