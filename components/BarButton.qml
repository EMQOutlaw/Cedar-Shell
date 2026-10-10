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
    // Quiet at rest: muted until hovered, pressed or checked. The bar's
    // secondary controls and the workspace row use it, so the wordmark, the
    // pill and the gliding mark carry the eye.
    property bool quiet: false
    property string fontFamily: Theme.dataFont
    property int fontSize: iconOnly ? 16 : Theme.small
    property real letterSpacing: 0
    property string hint: ""
    property string canopyTopic: ""
    property string canopyOutput: ""
    // A control with a Canopy topic registers where that panel descends from:
    // the screen x of its centre, for a full-width bar or a centred window alike.
    property bool anchorsCanopy: true
    // The topic whose panel grows out of this control; defaults to the peek topic.
    property string anchorTopic: canopyTopic
    // A button in a row that shares one gliding mark draws no mark of its own.
    property bool glide: false
    readonly property string anchorOutput: canopyOutput || CoreService.hostName
    function anchorRect() {
        const win = root.QsWindow.window;
        if (!win || !win.screen)
            return null;
        const p = root.mapToItem(null, 0, 0);
        return { x: (win.screen.width - win.width) / 2 + p.x, width: root.width };
    }
    function publishAnchor() {
        if (!anchorTopic)
            return;
        if (visible && anchorsCanopy)
            Canopy.setAnchorProvider(anchorTopic, anchorOutput, root.anchorRect);
        else
            Canopy.clearAnchorProvider(anchorTopic, anchorOutput, root.anchorRect);
    }
    Component.onCompleted: publishAnchor()
    Component.onDestruction: if (anchorTopic) Canopy.clearAnchorProvider(anchorTopic, anchorOutput, root.anchorRect)
    onVisibleChanged: publishAnchor()
    onAnchorTopicChanged: publishAnchor()
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
    // The control its panel grows from brightens as the surface unfolds, then settles to checked.
    readonly property bool unfolding: anchorTopic !== "" && Canopy.shown && Canopy.topic === anchorTopic && Canopy.surfaceState === "opening"
    background: Rectangle {
        radius: 5
        color: root.unfolding ? Qt.alpha(root.accent, 0.34)
             : root.down ? Qt.alpha(root.accent, 0.18)
             : root.checked && !root.glide ? Qt.alpha(root.accent, 0.1)
             : root.hovered ? Qt.alpha(root.accent, 0.06)
             : Theme.transparent
        Behavior on color { enabled: VisualQuality.effects; ColorAnimation { duration: VisualQuality.ms(Theme.hover) } }
        Rectangle {
            anchors.fill: parent; anchors.margins: Theme.focusInset
            radius: Math.max(0, parent.radius - Theme.focusInset)
            color: Theme.transparent
            border.width: root.visualFocus ? Theme.focusWidth : 0
            border.color: root.accent
        }
        Rectangle {
            visible: root.checked && !root.glide
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
        font.family: root.fontFamily
        font.pixelSize: root.fontSize
        font.letterSpacing: root.letterSpacing
        font.weight: Font.Medium
        // In a gliding row the shared mark carries the accent; the active label stays plain.
        color: !root.enabled ? Theme.muted : root.checked || root.down ? (root.glide ? Theme.text : root.accent) : root.quiet && !root.hovered ? Theme.muted : Theme.text
        Behavior on color { enabled: VisualQuality.effects; ColorAnimation { duration: VisualQuality.ms(Theme.hover) } }
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    Accessible.name: hint || text
    ToolTip.visible: hovered && hint !== ""
    ToolTip.text: hint
    ToolTip.delay: 600
}
