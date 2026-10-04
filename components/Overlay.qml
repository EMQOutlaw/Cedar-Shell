import QtQuick
import Quickshell
import Quickshell.Wayland
import ".."

PanelWindow {
    id: root
    required property var output
    required property string panelName
    screen: output
    visible: ShellState.shows(panelName, output)
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: Theme.veil
    WlrLayershell.namespace: "cedar-" + panelName
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    contentItem.focus: true
    contentItem.Keys.onEscapePressed: ShellState.close()
    MouseArea { anchors.fill: parent; onClicked: ShellState.close() }
}
