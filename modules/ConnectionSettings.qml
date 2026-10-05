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
        hotspotPassword.text = "";
        if (active)
            Network.refresh();
        else
            selected = null;
    }
    spacing: 12
    GlowText {
        text: "Connections"
        color: Theme.teal
        font.pixelSize: 19
    }
    GlowText {
        text: Network.statusDescription
        color: Theme.green
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
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
        StationButton {
            text: Network.busy ? "Working…" : "Scan"
            enabled: Network.data.enabled && !Network.busy
            onClicked: Network.run({
                action: "scan"
            })
        }
        StationButton {
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
        RowLayout {
            required property var model
            readonly property var modelData: model
            Layout.fillWidth: true
            ColumnLayout {
                Layout.fillWidth: true
                GlowText {
                    text: modelData.ssid
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    color: modelData.active ? Theme.green : Theme.text
                }
                GlowText {
                    text: modelData.strength + "% · " + modelData.security + (modelData.saved ? " · saved" : "")
                    color: Theme.muted
                    font.pixelSize: 10
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
    ColumnLayout {
        visible: root.hotspot
        Layout.fillWidth: true
        GlowText {
            text: "Sharing an adapter disconnects it from its current Wi-Fi network."
            color: Theme.amber
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }
        StationCombo {
            id: hotspotAdapter
            Layout.fillWidth: true
            model: Network.data.devices.filter(d => d.type === 2 && d.hotspotCapable === true)
            textRole: "name"
        }
        StationField {
            id: hotspotName
            Layout.fillWidth: true
            placeholderText: "Hotspot name"
            text: "CEDAR"
        }
        StationField {
            id: hotspotPassword
            Layout.fillWidth: true
            placeholderText: "Password (8–63 characters)"
            echoMode: TextInput.Password
            inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
        }
        StationToggle {
            id:hotspotConsent
            property bool accepted: false
            checked:accepted
            label:"Allow this adapter to disconnect its current network"
            description:"Starting a hotspot changes how the selected Wi-Fi adapter is used."
            Layout.fillWidth:true
            onToggled:value=>accepted=value
        }
        StationButton {
            text: "Start hotspot"
            enabled: hotspotConsent.checked && !Network.busy && hotspotPassword.text.length >= 8 && hotspotAdapter.currentIndex >= 0
            onClicked: {
                Network.run({
                    action: "hotspot",
                    approveDisconnect: hotspotConsent.checked,
                    device: hotspotAdapter.model[hotspotAdapter.currentIndex].path,
                    ssid: hotspotName.text,
                    password: hotspotPassword.text
                });
                hotspotPassword.text = "";
            }
        }
    }
    GlowText {
        text: "SAVED NETWORKS & VPN"
        color: Theme.teal
        Layout.topMargin: 8
    }
    Repeater {
        model: Network.savedNetworks
        ColumnLayout {
            required property var model
            readonly property var modelData: model
            Layout.fillWidth: true
            RowLayout {
                Layout.fillWidth: true
                GlowText {
                    text: modelData.name + " · " + modelData.type
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    color: modelData.active ? Theme.green : Theme.text
                }
                StationButton {
                    text: modelData.active ? "Disconnect" : "Connect"
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
                visible: modelData.type !== "vpn"
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
