import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."
import "../components"
import "../services"
// Share this computer's connection. Credentials go straight to NetworkManager.
ColumnLayout {
    id: root
    readonly property var adapters: Network.data.devices.filter(d => d.type === 2 && d.hotspotCapable === true)
    property bool consent: false
    onVisibleChanged: if (!visible) { hotspotPassword.text = ""; consent = false; }
    spacing: 10
    // Already sharing
    RowLayout {
        visible: Network.hotspot !== null; Layout.fillWidth: true; spacing: 12
        Rectangle { width: 8; height: 8; radius: 4; color: Theme.strataAccent }
        ColumnLayout {
            Layout.fillWidth: true; spacing: 2
            GlowText { text: "Sharing as “" + (Network.hotspot?.ssid || Network.hotspot?.name || "") + "”"; color: Theme.strataAccent; Layout.fillWidth: true; elide: Text.ElideRight }
            GlowText { text: "Nearby devices can join with the password you set."; color: Theme.strataMuted; font.pixelSize: Theme.small }
        }
        StrataButton { text: "Stop sharing"; enabled: !Network.busy; onClicked: Network.run({action:"deactivate", path:Network.hotspot.path}) }
    }
    ColumnLayout {
        visible: Network.hotspot === null; Layout.fillWidth: true; spacing: 10
        GlowText {
            visible: root.adapters.length === 0
            text: !Network.data.enabled ? "Turn on Wi-Fi to share a hotspot." : "No Wi-Fi adapter here reports hotspot support."
            color: Theme.strataMuted; Layout.fillWidth: true; wrapMode: Text.WordWrap; font.pixelSize: Theme.small
        }
        GridLayout {
            visible: root.adapters.length > 0
            Layout.fillWidth: true; columns: root.width < 520 ? 1 : 2; columnSpacing: 10; rowSpacing: 8
            StrataField { id: hotspotName; Layout.fillWidth: true; placeholderText: "Hotspot name"; text: "CEDAR"; Accessible.name: "Hotspot name" }
            StrataField {
                id: hotspotPassword
                Layout.fillWidth: true
                placeholderText: "Password (8–63 characters)"
                echoMode: TextInput.Password
                inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
                Accessible.name: "Hotspot password"
            }
            StationCombo { id: hotspotAdapter; visible: root.adapters.length > 1; Layout.fillWidth: true; model: root.adapters; textRole: "name"; Accessible.name: "Hotspot adapter" }
        }
        StationToggle {
            accent: Theme.strataAccent
            focusAccent: Theme.strataAccent
            visible: root.adapters.length > 0
            checked: root.consent
            label: "Allow this adapter to leave its current network"
            description: "A Wi-Fi adapter can either join a network or share one. Starting a hotspot disconnects " + (root.adapters[Math.max(0, hotspotAdapter.currentIndex)]?.name || "it") + "."
            Layout.fillWidth: true
            onToggled: value => root.consent = value
        }
        StrataButton {
            visible: root.adapters.length > 0
            text: "Start hotspot"; accent: Theme.strataAccent
            enabled: root.consent && !Network.busy && hotspotPassword.text.length >= 8 && hotspotPassword.text.length <= 63 && hotspotName.text.trim() !== ""
            onClicked: {
                Network.run({
                    action: "hotspot",
                    approveDisconnect: root.consent,
                    device: root.adapters[Math.max(0, hotspotAdapter.currentIndex)].path,
                    ssid: hotspotName.text,
                    password: hotspotPassword.text
                });
                hotspotPassword.text = "";
                root.consent = false;
            }
        }
    }
}
