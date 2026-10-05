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
    readonly property bool requested: Canopy.shown && Canopy.screen === modelData
    property bool mapped: false
    visible: mapped
    onRequestedChanged: {
        if(requested){closeDelay.stop();mapped=true;}
        else if(ShellState.locked || Theme.reducedMotion){closeDelay.stop();mapped=false;}
        else closeDelay.restart();
    }
    Component.onCompleted: if(requested) mapped=true
    Timer {id:closeDelay;interval:Theme.transition;onTriggered:if(!root.requested)root.mapped=false}
    Connections {target:ShellState;function onLockedChanged(){if(ShellState.locked){closeDelay.stop();root.mapped=false;}}}
    anchors.top: true
    margins.top: (Config.barDetached ? Config.barMargin : 0) + Config.barHeight + 8
    implicitWidth: Math.min(modelData?.width - 24 || 560, Canopy.peeking ? 360 : ["audio", "system"].includes(Canopy.topic) ? 760 : Canopy.topic === "quick" ? 420 : 520)
    implicitHeight: Math.max(120, Math.min((modelData?.height || 800) - margins.top - 24, Canopy.peeking ? 160 : Canopy.topic === "quick" ? 660 : 700))
    color: Theme.transparent
    exclusionMode: ExclusionMode.Ignore
    mask: Region {
        item: presentation
    }
    WlrLayershell.namespace: "cedar-canopy"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: requested && !Canopy.pinned && !Canopy.peeking ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    HyprlandFocusGrab {
        windows: [root].concat(Canopy.controlWindows.filter(window => window.visible))
        active: root.requested && !Canopy.pinned && !Canopy.peeking && !Config.testMode
        onCleared: if (root.visible && !Canopy.pinned && !Canopy.peeking)
            Canopy.close()
    }
    contentItem.focus: true
    contentItem.Keys.onEscapePressed: Canopy.close()
    Loader {
        id: presentation
        width: parent.width; height: parent.height
        active: root.mapped
        asynchronous: true
        enabled: root.requested
        y: root.requested || Theme.reducedMotion ? 0 : -8
        opacity: root.requested ? 1 : 0
        sourceComponent: Component { CanopyPanel { active: root.requested } }
        Behavior on y { enabled:!Theme.reducedMotion; NumberAnimation { duration:Theme.transition;easing.type:Easing.OutCubic } }
        Behavior on opacity { enabled:!Theme.reducedMotion; NumberAnimation { duration:Theme.fast } }
    }
}
