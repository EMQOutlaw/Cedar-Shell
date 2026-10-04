import QtQuick
import ".."
import "../services"

BarButton {
    id: root
    property string outputName: ""
    objectName: "coreNetwork"
    enabled: !ShellState.locked
    iconOnly: true
    implicitWidth: Network.vpnActive ? 46 : 32
    text: Theme.availableFonts.includes("JetBrainsMono Nerd Font") ? Network.glyph : Network.fallbackGlyph
    hint: Network.statusDescription + " · Open Connections"
    accent: Network.state === "connected" ? Theme.teal : Theme.muted
    onClicked: {
        if (Config.saved.canopyEnabled)
            Canopy.open("network", outputName);
        else {
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
