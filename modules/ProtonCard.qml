import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../services"

// A small Proton VPN instrument for the Connections drop: where the tunnel
// leaves, one-press connect and disconnect, a country picker and the two
// protections worth a switch. Everything goes through Proton's own CLI.
// The CLI does not report the account's plan, so nothing is hidden by plan:
// Proton refuses what the plan lacks and the card shows its reason.
// Proton and Tailscale never run together (see services/Tailscale.qml): while
// Tailscale is up the connect buttons wait and the card says why.
ColumnLayout {
    id: root
    property bool picking: false
    property string filter: ""
    readonly property var status: Proton.data.status
    // Tailscale holds the tunnel; Proton waits.
    readonly property bool blocked: Tailscale.up && !Proton.connected
    readonly property bool canConnect: !Proton.busy && !blocked
    readonly property var matches: Proton.countries.filter(c => !filter || c.name.toLowerCase().includes(filter.toLowerCase()) || c.code.toLowerCase() === filter.toLowerCase()).slice(0, 18)
    spacing: 6
    function go(country) { Proton.connectTo("country", country.code, country.name); picking = false; }

    RowLayout {
        Layout.fillWidth: true; spacing: 8
        SectionMark { text: "PROTON VPN"; tone: Theme.strataAccent }
        Item { Layout.fillWidth: true }
        GlowText {
            visible: Proton.data.signedIn && Proton.data.plan !== ""
            text: Proton.data.plan.toUpperCase()
            font.pixelSize: 9; font.letterSpacing: 1.2; color: Theme.strataMuted
        }
    }

    // Not installed, or the GTK app in the way: one line and one way forward.
    RowLayout {
        visible: Proton.probed && !Proton.data.installed
        Layout.fillWidth: true; spacing: 8
        GlowText { text: "Proton's VPN command-line app is not installed."; font.pixelSize: Theme.small; color: Theme.strataMuted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
        StrataButton { text: "Install"; implicitHeight: 28; onClicked: Proton.install() }
    }
    GlowText {
        visible: Proton.data.conflict
        text: "Proton's desktop app is also installed. It and the CLI refuse to run together; quit or remove the app."
        font.pixelSize: 10; color: Theme.amber; Layout.fillWidth: true; wrapMode: Text.WordWrap
    }
    RowLayout {
        visible: Proton.data.installed && !Proton.data.signedIn && !Proton.connected
        Layout.fillWidth: true; spacing: 8
        GlowText { text: Proton.loading && !Proton.probed ? "Checking…" : "Signed out. Proton asks for the password in its own prompt."; font.pixelSize: Theme.small; color: Theme.strataMuted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
        StrataButton { text: "Sign in"; implicitHeight: 28; enabled: !Proton.loading; onClicked: Proton.signIn() }
    }

    // The tunnel: state, exit server and where it is.
    ColumnLayout {
        visible: Proton.data.installed && (Proton.data.signedIn || Proton.connected)
        Layout.fillWidth: true; spacing: 6
        RowLayout {
            Layout.fillWidth: true; spacing: 10
            Rectangle {
                width: 8; height: 8; radius: 4
                color: Proton.connected ? Theme.strataAccent : Proton.busy ? Theme.amber : Theme.strataMuted
                SequentialAnimation on opacity {
                    running: Proton.busy; loops: Animation.Infinite
                    alwaysRunToEnd: true
                    NumberAnimation { to: .3; duration: VisualQuality.ms(500) }
                    NumberAnimation { to: 1; duration: VisualQuality.ms(500) }
                }
            }
            ColumnLayout {
                Layout.fillWidth: true; spacing: 1
                GlowText {
                    text: Proton.busy ? Proton.working : Proton.connected ? "Protected · " + Proton.server : "Not connected"
                    color: Proton.connected ? Theme.strataAccent : Theme.strataText
                    Layout.fillWidth: true; elide: Text.ElideRight
                }
                GlowText {
                    visible: text !== ""
                    text: Proton.connected ? [root.status.location, root.status.load ? "load " + root.status.load : "", root.status.protocol].filter(Boolean).join(" · ")
                        : Proton.data.account ? "Signed in as " + Proton.data.account : ""
                    font.pixelSize: 10; color: Theme.strataMuted; Layout.fillWidth: true; elide: Text.ElideRight
                }
            }
            StrataButton {
                text: Proton.connected ? "Disconnect" : "Quick connect"
                implicitHeight: 28
                enabled: Proton.connected ? !Proton.busy : root.canConnect
                onClicked: Proton.connected ? Proton.disconnect() : Proton.connectTo("fastest")
            }
        }
        Flow {
            visible: Proton.data.signedIn
            Layout.fillWidth: true; spacing: 6
            StrataButton { text: "Country"; implicitHeight: 26; checked: root.picking; enabled: root.canConnect; onClicked: { root.picking = !root.picking; root.filter = ""; } }
            StrataButton { text: "P2P"; implicitHeight: 26; enabled: root.canConnect; onClicked: Proton.connectTo("p2p") }
            StrataButton { text: "Secure Core"; implicitHeight: 26; enabled: root.canConnect; onClicked: Proton.connectTo("securecore") }
            StrataButton { text: Proton.loading ? "…" : "Refresh"; implicitHeight: 26; enabled: !Proton.loading; onClicked: Proton.refresh() }
        }

        // Country picker: type to narrow, press a country to go there.
        ColumnLayout {
            visible: root.picking && Proton.data.signedIn
            Layout.fillWidth: true; spacing: 6
            StrataField {
                id: search
                objectName: "protonCountry"
                Layout.fillWidth: true
                placeholderText: Proton.countries.length ? "Search " + Proton.countries.length + " countries" : "Loading countries…"
                onTextChanged: root.filter = text.trim()
                onAccepted: if (root.matches.length && root.canConnect) root.go(root.matches[0])
                onVisibleChanged: { text = ""; if (visible) forceActiveFocus(); }
            }
            Flow {
                Layout.fillWidth: true; spacing: 6
                Repeater {
                    model: root.matches
                    StrataButton {
                        required property var modelData
                        text: modelData.code + "  " + modelData.name
                        implicitHeight: 26
                        enabled: root.canConnect
                        onClicked: root.go(modelData)
                    }
                }
            }
        }

        StationToggle {
            visible: Proton.data.signedIn
            accent: Theme.strataAccent; focusAccent: Theme.strataAccent
            Layout.fillWidth: true
            label: "Kill switch"
            description: "Block traffic if the tunnel drops"
            checked: Proton.killSwitch
            busy: Proton.busy
            onToggled: value => Proton.setOption("kill-switch", value ? "standard" : "off")
        }
        StationToggle {
            visible: Proton.data.signedIn
            accent: Theme.strataAccent; focusAccent: Theme.strataAccent
            Layout.fillWidth: true
            label: "NetShield"
            description: Proton.data.config.netshield === "malware-only" ? "Blocking malware domains" : "Block malware, ads and trackers"
            checked: Proton.netShield
            busy: Proton.busy
            onToggled: value => Proton.setOption("netshield", value ? "malware-ads-trackers" : "off")
        }
    }
    RowLayout {
        visible: root.blocked && Proton.data.installed && (Proton.data.signedIn || Proton.connected)
        Layout.fillWidth: true; spacing: 8
        GlowText {
            text: "Tailscale is up. Proton waits while it is: the two claim the same routes, and Proton's kill switch would cut the tailnet."
            font.pixelSize: 10; color: Theme.amber; Layout.fillWidth: true; wrapMode: Text.WordWrap
        }
        StrataButton { text: "Tailscale down"; implicitHeight: 28; enabled: !Tailscale.busy; onClicked: Tailscale.bringDown() }
    }
    GlowText {
        visible: Proton.error !== ""
        text: Proton.error
        color: Theme.amber; font.pixelSize: 10
        Layout.fillWidth: true; wrapMode: Text.WordWrap
    }
}
