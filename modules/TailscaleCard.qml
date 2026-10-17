import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../services"

// Tailscale in the Connections drop, shown only where its CLI is installed:
// the tailnet, this machine's name and address, how many peers are reachable
// and one press up or down. Tailscale and Proton VPN never run together (see
// services/Tailscale.qml): Up waits while Proton is connected, and the card
// says why rather than letting the two fight over routes.
ColumnLayout {
    id: root
    readonly property var status: Tailscale.data.status
    // Proton holds the tunnel; Tailscale waits.
    readonly property bool blocked: Proton.connected && !Tailscale.up
    // Both up at once, brought there outside CEDAR: say so, let the user pick which goes down.
    readonly property bool overlapping: Proton.connected && Tailscale.up
    visible: Tailscale.installed
    spacing: 6

    RowLayout {
        Layout.fillWidth: true; spacing: 8
        SectionMark { text: "TAILSCALE"; tone: Theme.strataAccent }
        Item { Layout.fillWidth: true }
        GlowText {
            visible: root.status.tailnet !== ""
            text: root.status.tailnet.toUpperCase()
            font.pixelSize: 9; font.letterSpacing: 1.2; color: Theme.strataMuted
            elide: Text.ElideRight; Layout.maximumWidth: 180
        }
    }

    // tailscaled not answering: one line and one way forward.
    RowLayout {
        visible: Tailscale.probed && !Tailscale.data.running
        Layout.fillWidth: true; spacing: 8
        GlowText { text: "Tailscale's service is not running."; font.pixelSize: Theme.small; color: Theme.strataMuted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
        StrataButton { text: "Start"; implicitHeight: 28; onClicked: Tailscale.startService() }
    }

    RowLayout {
        visible: !Tailscale.probed || Tailscale.data.running
        Layout.fillWidth: true; spacing: 10
        Rectangle {
            width: 8; height: 8; radius: 4
            color: Tailscale.up ? Theme.strataAccent : Tailscale.busy ? Theme.amber : Theme.strataMuted
            SequentialAnimation on opacity {
                running: Tailscale.busy; loops: Animation.Infinite
                alwaysRunToEnd: true
                NumberAnimation { to: .3; duration: VisualQuality.ms(500) }
                NumberAnimation { to: 1; duration: VisualQuality.ms(500) }
            }
        }
        ColumnLayout {
            Layout.fillWidth: true; spacing: 1
            GlowText {
                text: Tailscale.busy ? Tailscale.working
                    : !Tailscale.probed ? "Checking…"
                    : Tailscale.needsLogin ? "Signed out"
                    : Tailscale.up ? "Up · " + (root.status.hostname || "this machine")
                    : "Down"
                color: Tailscale.up ? Theme.strataAccent : Theme.strataText
                Layout.fillWidth: true; elide: Text.ElideRight
            }
            GlowText {
                visible: text !== ""
                text: Tailscale.up ? [root.status.ip, root.status.peers ? root.status.peersOnline + " of " + root.status.peers + " peers online" : "", root.status.exitNode ? "exit node " + root.status.exitNode : ""].filter(Boolean).join(" · ")
                    : Tailscale.needsLogin ? "Tailscale asks for the login in its own link."
                    : Tailscale.probed ? "Your other machines are out of reach until it is up." : ""
                font.pixelSize: 10; color: Theme.strataMuted; Layout.fillWidth: true; elide: Text.ElideRight
            }
        }
        StrataButton {
            text: Tailscale.needsLogin ? "Sign in" : Tailscale.up ? "Down" : "Up"
            implicitHeight: 28
            enabled: !Tailscale.busy && Tailscale.probed && !root.blocked
            onClicked: Tailscale.needsLogin ? Tailscale.signIn() : Tailscale.up ? Tailscale.bringDown() : Tailscale.bringUp()
        }
    }
    RowLayout {
        visible: root.blocked
        Layout.fillWidth: true; spacing: 8
        GlowText {
            text: "Proton VPN is connected. Tailscale stays down while it is: the two claim the same routes, and Proton's kill switch cuts the tailnet."
            font.pixelSize: 10; color: Theme.amber; Layout.fillWidth: true; wrapMode: Text.WordWrap
        }
        StrataButton { text: "Disconnect Proton"; implicitHeight: 28; enabled: !Proton.busy; onClicked: Proton.disconnect() }
    }
    GlowText {
        visible: root.overlapping
        text: "Proton VPN is connected too. Running both tangles routes and DNS; bring one of them down."
        font.pixelSize: 10; color: Theme.amber; Layout.fillWidth: true; wrapMode: Text.WordWrap
    }
    GlowText {
        visible: Tailscale.error !== "" && (!Tailscale.probed || Tailscale.data.running)
        text: Tailscale.error
        color: Theme.amber; font.pixelSize: 10
        Layout.fillWidth: true; wrapMode: Text.WordWrap
    }
}
