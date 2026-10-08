import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import ".."
import "../components"
import "../services"

ColumnLayout {
    id: root
    property bool active: false
    property var selected: null
    property string confirmForget: ""
    property bool hotspot: false
    // The Settings Connections page shows these in sections of its own.
    property bool showTitle: true
    property bool showHotspot: true
    Connections {
        target: Network
        function onDataChanged() {
            if (root.selected && !(Network.data.networks || []).some(row => row.path === root.selected.path)) {
                password.text = "";
                root.selected = null;
            }
        }
    }
    onActiveChanged: {
        password.text = "";
        if (active)
            Network.refresh();
        else
            selected = null;
    }
    spacing: 12
    // Instruments settle one beat after another while the panel enters; in the
    // Settings page the clock is already at rest, so nothing moves.
    function beat(order, span = .4) { return Canopy.ease(.06 * order, span); }
    RowLayout {
        visible: root.showTitle
        spacing: 8
        opacity: root.beat(0)
        transform: Translate { y: 6 * (1 - root.beat(0)) }
        Rectangle { width: 14; height: 1; color: Theme.teal; opacity: .7 }
        GlowText {
            text: "Connections"
            color: Theme.teal
            font.pixelSize: 19
        }
    }
    Flow {
        Layout.fillWidth: true
        spacing: 8
        opacity: root.beat(1)
        transform: Translate { y: 6 * (1 - root.beat(1)) }
        StatusPill { text: Network.label; tone: Network.state === "connected" ? Theme.green : Theme.muted }
        StatusPill { visible: Network.vpnActive; text: "VPN"; tone: Theme.green }
        StatusPill { text: ({ unknown: "Internet unchecked", none: "No internet", portal: "Sign-in required", limited: "Limited internet", verified: "Internet verified" })[Network.data.available ? Network.data.status?.internet || "unknown" : "unknown"]; tone: Network.data.status?.internet === "verified" ? Theme.green : Network.data.status?.internet === "none" ? Theme.amber : Theme.muted }
    }
    GlowText {
        visible: Network.error !== ""
        text: Network.error
        color: Theme.amber
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
    }
    StationToggle {
        Layout.fillWidth: true
        opacity: root.beat(2)
        transform: Translate { x: 10 * (1 - root.beat(2)) }
        label: "Wi-Fi"
        checked: Network.data.enabled
        enabled: Network.data.available && Network.data.hardware
        busy: Network.busy
        description: !Network.data.hardware ? "No enabled wireless adapter available" : "Wireless networks in range"
        onToggled: value => Network.run({
                action: "radio",
                enabled: value
            })
    }
    Flow {
        Layout.fillWidth: true
        spacing: 8
        opacity: root.beat(3)
        transform: Translate { x: 10 * (1 - root.beat(3)) }
        StationButton {
            text: Network.busy ? "Working…" : "Scan"
            enabled: Network.data.enabled && !Network.busy
            onClicked: Network.run({
                action: "scan"
            })
        }
        StationButton {
            visible: root.showHotspot
            text: "Hotspot"
            enabled: Network.data.enabled && !Network.busy
            checked: root.hotspot
            onClicked: root.hotspot = !root.hotspot
        }
        StationButton {
            text: "Advanced networks (terminal)"
            onClicked: {
                Quickshell.execDetached(Config.terminal.concat(["-e", "nmtui"]));
                ShellState.close();
            }
        }
    }
    Repeater {
        model: Network.networks
        // Each network settles a beat after the last; its signal bar sweeps to strength.
        RowLayout {
            id: row
            required property var model
            required property int index
            readonly property var modelData: model
            readonly property real sweep: root.beat(4 + Math.min(index, 8), .4)
            Layout.fillWidth: true
            opacity: sweep
            transform: Translate { x: 10 * (1 - row.sweep) }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                GlowText {
                    text: row.modelData.ssid
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    color: row.modelData.active ? Theme.green : Theme.text
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Rectangle {
                        Layout.preferredWidth: 72
                        implicitHeight: 2
                        color: Qt.alpha(Theme.teal, .12)
                        Rectangle {
                            width: parent.width * Math.max(0, Math.min(1, row.modelData.strength / 100)) * row.sweep
                            height: parent.height
                            color: row.modelData.active ? Theme.green : Theme.teal
                            Rectangle { visible: parent.width > 12; anchors.right: parent.right; width: 8; height: parent.height; color: Theme.green; opacity: .8 }
                        }
                    }
                    GlowText {
                        Layout.fillWidth: true
                        text: Math.round(row.modelData.strength * row.sweep) + "% · " + row.modelData.security + (row.modelData.saved ? " · saved" : "")
                        color: Theme.muted
                        font.pixelSize: 10
                        elide: Text.ElideRight
                    }
                }
            }
            StationButton {
                text: modelData.active ? "Disconnect" : "Connect"
                enabled: !Network.busy
                onClicked: {
                    password.text = "";
                    if (modelData.active)
                        Network.run({
                            action: "disconnect",
                            device: modelData.device
                        });
                    else if (modelData.saved || modelData.security === "open")
                        Network.run({
                            action: "connect",
                            path: modelData.path
                        });
                    else
                        root.selected = {path: modelData.path, ssid: modelData.ssid, security: modelData.security};
                }
            }
        }
    }
    ColumnLayout {
        visible: root.selected !== null
        Layout.fillWidth: true
        GlowText {
            text: "Join " + (root.selected?.ssid || "")
            color: Theme.teal
        }
        GlowText {
            visible: ["enterprise", "unsupported"].includes(root.selected?.security)
            text: "Use the advanced network editor to configure enterprise credentials or legacy security."
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: Theme.amber
        }
        StationField {
            id: password
            objectName: "networkPassword"
            Layout.fillWidth: true
            echoMode: TextInput.Password
            placeholderText: "Network password"
            inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
            onAccepted: join.clicked()
        }
        RowLayout {
            StationButton {
                id: join
                text: "Join network"
                enabled: root.selected !== null && !Network.busy && password.text.length > 0 && !["enterprise", "unsupported"].includes(root.selected?.security)
                onClicked: {
                    if (!enabled || !(Network.data.networks || []).some(row => row.path === root.selected?.path)) {
                        password.text = "";
                        root.selected = null;
                        return;
                    }
                    Network.run({
                        action: "connect",
                        path: root.selected.path,
                        password: password.text
                    });
                    password.text = "";
                    root.selected = null;
                }
            }
            StationButton {
                text: "Cancel"
                onClicked: {
                    password.text = "";
                    root.selected = null;
                }
            }
        }
    }
    HotspotSettings {
        visible: root.hotspot && root.showHotspot
        Layout.fillWidth: true
    }
    // VPN: the tunnels NetworkManager knows, whoever created them. A profile a
    // VPN application manages is still controllable here; the app may reconnect.
    RowLayout {
        Layout.fillWidth: true; Layout.topMargin: 8; spacing: 8
        opacity: root.beat(5)
        SectionMark { text: "VPN"; tone: Network.vpnActive ? Theme.green : Theme.teal }
        Item { Layout.fillWidth: true }
        GlowText { text: Network.vpns.count ? Network.vpns.count + (Network.vpns.count === 1 ? " PROFILE" : " PROFILES") : "NO PROFILES"; font.pixelSize: 9; font.letterSpacing: 1.2; color: Theme.muted }
    }
    GlowText {
        visible: Network.vpns.count === 0
        text: Network.data.available ? "No VPN or WireGuard profile is saved in NetworkManager. Import one (a WireGuard file from your provider works with `nmcli connection import type wireguard file …`) and it appears here." : "NetworkManager is not reachable."
        font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap
        opacity: root.beat(6)
    }
    Repeater {
        model: Network.vpns
        ColumnLayout {
            id: vpn
            required property var model
            required property int index
            readonly property var modelData: model
            readonly property bool pending: Network.pendingPath === modelData.path && Network.busy
            readonly property string state: pending ? (Network.pendingAction === "deactivate" ? "Disconnecting…" : "Connecting…") : modelData.active ? "Connected" : "Saved"
            readonly property bool managed: /^ProtonVPN|^pvpn-|^Mullvad|^NordVPN|^ExpressVPN/i.test(modelData.name)
            readonly property real sweep: root.beat(6 + Math.min(index, 6), .4)
            Layout.fillWidth: true; spacing: 2
            opacity: sweep
            transform: Translate { x: 10 * (1 - vpn.sweep) }
            // Name and state on one line, the kind and the controls on the next: the drop is narrow.
            RowLayout {
                Layout.fillWidth: true; spacing: 10
                Rectangle { width: 8; height: 8; radius: 4; color: vpn.modelData.active ? Theme.green : vpn.pending ? Theme.teal : Theme.muted }
                GlowText { text: vpn.modelData.name; Layout.fillWidth: true; elide: Text.ElideRight; color: vpn.modelData.active ? Theme.green : Theme.text }
                StatusPill { text: vpn.state; tone: vpn.modelData.active ? Theme.green : vpn.pending ? Theme.teal : Theme.muted }
            }
            RowLayout {
                Layout.fillWidth: true; Layout.leftMargin: 18; spacing: 8
                GlowText { text: (vpn.modelData.type === "wireguard" ? "WireGuard" : "VPN plugin") + (vpn.managed ? " · kept by its own app, which may reconnect" : "") + (vpn.modelData.autoconnect ? " · automatic" : ""); font.pixelSize: 10; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                StationButton { text: vpn.pending ? "Working…" : vpn.modelData.active ? "Disconnect" : "Connect"; implicitHeight: 28; enabled: !Network.busy; onClicked: Network.run({ action: vpn.modelData.active ? "deactivate" : "activate", path: vpn.modelData.path }) }
                StationButton { text: "Forget"; implicitHeight: 28; enabled: !Network.busy; onClicked: root.confirmForget = vpn.modelData.path }
            }
            RowLayout {
                visible: root.confirmForget === vpn.modelData.path
                GlowText { text: "Remove this VPN profile from NetworkManager?"; color: Theme.amber; font.pixelSize: Theme.small }
                StationButton { text: "Forget profile"; accent: Theme.amber; onClicked: { Network.run({ action: "forget", path: vpn.modelData.path }); root.confirmForget = ""; } }
                StationButton { text: "Cancel"; onClicked: root.confirmForget = "" }
            }
        }
    }
    GlowText {
        visible: Network.killSwitch !== null
        text: "A kill-switch connection (" + (Network.killSwitch ? Network.killSwitch.name : "") + ") is active. It belongs to the VPN application; CEDAR reports it and does not enforce one of its own."
        font.pixelSize: 10; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap
        opacity: root.beat(7)
    }
    GlowText {
        visible: Network.vpns.count > 0
        text: "Advanced settings (servers, keys, DNS) are the profile's own: edit them with “Advanced networks (terminal)” above or your provider's application."
        font.pixelSize: 10; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap
        opacity: root.beat(7)
    }
    SectionMark {
        text: "SAVED NETWORKS"
        Layout.topMargin: 8
        opacity: root.beat(6)
    }
    Repeater {
        model: Network.savedNetworks
        ColumnLayout {
            id: saved
            required property var model
            required property int index
            readonly property var modelData: model
            readonly property real sweep: root.beat(7 + Math.min(index, 8), .4)
            readonly property bool pending: Network.pendingPath === modelData.path && Network.busy
            Layout.fillWidth: true
            opacity: sweep
            transform: Translate { x: 10 * (1 - saved.sweep) }
            RowLayout {
                Layout.fillWidth: true
                GlowText {
                    text: modelData.name + " · " + modelData.type.replace("802-11-wireless", "Wi-Fi").replace("802-3-ethernet", "wired")
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    color: modelData.active ? Theme.green : Theme.text
                }
                StatusPill { visible: modelData.active || saved.pending; text: saved.pending ? (Network.pendingAction === "deactivate" ? "Disconnecting…" : "Connecting…") : "Connected"; tone: saved.pending ? Theme.teal : Theme.green }
                StationButton {
                    text: saved.pending ? "Working…" : modelData.active ? "Disconnect" : "Connect"
                    enabled: !Network.busy
                    onClicked: Network.run({
                        action: modelData.active ? "deactivate" : "activate",
                        path: modelData.path
                    })
                }
                StationButton {
                    text: "Forget"
                    enabled: !Network.busy
                    onClicked: root.confirmForget = modelData.path
                }
            }
            StationToggle {
                Layout.fillWidth: true
                label: "Connect automatically"
                checked: modelData.autoconnect === true
                busy: Network.busy
                onToggled: value => Network.run({
                        action: "autoconnect",
                        path: modelData.path,
                        enabled: value
                    })
            }
            RowLayout {
                visible: root.confirmForget === modelData.path
                GlowText {
                    text: "Remove the saved connection?"
                    color: Theme.amber
                }
                StationButton {
                    text: "Forget connection"
                    onClicked: {
                        Network.run({
                            action: "forget",
                            path: modelData.path
                        });
                        root.confirmForget = "";
                    }
                }
                StationButton {
                    text: "Cancel"
                    onClicked: root.confirmForget = ""
                }
            }
        }
    }
}
