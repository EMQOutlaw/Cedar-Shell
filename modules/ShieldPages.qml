import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import ".."
import "../components"
import "../services"

// The Shield application's content: navigation and five pages. Overview
// answers "how protected am I" in two seconds; Protections, Network,
// Activity and Settings sit one level deeper. Depth: the window is level 0,
// the panels level 1, the cards level 2.
FocusScope {
    id: root
    signal closed()
    property string page: "overview"
    property string detail: ""           // a protection id while a detail view is open
    readonly property bool sidebar: width >= 860
    readonly property int columns: width < 1180 && !sidebar ? (width < 640 ? 1 : 2) : width < 1180 ? 1 : 2
    readonly property var pages: [["overview", "Overview", "◇"], ["protections", "Protections", "⬡"], ["network", "Network", "⌁"], ["activity", "Activity", "◷"], ["settings", "Settings", "◈"]]
    function navigate(id) { page = id; detail = ""; }
    function tone(state) { return state === "on" ? Theme.success : state === "warn" ? Theme.warning : state === "fail" ? Theme.danger : state === "working" ? Theme.teal : Theme.inactive; }
    function word(state) { return ({ on: "Active", off: "Off", warn: "Check", fail: "Failed", unavailable: "Unavailable", working: "Working" })[state] || state; }
    function when(at) {
        const diff = Math.max(0, Date.now() - at), m = Math.floor(diff / 60000);
        return m < 1 ? "just now" : m < 60 ? m + " min ago" : m < 1440 ? Math.floor(m / 60) + " h ago" : Qt.formatDateTime(new Date(at), Config.clock24 ? "d MMM HH:mm" : "d MMM h:mm ap");
    }
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) { if (root.detail) root.detail = ""; else root.closed(); event.accepted = true; }
        else if (event.key === Qt.Key_W && event.modifiers & Qt.ControlModifier) { root.closed(); event.accepted = true; }
        else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_5 && event.modifiers & Qt.ControlModifier) { root.navigate(root.pages[event.key - Qt.Key_1][0]); event.accepted = true; }
    }

    // ------------------------------------------------------------ navigation
    component NavButton: StationButton {
        id: nav
        required property var modelData
        readonly property bool current: root.page === modelData[0]
        text: (root.sidebar ? modelData[2] + "   " : "") + modelData[1]
        checked: current
        accent: Theme.green
        implicitHeight: 34
        Layout.fillWidth: root.sidebar
        onClicked: root.navigate(modelData[0])
        Accessible.name: modelData[1] + (current ? ", current page" : "")
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0
        // Sidebar (level 1), only when wide.
        Rectangle {
            visible: root.sidebar
            Layout.fillHeight: true; Layout.preferredWidth: 200
            color: Theme.surface
            ColumnLayout {
                anchors { fill: parent; margins: 16 }
                spacing: 6
                RowLayout {
                    Layout.fillWidth: true; Layout.bottomMargin: 10
                    ShieldMark { compact: true; implicitWidth: 28; implicitHeight: 34; interactive: false }
                    GlowText { text: "SHIELD"; font.pixelSize: 11; font.letterSpacing: 2.2; color: Theme.teal }
                }
                Repeater { model: root.pages.slice(0, 4); NavButton {} }
                Item { Layout.fillHeight: true }
                Repeater { model: root.pages.slice(4); NavButton {} }
                GlowText { text: Branding.content.identity || ""; font.pixelSize: 9; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap; Layout.topMargin: 8 }
            }
        }
        ColumnLayout {
            Layout.fillWidth: true; Layout.fillHeight: true
            spacing: 0
            // Tab strip when narrow.
            RowLayout {
                visible: !root.sidebar
                Layout.fillWidth: true; Layout.margins: 12; spacing: 6
                Repeater { model: root.pages; NavButton {} }
            }
            Flickable {
                id: scroll
                Layout.fillWidth: true; Layout.fillHeight: true
                contentWidth: width; contentHeight: body.implicitHeight + 48
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: scroll.contentHeight > scroll.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }
                Loader {
                    id: body
                    x: 24; y: 24; width: scroll.width - 48
                    sourceComponent: root.detail ? detailPage : ({ overview: overview, protections: protections, network: network, activity: activity, settings: settings })[root.page] || overview
                }
            }
        }
    }

    // --------------------------------------------------------------- overview
    Component {
        id: overview
        ColumnLayout {
            spacing: 24
            RowLayout {
                Layout.fillWidth: true
                ColumnLayout {
                    spacing: 4; Layout.fillWidth: true
                    GlowText { text: "Shield"; font.family: Theme.labelFont; font.pixelSize: Math.round(30 * Theme.fontScale); font.weight: Font.DemiBold; color: Theme.text }
                    GlowText { text: Shield.posture === "protected" ? "Your system is protected." : Shield.posture === "attention" ? "Your system needs attention." : Shield.posture === "risk" ? "Your system is at risk." : "Reading your protections…"; font.pixelSize: Theme.normal; color: Theme.muted }
                }
                StatusPill { text: Shield.ready ? "Protection " + Math.round(100 * Shield.onCount / Math.max(1, Shield.countable)) + "%" : "Reading"; tone: root.tone(Shield.posture === "protected" ? "on" : Shield.posture === "attention" ? "warn" : Shield.posture === "risk" ? "fail" : "working") }
                StationButton { text: Shield.busy ? "Checking…" : "Check again"; enabled: !Shield.busy; onClicked: Shield.refresh() }
            }
            GridLayout {
                id: hero
                Layout.fillWidth: true
                readonly property bool wide: root.width >= 820
                columns: wide ? 2 : 1; columnSpacing: 24; rowSpacing: 24
                // The centrepiece (level 1): the shield, the posture, the count.
                Rectangle {
                    Layout.preferredWidth: hero.wide ? Math.round((hero.width - hero.columnSpacing) * .46) : hero.width
                    Layout.maximumWidth: Layout.preferredWidth
                    Layout.fillHeight: true
                    implicitHeight: 420
                    color: Theme.surface; radius: Theme.panelRadius
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 10
                        ShieldMark { Layout.alignment: Qt.AlignHCenter; implicitWidth: 220; implicitHeight: 260; revealOnShow: true }
                        GlowText { Layout.alignment: Qt.AlignHCenter; text: Shield.headline.toUpperCase(); font.family: Theme.labelFont; font.pixelSize: Math.round(22 * Theme.fontScale); font.weight: Font.DemiBold; font.letterSpacing: 2; color: root.tone(Shield.posture === "protected" ? "on" : Shield.posture === "attention" ? "warn" : Shield.posture === "risk" ? "fail" : "working") }
                        GlowText { Layout.alignment: Qt.AlignHCenter; text: Shield.subline; font.pixelSize: Theme.small; color: Theme.muted; horizontalAlignment: Text.AlignHCenter; Layout.maximumWidth: 280; wrapMode: Text.WordWrap }
                        GlowText { Layout.alignment: Qt.AlignHCenter; visible: Shield.ready; text: "Your current network is " + (Shield.publicNetwork ? "public" : "trusted") + "."; font.pixelSize: Theme.small; color: Theme.muted }
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true; Layout.alignment: Qt.AlignTop
                    Layout.preferredWidth: hero.wide ? hero.width - hero.columnSpacing - Math.round((hero.width - hero.columnSpacing) * .46) : hero.width
                    spacing: 16
                    // Important protections (level 1 panel, rows not cards).
                    Rectangle {
                        Layout.fillWidth: true; implicitHeight: important.implicitHeight + 36
                        color: Theme.surface; radius: Theme.panelRadius
                        ColumnLayout {
                            id: important
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 18 }
                            spacing: 8
                            SectionMark { text: "PROTECTIONS" }
                            Repeater {
                                model: ["firewall", "dns", "discovery", "wifi", "ipv6", "vpn"].map(id => Shield.protection(id)).filter(Boolean)
                                RowLayout {
                                    required property var modelData
                                    Layout.fillWidth: true; spacing: 10
                                    Rectangle { width: 8; height: 8; radius: 4; color: root.tone(modelData.state); opacity: modelData.state === "on" ? 1 : .55 }
                                    GlowText { text: modelData.label; color: Theme.text; Layout.fillWidth: true; elide: Text.ElideRight }
                                    GlowText { text: modelData.value; color: modelData.state === "on" ? Theme.success : Theme.muted; font.pixelSize: Theme.small; elide: Text.ElideRight; Layout.maximumWidth: 220; horizontalAlignment: Text.AlignRight }
                                }
                            }
                            StationButton { Layout.alignment: Qt.AlignRight; text: "View all protections →"; onClicked: root.navigate("protections") }
                        }
                    }
                    GridLayout {
                        Layout.fillWidth: true; columns: 2; columnSpacing: 12; rowSpacing: 12
                        // Network and exposure at a glance (level 2 cards).
                        ChamferFrame {
                            Layout.fillWidth: true; implicitHeight: 92; cut: 8; fill: Theme.elevated; stroke: Qt.alpha(Theme.teal, .18)
                            ColumnLayout { anchors { fill: parent; margins: 14 } spacing: 2
                                GlowText { text: "NETWORK"; font.pixelSize: 10; font.letterSpacing: 1.4; color: Theme.muted }
                                GlowText { text: Shield.publicNetwork ? "Public" : "Trusted"; font.family: Theme.labelFont; font.pixelSize: Math.round(18 * Theme.fontScale); font.weight: Font.DemiBold; color: Theme.text }
                                GlowText { text: Shield.networkLabel; font.pixelSize: Theme.small; color: Theme.muted; elide: Text.ElideRight; Layout.fillWidth: true } }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.navigate("network") }
                        }
                        ChamferFrame {
                            Layout.fillWidth: true; implicitHeight: 92; cut: 8; fill: Theme.elevated; stroke: Qt.alpha(Shield.exposedCount ? Theme.warning : Theme.teal, .25)
                            ColumnLayout { anchors { fill: parent; margins: 14 } spacing: 2
                                GlowText { text: "EXPOSURE"; font.pixelSize: 10; font.letterSpacing: 1.4; color: Theme.muted }
                                GlowText { text: Shield.exposure ? Shield.exposedCount + (Shield.exposedCount === 1 ? " service" : " services") : "Not scanned"; font.family: Theme.labelFont; font.pixelSize: Math.round(18 * Theme.fontScale); font.weight: Font.DemiBold; color: Theme.text }
                                GlowText { text: Shield.exposure ? (Shield.exposedCount ? "visible to your network" : "Everything stays local") : ""; font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; elide: Text.ElideRight } }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.navigate("network") }
                        }
                    }
                }
            }
            GlowText { visible: Shield.error !== ""; text: Shield.error; color: Theme.danger; Layout.fillWidth: true; wrapMode: Text.WordWrap }
            ColumnLayout {
                Layout.fillWidth: true; spacing: 8
                RowLayout { Layout.fillWidth: true; SectionMark { text: "RECENT ACTIVITY" } Item { Layout.fillWidth: true } StationButton { text: "All activity →"; visible: Shield.activity.length > 3; onClicked: root.navigate("activity") } }
                Repeater {
                    model: Shield.activity.slice(0, 3)
                    RowLayout {
                        required property var modelData
                        Layout.fillWidth: true; spacing: 10
                        Rectangle { width: 6; height: 6; radius: 3; color: modelData.kind === "failure" ? Theme.danger : modelData.kind === "on" ? Theme.success : Theme.teal }
                        GlowText { text: modelData.title; color: Theme.text; Layout.fillWidth: true; elide: Text.ElideRight }
                        GlowText { text: root.when(modelData.at); font.pixelSize: Theme.small; color: Theme.muted }
                    }
                }
                GlowText { visible: !Shield.activity.length; text: "Nothing observed yet. Shield records only what it sees: a protection changing, an action and its result, a network change."; font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
            }
        }
    }

    // ------------------------------------------------------------ protections
    Component {
        id: protections
        ColumnLayout {
            spacing: 20
            RowLayout { Layout.fillWidth: true
                ColumnLayout { spacing: 4; Layout.fillWidth: true
                    GlowText { text: "Protections"; font.family: Theme.labelFont; font.pixelSize: Math.round(26 * Theme.fontScale); font.weight: Font.DemiBold; color: Theme.text }
                    GlowText { text: Shield.onCount + " of " + Shield.countable + " active · open a card for its controls and technical details"; font.pixelSize: Theme.small; color: Theme.muted } }
                StationButton { text: Shield.busy ? "Checking…" : "Check again"; enabled: !Shield.busy; onClicked: Shield.refresh() } }
            Repeater {
                model: Shield.groups
                ColumnLayout {
                    required property string modelData
                    Layout.fillWidth: true; spacing: 10
                    SectionMark { text: modelData.toUpperCase() }
                    GridLayout {
                        Layout.fillWidth: true; columns: root.columns; columnSpacing: 12; rowSpacing: 12; uniformCellWidths: true
                        Repeater {
                            model: Shield.protections.filter(p => p.group === modelData)
                            ProtectionCard {
                                required property var modelData
                                Layout.fillWidth: true; Layout.alignment: Qt.AlignTop
                                label: modelData.label; state: modelData.state; value: modelData.value; detail: modelData.provider; reason: ""
                                interactive: true
                                onOpened: root.detail = modelData.id
                            }
                        }
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------- detail view
    Component {
        id: detailPage
        ColumnLayout {
            readonly property var p: Shield.protection(root.detail) || Shield.protections[0]
            readonly property string id: p.id
            spacing: 18
            StationButton { text: "← " + p.label; onClicked: root.detail = "" }
            Rectangle {
                Layout.fillWidth: true; implicitHeight: head.implicitHeight + 48; color: Theme.surface; radius: Theme.panelRadius
                ColumnLayout {
                    id: head
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 24 }
                    spacing: 8
                    ShieldMark { Layout.alignment: Qt.AlignHCenter; compact: true; implicitWidth: 64; implicitHeight: 76; highlight: id }
                    GlowText { Layout.alignment: Qt.AlignHCenter; text: root.word(p.state).toUpperCase(); font.family: Theme.labelFont; font.pixelSize: Math.round(22 * Theme.fontScale); font.weight: Font.DemiBold; font.letterSpacing: 2; color: root.tone(p.state) }
                    GlowText { Layout.alignment: Qt.AlignHCenter; text: p.value; font.pixelSize: Theme.normal; color: Theme.text }
                    GlowText { Layout.alignment: Qt.AlignHCenter; text: p.detail; font.pixelSize: Theme.small; color: Theme.muted; horizontalAlignment: Text.AlignHCenter; Layout.maximumWidth: 520; wrapMode: Text.WordWrap }
                    GlowText { Layout.alignment: Qt.AlignHCenter; visible: p.reason !== ""; text: p.reason; font.pixelSize: Theme.small; color: p.state === "fail" ? Theme.danger : Theme.warning; horizontalAlignment: Text.AlignHCenter; Layout.maximumWidth: 520; wrapMode: Text.WordWrap }
                }
            }
            // Controls: each one enters a working state, the provider verifies, then the card says so.
            Loader {
                Layout.fillWidth: true
                sourceComponent: ({ firewall: firewallControls, dns: dnsControls, wifi: wifiControls, ipv6: ipv6Controls, discovery: discoveryControls, exposure: exposureControls, lock: lockControls, idle: idleControls, local: localControls, clipboard: clipboardControls, trails: trailsControls })[id] || null
            }
            GlowText { visible: Shield.error !== ""; text: Shield.error; color: Theme.danger; Layout.fillWidth: true; wrapMode: Text.WordWrap }
            ExpandableDetails {
                Layout.fillWidth: true; label: "Technical details"
                Repeater {
                    model: root.technical(id)
                    RowLayout { required property var modelData; Layout.fillWidth: true
                        GlowText { text: modelData[0]; font.pixelSize: Theme.small; color: Theme.muted; Layout.preferredWidth: 160 }
                        GlowText { text: modelData[1]; font.pixelSize: Theme.small; color: Theme.text; Layout.fillWidth: true; wrapMode: Text.WrapAnywhere } }
                }
            }
        }
    }
    function technical(id) {
        const verified = Shield.data.verifiedAt ? ["Last verified", root.when(Shield.data.verifiedAt * 1000)] : null;
        const rows = ({
            firewall: Shield.firewall ? [["Provider", Shield.firewall.provider], ["Owner", Shield.firewall.owner], ["Unit", Shield.firewall.unit || "—"], ["Running", String(Shield.firewall.active)]].concat((Shield.firewall.providers || []).map(f => ["Installed", f.provider + " · " + (f.active ? "running" : "stopped") + (f.enabled ? " · at boot" : "") + (f.configured ? " · configured" : "")])) : [],
            dns: Shield.dns ? [["Resolver", Shield.dns.resolver], ["Link", Shield.dns.link || "—"], ["Servers", (Shield.dns.servers || []).join("  ") || "—"], ["Mode", Shield.dns.mode], ["Connection", Shield.dns.connection ? Shield.dns.connection.name + " · dns-over-tls " + Shield.dns.connection.dnsOverTls + " · ignore-auto-dns " + Shield.dns.connection.ignoreAutoDns : "—"], ["DNS-over-HTTPS", "not offered: neither resolved nor NetworkManager speaks it"]] : [],
            discovery: Shield.discovery ? [["Avahi", Shield.discovery.avahi ? "running" : "stopped"], ["resolved mDNS", String(Shield.discovery.mdns)], ["resolved LLMNR", String(Shield.discovery.llmnr)], ["Connection setting", "mdns " + Shield.discovery.setting.mdns + " · llmnr " + Shield.discovery.setting.llmnr]] : [],
            exposure: Shield.exposure ? [["Scanned", Shield.scannedAt ? root.when(Shield.scannedAt) : "—"], ["Localhost only", String(Shield.exposure.local)], ["This network", String(Shield.exposure.lan)], ["Every interface", String(Shield.exposure.all)]].concat(Shield.exposure.listeners.filter(l => l.scope !== "local").slice(0, 40).map(l => [l.proto.toUpperCase() + " " + l.port, l.bind + (l.process ? " · " + l.process : "") + (l.scope === "all" ? " · every interface" : " · this network")])) : [],
            wifi: Shield.wifi ? [["Device", Shield.wifi.device || "—"], ["Profile", Shield.wifi.connection || "—"], ["cloned-mac-address", Shield.wifi.raw || "(default)"]] : [],
            ipv6: Shield.ipv6 ? [["ipv6.ip6-privacy", Shield.ipv6.setting || "—"], ["Kernel use_tempaddr", Shield.ipv6.kernel || "—"], ["Effective", Shield.ipv6.effective || "—"]] : [],
            vpn: [["Active VPNs", String((Network.data.status?.vpns || []).map(v => v.name).join(", ") || "none")]],
            lock: [["Setting", "lockPrivacy = " + Config.saved.lockPrivacy]], idle: [["Setting", "idleLockSeconds = " + Config.idleLockSeconds]],
            local: [["Setting", "localOnly = " + Config.localOnly]], clipboard: [["Setting", "clipboardHistory = " + Config.saved.clipboardHistory]], trails: [["Setting", "forestTrails = " + Config.saved.forestTrails]]
        })[id] || [];
        return verified ? rows.concat([verified]) : rows;
    }
    Component { id: firewallControls; ColumnLayout { spacing: 8
        StationToggle { Layout.fillWidth: true; label: Shield.firewallOn ? "Firewall on" : "Turn the firewall on"; description: Shield.firewall && Shield.firewall.available ? "Uses " + (Shield.firewallManager || "the installed manager") + "'s own command through pkexec; you will be asked for permission." : "Install ufw, firewalld or nftables, then check again."; checked: Shield.firewallOn; busy: Shield.working === "firewall"; enabled: !Shield.busy && !!Shield.firewall && Shield.firewall.available && Capabilities.canElevate; onToggled: Shield.setFirewall(!Shield.firewallOn) }
        GlowText { visible: Capabilities.ready && !Capabilities.canElevate; text: Capabilities.privilege.helper === "pkexec" ? "No authentication agent is running, so permission cannot be asked for from here." : "pkexec is not installed, so the firewall cannot be changed from here."; color: Theme.warning; font.pixelSize: Theme.small; Layout.fillWidth: true; wrapMode: Text.WordWrap } } }
    Component { id: dnsControls; ColumnLayout { spacing: 8; visible: Shield.dnsSupported
        GlowText { text: "PROVIDER"; font.pixelSize: 10; font.letterSpacing: 1.4; color: Theme.muted }
        RowLayout { spacing: 6; Repeater { model: [["cloudflare", "Cloudflare"], ["quad9", "Quad9"], ["mullvad", "Mullvad"]]; StationButton { required property var modelData; text: modelData[1]; checked: Config.saved.shieldDnsProvider === modelData[0]; enabled: !Shield.busy; onClicked: Config.set("shieldDnsProvider", modelData[0]) } } }
        GlowText { text: "MODE"; font.pixelSize: 10; font.letterSpacing: 1.4; color: Theme.muted }
        RowLayout { spacing: 6
            StationButton { text: "Strict"; hint: "DNS-over-TLS only; never falls back to plain DNS"; checked: Shield.dns && Shield.dns.mode === "strict"; enabled: !Shield.busy; onClicked: Shield.setDns("strict") }
            StationButton { text: "Opportunistic"; hint: "Tries TLS first, falls back when it fails"; checked: Shield.dns && Shield.dns.mode === "opportunistic"; enabled: !Shield.busy; onClicked: Shield.setDns("opportunistic") }
            StationButton { text: "Off"; hint: "Back to the network's own DNS"; checked: Shield.dns && Shield.dns.mode === "off"; enabled: !Shield.busy; onClicked: Shield.setDns("off") } } } }
    Component { id: wifiControls; GridLayout { columns: 2; columnSpacing: 6; rowSpacing: 6; visible: !!Shield.wifi && Shield.wifi.available && !!Shield.wifi.connection
        Repeater { model: [["stable", "Stable private", "One private address, kept for this network"], ["random", "Randomized", "A different private address as NetworkManager allows"], ["hardware", "Hardware", "The physical interface address"], ["default", "System default", "Whatever NetworkManager's default is"]]
            StationButton { required property var modelData; Layout.fillWidth: true; text: modelData[1]; hint: modelData[2]; checked: Shield.wifiPolicy === modelData[0]; enabled: !Shield.busy; onClicked: Shield.setWifiPolicy(modelData[0]) } } } }
    Component { id: ipv6Controls; StationToggle { label: Shield.ipv6 && Shield.ipv6.active ? "Temporary addresses on" : "Use temporary addresses"; description: "NetworkManager's ipv6.ip6-privacy on the active connection, reapplied without dropping the link."; checked: !!Shield.ipv6 && Shield.ipv6.active; busy: Shield.working === "ipv6"; enabled: !Shield.busy && !!Shield.ipv6 && Shield.ipv6.available; onToggled: Shield.setIpv6(!(Shield.ipv6 && Shield.ipv6.active)) } }
    Component { id: discoveryControls; StationToggle { label: Shield.discovery && Shield.discovery.answering ? "Answering name queries" : "Not answering name queries"; description: "mDNS and LLMNR on the active connection through NetworkManager; Avahi is stopped through pkexec when it is running."; checked: !!Shield.discovery && Shield.discovery.answering; busy: Shield.working === "discovery"; enabled: !Shield.busy && !!Shield.discovery && Shield.discovery.available; onToggled: Shield.setDiscovery(!(Shield.discovery && Shield.discovery.answering)) } }
    Component { id: exposureControls; RowLayout { StationButton { text: Shield.busy ? "Scanning…" : "Scan again"; enabled: !Shield.busy; onClicked: Shield.rescan() } } }
    Component { id: lockControls; StationToggle { label: "Hide details while locked"; checked: Config.saved.lockPrivacy; onToggled: Config.set("lockPrivacy", !Config.saved.lockPrivacy) } }
    Component { id: idleControls; RowLayout { spacing: 6; Repeater { model: [[0, "Never"], [300, "5 min"], [600, "10 min"], [1800, "30 min"]]; StationButton { required property var modelData; text: modelData[1]; checked: Config.idleLockSeconds === modelData[0]; onClicked: Config.set("idleLockSeconds", modelData[0]) } } } }
    Component { id: localControls; StationToggle { label: "Local-only mode"; checked: Config.saved.localOnly; onToggled: Config.set("localOnly", !Config.saved.localOnly) } }
    Component { id: clipboardControls; StationToggle { label: "Keep clipboard history"; checked: Config.saved.clipboardHistory; onToggled: Config.set("clipboardHistory", !Config.saved.clipboardHistory) } }
    Component { id: trailsControls; StationToggle { label: "Record activity trails"; checked: Config.saved.forestTrails; onToggled: Config.set("forestTrails", !Config.saved.forestTrails) } }

    // ---------------------------------------------------------------- network
    Component {
        id: network
        ColumnLayout {
            spacing: 20
            GlowText { text: "Network"; font.family: Theme.labelFont; font.pixelSize: Math.round(26 * Theme.fontScale); font.weight: Font.DemiBold; color: Theme.text }
            Rectangle {
                Layout.fillWidth: true; implicitHeight: net.implicitHeight + 48; color: Theme.surface; radius: Theme.panelRadius
                ColumnLayout {
                    id: net
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 24 }
                    spacing: 10
                    GlowText { Layout.alignment: Qt.AlignHCenter; text: Shield.networkLabel; font.family: Theme.labelFont; font.pixelSize: Math.round(22 * Theme.fontScale); font.weight: Font.DemiBold; color: Theme.text }
                    GlowText { Layout.alignment: Qt.AlignHCenter; text: (Shield.publicNetwork ? "PUBLIC" : "TRUSTED") + (Shield.connection ? " · " + Shield.connection.type.replace("802-3-ethernet", "wired").replace("802-11-wireless", "Wi-Fi") : ""); font.pixelSize: 11; font.letterSpacing: 2; color: Shield.publicNetwork ? Theme.warning : Theme.success }
                    Repeater {
                        model: ["firewall", "dns", "discovery", "wifi", "vpn"].map(id => Shield.protection(id)).filter(Boolean)
                        RowLayout { required property var modelData; Layout.fillWidth: true; Layout.leftMargin: 24; Layout.rightMargin: 24
                            GlowText { text: modelData.label; color: Theme.muted; Layout.preferredWidth: 180 }
                            Rectangle { width: 8; height: 8; radius: 4; color: root.tone(modelData.state) }
                            GlowText { text: modelData.value; color: Theme.text; Layout.fillWidth: true; elide: Text.ElideRight } }
                    }
                }
            }
            ColumnLayout {
                spacing: 8
                SectionMark { text: "NETWORK PROFILE" }
                GlowText { text: "A public network recommends more: encrypted DNS, no discovery answers and temporary IPv6 addresses join the firewall and session protections. The profile is remembered for this connection."; font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                RowLayout { spacing: 8
                    StationButton { text: "Trusted"; checked: !Shield.publicNetwork; enabled: !!Shield.connectionKey; onClicked: Shield.setProfile("trusted") }
                    StationButton { text: "Public"; checked: Shield.publicNetwork; enabled: !!Shield.connectionKey; onClicked: Shield.setProfile("public") }
                    Item { Layout.fillWidth: true }
                    StationButton { visible: Shield.recommendedOff.length > 0; text: Shield.busy ? "Working…" : "Apply recommended (" + Shield.recommendedOff.length + ")"; accent: Theme.green; enabled: !Shield.busy; onClicked: Shield.applyRecommended() } }
                GlowText { visible: !Shield.connectionKey; text: "No active NetworkManager connection to attach a profile to."; font.pixelSize: Theme.small; color: Theme.muted }
            }
            ColumnLayout {
                spacing: 8
                SectionMark { text: "LOCAL EXPOSURE" }
                GlowText { text: Shield.exposure ? (Shield.exposure.all + (Shield.exposure.all === 1 ? " service answers" : " services answer") + " on every interface · " + Shield.exposure.lan + " on this network only · " + Shield.exposure.local + " on localhost") : "Not scanned yet."; color: Theme.text; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                RowLayout { StationButton { text: "View services →"; onClicked: root.detail = "exposure" } StationButton { text: Shield.busy ? "Scanning…" : "Scan again"; enabled: !Shield.busy; onClicked: Shield.rescan() } }
            }
        }
    }

    // --------------------------------------------------------------- activity
    Component {
        id: activity
        ColumnLayout {
            spacing: 14
            GlowText { text: "Activity"; font.family: Theme.labelFont; font.pixelSize: Math.round(26 * Theme.fontScale); font.weight: Font.DemiBold; color: Theme.text }
            GlowText { text: "Only what Shield observed: a protection changing between two reads, an action and its result, a network or profile change. No invented events."; font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
            Repeater {
                model: Shield.activity
                RowLayout {
                    required property var modelData
                    Layout.fillWidth: true; spacing: 12
                    Rectangle { width: 8; height: 8; radius: 4; color: modelData.kind === "failure" ? Theme.danger : modelData.kind === "on" ? Theme.success : modelData.kind === "network" || modelData.kind === "profile" ? Theme.teal : Theme.muted; Layout.alignment: Qt.AlignTop; Layout.topMargin: 6 }
                    ColumnLayout { Layout.fillWidth: true; spacing: 2
                        GlowText { text: modelData.title; color: Theme.text; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                        GlowText { visible: modelData.detail !== ""; text: modelData.detail; font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap } }
                    GlowText { text: root.when(modelData.at); font.pixelSize: Theme.small; color: Theme.muted; Layout.alignment: Qt.AlignTop }
                }
            }
            GlowText { visible: !Shield.activity.length; text: "Nothing observed yet."; color: Theme.muted }
        }
    }

    // --------------------------------------------------------------- settings
    Component {
        id: settings
        ColumnLayout {
            spacing: 14
            GlowText { text: "Settings"; font.family: Theme.labelFont; font.pixelSize: Math.round(26 * Theme.fontScale); font.weight: Font.DemiBold; color: Theme.text }
            StationToggle { Layout.fillWidth: true; label: "Reassess when the network changes"; description: "One fresh read after a network change, even while this window is closed, so the Quick Controls tile and the activity log stay true."; checked: Config.saved.shieldWatchNetwork; onToggled: Config.set("shieldWatchNetwork", !Config.saved.shieldWatchNetwork) }
            GlowText { text: "PREFERRED DNS-OVER-TLS PROVIDER"; font.pixelSize: 10; font.letterSpacing: 1.4; color: Theme.muted }
            RowLayout { spacing: 6; Repeater { model: [["cloudflare", "Cloudflare"], ["quad9", "Quad9"], ["mullvad", "Mullvad"]]; StationButton { required property var modelData; text: modelData[1]; checked: Config.saved.shieldDnsProvider === modelData[0]; onClicked: Config.set("shieldDnsProvider", modelData[0]) } } }
            SectionMark { text: "ABOUT"; Layout.topMargin: 8 }
            GlowText { text: "CEDAR Shield is a presentation over the services that own each protection. Closing this window or restarting the shell changes none of them. Keyboard: Ctrl+1…5 switch pages, Escape goes back, Ctrl+W closes."; font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
        }
    }
}
