pragma Singleton
import QtQuick
import Quickshell
import ".."
import "../components"

// Shield: the state of this computer's protections, read from the providers
// that own them (the firewall manager, systemd-resolved behind NetworkManager,
// the Wi-Fi profile, /proc/net) and changed only through those providers'
// own interfaces by scripts/shield.py, which verifies and rolls back. The
// shell asks when the Shield page opens, when the user refreshes, after an
// action, and when the network state materially changes; nothing polls.
//
// Every protection is a row: {id, label, state, value, detail, reason}
//   state: on | off | warn | fail | unavailable | working
Singleton {
    id: root
    property var data: ({ firewall: null, dns: null, wifi: null, exposure: null, privilege: null })
    property bool ready: false
    property string error: ""            // last failed action, with the provider's reason
    property string working: ""          // protection id of the action in flight
    property double scannedAt: 0
    readonly property bool busy: worker.running
    readonly property bool open: !ShellState.locked && ShellState.panel === "settings" && ShellState.settingsSection === "shield"

    // ------------------------------------------------------------- derived
    readonly property var firewall: data.firewall
    readonly property var dns: data.dns
    readonly property var wifi: data.wifi
    readonly property var exposure: data.exposure
    readonly property bool firewallOn: !!firewall && firewall.active
    readonly property string firewallManager: firewall && firewall.owner !== "none" ? firewall.owner : firewall && firewall.provider !== "none" ? firewall.provider : ""
    readonly property bool dnsEncrypted: !!dns && dns.mode !== "off"
    readonly property bool dnsSupported: !!dns && dns.supported
    readonly property string wifiPolicy: wifi && wifi.available ? wifi.policy : ""
    readonly property int exposedCount: exposure ? exposure.exposed : 0
    readonly property bool localOnly: Config.localOnly
    readonly property bool lockPrivacy: Config.saved.lockPrivacy
    readonly property bool vpn: Network.vpnActive

    // The protections, in the order the shield's segments light up.
    readonly property var protections: [
        row("firewall", "Firewall", working === "firewall" ? "working" : !firewall || !firewall.available ? "unavailable" : firewallOn ? "on" : "off",
            !firewall || !firewall.available ? "No firewall manager installed" : firewallOn ? "Protected" : "Not protecting",
            firewallManager ? "Managed by " + firewallManager + (firewall && firewall.competing ? " · another manager is also active" : "") : "Install ufw, firewalld or nftables",
            firewall && firewall.competing ? "Two firewall managers are active at once; only one should own the rules." : ""),
        row("dns", "Encrypted DNS", working === "dns" ? "working" : !dns ? "unavailable" : !dnsSupported ? "unavailable" : dnsEncrypted ? (dns.mode === "strict" ? "on" : "warn") : "off",
            !dns ? "Unknown" : !dnsSupported ? "Not supported by current resolver" : dnsEncrypted ? "DNS-over-TLS · " + dns.providerLabel + (dns.mode === "opportunistic" ? " · opportunistic" : "") : "Plain DNS · " + (dns.providerLabel || "your network"),
            dns ? (dnsSupported ? "systemd-resolved on " + (dns.link || "the default route") + (dns.connection ? " · " + dns.connection.name : "") : dns.reason) : "",
            dns && dnsEncrypted && dns.mode === "opportunistic" ? "Opportunistic mode falls back to plain DNS when TLS fails; strict mode never does." : ""),
        row("wifi", "Private Wi-Fi address", working === "wifi" ? "working" : !wifi || !wifi.available || !wifi.connection ? "unavailable" : wifiPolicy === "stable" || wifiPolicy === "random" ? "on" : wifiPolicy === "hardware" ? "off" : "warn",
            !wifi || !wifi.available ? (wifi ? wifi.reason : "Unknown") : !wifi.connection ? "No Wi-Fi network saved yet" : ({ stable: "Stable private", random: "Randomized", hardware: "Hardware address", default: "System default", custom: "Custom address" })[wifiPolicy] || "Unknown",
            wifi && wifi.available ? (wifi.connection ? wifi.connection + (wifi.connected ? " · connected" : " · last used") : wifi.reason) : "",
            wifi && wifi.available && wifiPolicy === "default" ? "NetworkManager's default keeps the hardware address unless the profile says otherwise." : ""),
        row("exposure", "Local exposure", !exposure ? "unavailable" : exposure.all + exposure.lan === 0 ? "on" : "warn",
            !exposure ? "Not scanned" : exposure.exposed === 0 ? "Nothing listens beyond this computer" : exposure.exposed + (exposure.exposed === 1 ? " service visible" : " services visible") + " to your network",
            exposure ? exposure.local + " local only · " + exposure.lan + " on this network · " + exposure.all + " on every interface" : "",
            exposure && exposure.all > 0 ? "A service on every interface answers any network you join; the firewall decides who reaches it." : ""),
        row("vpn", "VPN", vpn ? "on" : "off", vpn ? "Active" : "Not connected", "From NetworkManager", ""),
        row("lock", "Lock screen privacy", lockPrivacy ? "on" : "off", lockPrivacy ? "Hidden while locked" : "Details shown while locked", "Settings › Power & Lock", ""),
        row("local", "Local-only mode", localOnly ? "on" : "off", localOnly ? "No external requests" : "Weather and artwork may reach out", "Settings › Desktop", "")
    ]
    function row(id, label, state, value, detail, reason) { return { id: id, label: label, state: state, value: value, detail: detail, reason: reason }; }
    readonly property int onCount: protections.filter(p => p.state === "on").length
    readonly property int warnCount: protections.filter(p => p.state === "warn").length
    readonly property int offCount: protections.filter(p => p.state === "off" || p.state === "fail").length
    readonly property string headline: !ready ? "Reading your protections…" : offCount === 0 && warnCount === 0 ? "Your system is protected." : offCount === 0 ? "Protected, with " + warnCount + (warnCount === 1 ? " thing to look at." : " things to look at.") : offCount + (offCount === 1 ? " protection is off." : " protections are off.")

    // --------------------------------------------------------------- actions
    function refresh() { if (Config.testMode || busy) return; worker.send({ action: "snapshot" }); }
    function rescan() { if (Config.testMode || busy) return; worker.send({ action: "exposure" }); }
    function setFirewall(enable) { act("firewall", { action: "firewall", enable: !!enable }); }
    function setDns(mode, provider) { act("dns", { action: "dns", mode: mode, provider: provider || "cloudflare" }); }
    function setWifiPolicy(policy) { act("wifi", { action: "wifi", policy: policy }); }
    function act(id, request) {
        if (Config.testMode || busy || ShellState.locked) return;
        error = ""; working = id;
        worker.send(request);
    }
    ServiceRequest {
        id: worker
        script: "scripts/shield.py"
        timeoutMs: 150000              // a pkexec prompt waits for the user
        onResult: value => {
            root.data = Object.assign({}, root.data, value);
            if (value.exposure) root.scannedAt = Date.now();
            root.ready = true; root.working = "";
            if (root.lastAction) Capabilities.refresh();
            root.lastAction = false;
        }
        onFailed: message => { root.error = message; root.ready = true; root.working = ""; root.lastAction = false; }
        onStarted: root.lastAction = !!request.action && request.action !== "snapshot" && request.action !== "exposure"
    }
    property bool lastAction: false
    onOpenChanged: if (open) refresh()
    // A network change moves the DNS path and the listeners; one fresh read, debounced.
    Connections { target: Network; function onStateChanged() { if (root.open) settle.restart(); } }
    Timer { id: settle; interval: 1500; onTriggered: root.refresh() }
}
