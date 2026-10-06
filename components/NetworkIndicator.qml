import QtQuick
import Quickshell
import ".."
import "../services"

BarButton {
    id: root
    property string outputName: ""
    // In a bar row the notice label takes its own space; beside Core it overflows
    // to the right so the pill never shifts.
    property bool inline: false
    objectName: "coreNetwork"
    enabled: !ShellState.locked
    iconOnly: true
    readonly property var notice: Network.notice
    readonly property bool noticing: !!notice
    readonly property color tone: notice?.tone === "lost" ? Theme.amber : Theme.teal
    implicitWidth: (Network.vpnActive ? 46 : 32) + (inline && noticeLabel.reveal > 0 ? Math.round(noticeLabel.width + 8) : 0)
    text: Theme.availableFonts.includes("JetBrainsMono Nerd Font") ? Network.glyph : Network.fallbackGlyph
    hint: (noticing && notice.detail ? notice.title + " · " + notice.detail + " · " : "") + Network.statusDescription + " · Open Connections"
    accent: noticing ? tone : Network.state === "connected" ? Theme.teal : Theme.muted
    checked: Canopy.shown && Canopy.topic === "network" && !Canopy.peeking
    // Screen x of the glyph's centre, so the Connections panel descends from it.
    // Works for a centred Core window and a full-width bar alike.
    function anchorX() {
        const win = root.QsWindow.window;
        if (!win || !win.screen)
            return -1;
        const p = root.mapToItem(null, (Network.vpnActive ? 46 : 32) / 2, 0);
        return (win.screen.width - win.width) / 2 + p.x;
    }
    readonly property string anchorOutput: outputName || CoreService.hostName
    function publishAnchor() { Canopy.setAnchorProvider("network", anchorOutput, visible ? root.anchorX : null); }
    Component.onCompleted: publishAnchor()
    Component.onDestruction: Canopy.setAnchorProvider("network", anchorOutput, null)
    onVisibleChanged: publishAnchor()
    onAnchorOutputChanged: publishAnchor()
    onNoticeChanged: {
        if (!notice)
            return;
        // Title only beside the glyph; the detail rides in the tooltip.
        noticeLabel.shown = notice.title;
        if (!Theme.reducedMotion)
            pulse.restart();
    }
    // One short pulse of the glyph when a notice lands.
    SequentialAnimation {
        id: pulse
        NumberAnimation { target: root.contentItem; property: "scale"; to: 1.3; duration: 120; easing.type: Easing.OutCubic }
        NumberAnimation { target: root.contentItem; property: "scale"; to: 1; duration: 260; easing.type: Easing.OutBack }
    }
    GlowText {
        id: noticeLabel
        objectName: "coreNetworkNotice"
        // Keeps its last text while fading out.
        property string shown: ""
        property real reveal: root.noticing ? 1 : 0
        Behavior on reveal { enabled: !Theme.reducedMotion; NumberAnimation { duration: root.noticing ? 220 : 160; easing.type: Easing.OutCubic } }
        visible: reveal > 0
        opacity: reveal
        x: (Network.vpnActive ? 46 : 32) + 2 + (1 - reveal) * -6
        anchors.verticalCenter: parent.verticalCenter
        text: shown
        font.family: Theme.dataFont
        font.pixelSize: Theme.small
        color: root.tone
        width: Math.min(implicitWidth, 150)
        elide: Text.ElideRight
        Accessible.role: Accessible.StaticText
        Accessible.name: shown
    }
    onClicked: {
        if (Config.saved.canopyEnabled) {
            if (checked)
                Canopy.close();
            else
                Canopy.open("network", outputName);
        } else {
            ShellState.settingsPage = "connections";
            ShellState.open("settings");
        }
    }
    contentItem: GlowText {
        text: root.text
        font.family: Theme.resolveFont("JetBrainsMono Nerd Font", "monospace")
        font.pixelSize: 16
        color: root.accent
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
    // Separate VPN mark; a tunnel never substitutes for the link-type icon.
    GlowText {
        visible: Network.vpnActive
        text: "V"
        font.pixelSize: 8
        color: Theme.teal
        anchors.right: parent.right
        anchors.rightMargin: 2
        anchors.top: parent.top
        Accessible.name: "VPN active"
    }
}
