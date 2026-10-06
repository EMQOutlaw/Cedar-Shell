import QtQuick
import QtQuick.Controls
import Quickshell
import ".."
import "../services"

// The bar's shared control: quiet at rest, one treatment for every action.
AbstractButton {
    id: root
    property color accent: Theme.green
    property bool iconOnly: false
    property string hint: ""
    property string canopyTopic: ""
    property string canopyOutput: ""
    // A control with a Canopy topic registers where that panel descends from:
    // the screen x of its centre, for a full-width bar or a centred window alike.
    property bool anchorsCanopy: true
    readonly property string anchorOutput: canopyOutput || CoreService.hostName
    function anchorX() {
        const win = root.QsWindow.window;
        if (!win || !win.screen)
            return -1;
        const p = root.mapToItem(null, root.width / 2, 0);
        return (win.screen.width - win.width) / 2 + p.x;
    }
    function publishAnchor() {
        if (!canopyTopic)
            return;
        if (visible && anchorsCanopy)
            Canopy.setAnchorProvider(canopyTopic, anchorOutput, root.anchorX);
        else
            Canopy.clearAnchorProvider(canopyTopic, anchorOutput, root.anchorX);
    }
    Component.onCompleted: publishAnchor()
    Component.onDestruction: if (canopyTopic) Canopy.clearAnchorProvider(canopyTopic, anchorOutput, root.anchorX)
    onVisibleChanged: publishAnchor()
    onCanopyTopicChanged: publishAnchor()
    onAnchorOutputChanged: publishAnchor()
    function updatePeek() {
        if (enabled && (hovered || visualFocus) && canopyTopic && Config.saved.canopyPeek) peekDelay.restart();
        else { peekDelay.stop(); Canopy.leavePeek(); }
    }
    onHoveredChanged: updatePeek()
    onVisualFocusChanged: updatePeek()
    onEnabledChanged: updatePeek()
    Timer {id:peekDelay;interval:450;onTriggered:if(root.enabled && (root.hovered || root.visualFocus))Canopy.open(root.canopyTopic,root.canopyOutput,true)}
    implicitWidth: iconOnly ? 32 : Math.max(32, label.implicitWidth + 20)
    implicitHeight: Math.max(24, Config.barHeight - 16)
    hoverEnabled: true
    activeFocusOnTab: true
    padding: 4
    HoverHandler { cursorShape: Qt.PointingHandCursor }
    background: Rectangle {
        radius: 5
        color: root.down ? Qt.alpha(root.accent, 0.18)
             : root.checked ? Qt.alpha(root.accent, 0.1)
             : Theme.transparent
        Rectangle {
            anchors.fill: parent; anchors.margins: Theme.focusInset
            radius: Math.max(0, parent.radius - Theme.focusInset)
            color: Theme.transparent
            border.width: root.visualFocus ? Theme.focusWidth : 0
            border.color: root.accent
        }
        Rectangle {
            visible: root.checked
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(14, parent.width - 8); height: 2; radius: 1
            color: root.accent
        }
    }
    contentItem: Text {
        id: label
        text: root.text
        textFormat: Text.PlainText
        font.family: Theme.dataFont
        font.pixelSize: root.iconOnly ? 16 : Theme.small
        font.weight: Font.Medium
        color: !root.enabled ? Theme.muted : root.checked || root.down ? root.accent : Theme.text
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    Accessible.name: hint || text
    ToolTip.visible: hovered && hint !== ""
    ToolTip.text: hint
    ToolTip.delay: 600
}
