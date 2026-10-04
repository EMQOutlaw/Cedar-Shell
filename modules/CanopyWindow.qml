import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import ".."
import "../services"

PanelWindow {
    id: root
    required property var modelData
    screen: modelData
    visible: Canopy.shown && Canopy.screen === modelData
    anchors.top: true
    margins.top: (Config.barDetached ? Config.barMargin : 0) + Config.barHeight + 8
    implicitWidth: Math.min(modelData?.width - 24 || 560, Canopy.peeking ? 360 : ["audio", "system", "quick"].includes(Canopy.topic) ? 900 : 600)
    implicitHeight: Math.max(120, Math.min((modelData?.height || 800) - margins.top - 24, Canopy.peeking ? 160 : 760))
    color: Theme.transparent
    exclusionMode: ExclusionMode.Ignore
    mask: Region {
        item: card
    }
    WlrLayershell.namespace: "cedar-canopy"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible && !Canopy.pinned && !Canopy.peeking ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    HyprlandFocusGrab {
        windows: [root].concat(Canopy.controlWindows.filter(window => window.visible))
        active: root.visible && !Canopy.pinned && !Canopy.peeking && !Config.testMode
        onCleared: if (root.visible && !Canopy.pinned && !Canopy.peeking)
            Canopy.close()
    }
    contentItem.focus: true
    contentItem.Keys.onEscapePressed: Canopy.close()
    CanopyPanel {
        id: card
        width: parent.width
        height: parent.height
        active: root.visible
        y: root.visible ? 0 : -18
        opacity: root.visible ? 1 : 0
        Behavior on y {
            enabled: !Theme.reducedMotion
            NumberAnimation {
                duration: Theme.transition
                easing.type: Easing.OutCubic
            }
        }
        Behavior on opacity {
            enabled: !Theme.reducedMotion
            OpacityAnimator {
                duration: Theme.fast
            }
        }
    }
}
