import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../services"

// Shield: one dominant object, the CEDAR shield, and a card per protection.
// Wide: shield left, cards right. Normal: shield and headline above a
// two-column grid. Narrow: one column. Every card shows the provider's real
// state; a control enters a working state, the provider verifies, and only
// then does the card say so. Failures stay on the card with their reason.
ColumnLayout {
    id: root
    property bool active: false
    property string highlightKey: ""
    readonly property bool wide: width >= 980
    readonly property int columns: width < 620 ? 1 : 2
    property string dnsProvider: Shield.dns && Shield.dns.provider in ({cloudflare: 1, quad9: 1, mullvad: 1}) ? Shield.dns.provider : "cloudflare"
    spacing: 16
    onActiveChanged: if (active) Shield.refresh()

    // Headline with the shield.
    GridLayout {
        Layout.fillWidth: true
        columns: root.wide ? 2 : 1
        columnSpacing: 24; rowSpacing: 12
        ShieldMark { Layout.alignment: Qt.AlignHCenter | Qt.AlignTop; Layout.rowSpan: root.wide ? 2 : 1; compact: !root.wide }
        ColumnLayout {
            Layout.fillWidth: true; Layout.alignment: Qt.AlignTop
            spacing: 6
            RowLayout {
                Layout.fillWidth: true
                SectionMark { text: "SHIELD" }
                Item { Layout.fillWidth: true }
                StatusPill { text: Shield.ready ? Shield.onCount + " / " + Shield.protections.length + " active" : "Reading"; tone: Shield.offCount ? Theme.amber : Theme.green }
                StationButton { text: Shield.busy ? "Checking…" : "Check again"; enabled: !Shield.busy; onClicked: Shield.refresh() }
            }
            GlowText { text: Shield.headline; font.family: Theme.labelFont; font.pixelSize: Math.round(24 * Theme.fontScale); font.weight: Font.DemiBold; color: Theme.text; Layout.fillWidth: true; wrapMode: Text.WordWrap }
            GlowText { text: "Read from the services that own each protection: the firewall manager, systemd-resolved behind NetworkManager, your Wi-Fi profile and the kernel's socket tables. Changes go through those services and are verified before the card says so."; font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
            GlowText { visible: Shield.error !== ""; text: Shield.error; color: Theme.ember; Layout.fillWidth: true; wrapMode: Text.WordWrap }
        }
        // Cards sit beside the shield when wide, below it otherwise.
        GridLayout {
            Layout.fillWidth: true; Layout.columnSpan: root.wide ? 1 : 1
            columns: root.columns; columnSpacing: 12; rowSpacing: 12
            uniformCellWidths: true

            // Firewall
            ProtectionCard {
                id: firewallCard
                Layout.fillWidth: true; Layout.alignment: Qt.AlignTop
                readonly property var p: Shield.protections[0]
                label: p.label; state: p.state; value: p.value; detail: p.detail; reason: p.reason
                StationToggle {
                    Layout.fillWidth: true
                    label: Shield.firewallOn ? "Firewall on" : "Turn the firewall on"
                    description: Shield.firewall && Shield.firewall.available ? "Uses " + (Shield.firewallManager || "the installed manager") + "'s own enable command through pkexec; you will be asked for permission." : "Install ufw, firewalld or nftables, then check again."
                    checked: Shield.firewallOn
                    busy: Shield.working === "firewall"
                    enabled: !Shield.busy && !!Shield.firewall && Shield.firewall.available && Capabilities.canElevate
                    onToggled: Shield.setFirewall(!Shield.firewallOn)
                }
                GlowText { visible: Capabilities.ready && !Capabilities.canElevate; text: Capabilities.privilege.helper === "pkexec" ? "No authentication agent is running, so permission cannot be asked for from here." : "pkexec is not installed, so the firewall cannot be changed from here."; color: Theme.amber; font.pixelSize: Theme.small; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                ExpandableDetails {
                    Layout.fillWidth: true
                    Repeater {
                        model: Shield.firewall ? Shield.firewall.providers : []
                        GlowText { required property var modelData; text: modelData.provider + " · " + (modelData.active ? "running" : "stopped") + " · " + (modelData.enabled ? "starts at boot" : "not at boot") + (modelData.configured ? " · configured" : ""); font.pixelSize: Theme.small; color: Theme.muted }
                    }
                    GlowText { visible: !Shield.firewall || !Shield.firewall.providers.length; text: "No firewall manager found."; font.pixelSize: Theme.small; color: Theme.muted }
                }
            }

            // Encrypted DNS
            ProtectionCard {
                Layout.fillWidth: true; Layout.alignment: Qt.AlignTop
                readonly property var p: Shield.protections[1]
                label: p.label; state: p.state; value: p.value; detail: p.detail; reason: p.reason
                GlowText { visible: Shield.dnsSupported; text: "Provider"; font.pixelSize: 10; font.letterSpacing: 1.2; color: Theme.muted }
                RowLayout {
                    visible: Shield.dnsSupported
                    Layout.fillWidth: true; spacing: 6
                    Repeater {
                        model: [["cloudflare", "Cloudflare"], ["quad9", "Quad9"], ["mullvad", "Mullvad"]]
                        StationButton { required property var modelData; text: modelData[1]; checked: root.dnsProvider === modelData[0]; enabled: !Shield.busy; onClicked: root.dnsProvider = modelData[0] }
                    }
                }
                RowLayout {
                    visible: Shield.dnsSupported
                    Layout.fillWidth: true; spacing: 6
                    StationButton { text: "Strict"; hint: "DNS-over-TLS only; never falls back to plain DNS"; checked: Shield.dns && Shield.dns.mode === "strict"; enabled: !Shield.busy; onClicked: Shield.setDns("strict", root.dnsProvider) }
                    StationButton { text: "Opportunistic"; hint: "Tries TLS first, falls back when it fails"; checked: Shield.dns && Shield.dns.mode === "opportunistic"; enabled: !Shield.busy; onClicked: Shield.setDns("opportunistic", root.dnsProvider) }
                    StationButton { text: "Off"; hint: "Back to the network's own DNS"; checked: Shield.dns && Shield.dns.mode === "off"; enabled: !Shield.busy; onClicked: Shield.setDns("off", root.dnsProvider) }
                }
                ExpandableDetails {
                    Layout.fillWidth: true
                    label: Shield.dnsSupported ? "Details" : "Learn why"
                    GlowText { text: Shield.dns ? "Resolver: " + Shield.dns.resolver + (Shield.dns.link ? " · link " + Shield.dns.link : "") : ""; font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                    GlowText { text: Shield.dns && Shield.dns.servers.length ? "Servers: " + Shield.dns.servers.join("  ") : "No DNS servers reported for the default route."; font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                    GlowText { text: Shield.dns && Shield.dns.connection ? "Connection: " + Shield.dns.connection.name + " · dns-over-tls " + Shield.dns.connection.dnsOverTls + " · ignore-auto-dns " + Shield.dns.connection.ignoreAutoDns : (Shield.dns ? Shield.dns.reason : ""); font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                    GlowText { text: "DNS-over-HTTPS is not offered: neither systemd-resolved nor NetworkManager speaks it, so plain DNS is never labelled DoH here."; font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                }
            }

            // Private Wi-Fi address
            ProtectionCard {
                Layout.fillWidth: true; Layout.alignment: Qt.AlignTop
                readonly property var p: Shield.protections[2]
                label: p.label; state: p.state; value: p.value; detail: p.detail; reason: p.reason
                GridLayout {
                    visible: !!Shield.wifi && Shield.wifi.available && !!Shield.wifi.connection
                    Layout.fillWidth: true; columns: 2; columnSpacing: 6; rowSpacing: 6
                    Repeater {
                        model: [["stable", "Stable private", "One private address, kept for this network"], ["random", "Randomized", "A different private address as NetworkManager allows"], ["hardware", "Hardware", "The physical interface address"], ["default", "System default", "Whatever NetworkManager's default is"]]
                        StationButton { required property var modelData; Layout.fillWidth: true; text: modelData[1]; hint: modelData[2]; checked: Shield.wifiPolicy === modelData[0]; enabled: !Shield.busy; onClicked: Shield.setWifiPolicy(modelData[0]) }
                    }
                }
                GlowText { visible: !!Shield.wifi && Shield.wifi.available && !!Shield.wifi.connected; text: "A new policy applies the next time this network connects."; font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
            }

            // Local exposure
            ProtectionCard {
                Layout.fillWidth: true; Layout.alignment: Qt.AlignTop
                readonly property var p: Shield.protections[3]
                label: p.label; state: p.state; value: p.value; detail: p.detail; reason: p.reason
                RowLayout {
                    Layout.fillWidth: true
                    StationButton { text: Shield.busy && Shield.working === "" ? "Scanning…" : "Scan again"; enabled: !Shield.busy; onClicked: Shield.rescan() }
                    Item { Layout.fillWidth: true }
                    GlowText { visible: Shield.scannedAt > 0; text: "Scanned " + Qt.formatTime(new Date(Shield.scannedAt), Config.clock24 ? "HH:mm" : "h:mm ap"); font.pixelSize: Theme.small; color: Theme.muted }
                }
                ExpandableDetails {
                    Layout.fillWidth: true
                    label: "Listeners"
                    Repeater {
                        model: Shield.exposure ? Shield.exposure.listeners.filter(l => l.scope !== "local").slice(0, 40) : []
                        GlowText { required property var modelData; text: modelData.proto.toUpperCase() + " " + modelData.port + " on " + modelData.bind + (modelData.process ? " · " + modelData.process : "") + (modelData.scope === "all" ? " · every interface" : " · this network"); font.pixelSize: Theme.small; color: modelData.scope === "all" ? Theme.amber : Theme.muted; Layout.fillWidth: true; elide: Text.ElideRight }
                    }
                    GlowText { visible: !Shield.exposure || !Shield.exposure.exposed; text: "Nothing listens beyond this computer."; font.pixelSize: Theme.small; color: Theme.muted }
                    GlowText { visible: !!Shield.exposure && Shield.exposure.local > 0; text: Shield.exposure ? Shield.exposure.local + " more listen on localhost only, which other machines cannot reach." : ""; font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                }
            }

            // VPN, lock privacy, local-only: read-only here; their switches live on their own pages.
            Repeater {
                model: [4, 5, 6]
                ProtectionCard {
                    required property int modelData
                    readonly property var p: Shield.protections[modelData]
                    Layout.fillWidth: true; Layout.alignment: Qt.AlignTop
                    label: p.label; state: p.state; value: p.value; detail: p.detail; reason: p.reason
                }
            }
        }
    }
}
