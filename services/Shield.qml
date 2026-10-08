pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import ".."
import "../components"

// Shield: the state of this computer's protections, read from the providers
// that own them (the firewall manager, systemd-resolved behind NetworkManager,
// the Wi-Fi profile, the connection's IPv6 and discovery settings, Avahi,
// /proc/net) and changed only through those providers' own interfaces by
// scripts/shield.py, which verifies and rolls back. Shield is a presentation
// over that; closing its window or restarting the shell changes nothing.
//
// The shell asks when the Shield window opens, when the user refreshes, after
// an action, and once per network change (debounced). Nothing polls.
//
// Protections are rows {id, group, label, state, value, provider, detail,
// reason, recommended}; state: on | off | warn | fail | unavailable | working.
// Posture: protected | attention | risk, from the recommended set only.
Singleton {
    id: root
    property var data: ({ firewall: null, dns: null, wifi: null, ipv6: null, discovery: null, exposure: null, connection: null, privilege: null, verifiedAt: 0 })
    property bool ready: false
    property string error: ""
    property string working: ""
    property double scannedAt: 0
    readonly property bool busy: worker.running
    property bool windowOpen: false
    readonly property bool open: windowOpen && !ShellState.locked

    // ------------------------------------------------------------- derived
    readonly property var firewall: data.firewall
    readonly property var dns: data.dns
    readonly property var wifi: data.wifi
    readonly property var ipv6: data.ipv6
    readonly property var discovery: data.discovery
    readonly property var exposure: data.exposure
    readonly property var connection: data.connection
    readonly property bool firewallOn: !!firewall && firewall.active
    readonly property string firewallManager: firewall && firewall.owner !== "none" ? firewall.owner : firewall && firewall.provider !== "none" ? firewall.provider : ""
    readonly property bool dnsEncrypted: !!dns && dns.mode !== "off"
    readonly property bool dnsSupported: !!dns && dns.supported
    readonly property string wifiPolicy: wifi && wifi.available ? wifi.policy : ""
    readonly property int exposedCount: exposure ? exposure.exposed : 0
    readonly property bool vpn: Network.vpnActive
    readonly property string networkLabel: Network.label
    readonly property string networkKind: Network.kind
    readonly property string connectionKey: connection ? String(connection.uuid || "") : ""
    readonly property string profile: connectionKey && store.profiles[connectionKey] ? store.profiles[connectionKey] : "trusted"
    readonly property bool publicNetwork: profile === "public"

    function row(id, group, label, state, value, provider, detail, reason, recommended) {
        return { id: id, group: group, label: label, state: state, value: value, provider: provider || "", detail: detail || "", reason: reason || "", recommended: !!recommended };
    }
    // Twelve protections in four groups. The branch pairs of the shield mark
    // follow this order, bottom to top.
    readonly property var protections: [
        row("firewall", "Network", "Firewall", working === "firewall" ? "working" : !firewall || !firewall.available ? "unavailable" : firewall.competing ? "fail" : firewallOn ? "on" : "off",
            !firewall || !firewall.available ? "No firewall manager installed" : firewall.competing ? "Two managers active" : firewallOn ? "Protected" : "Not protecting",
            firewallManager, firewallOn ? "Incoming connections are restricted by " + firewallManager + "." : firewallManager ? firewallManager + " is installed but not running." : "Install ufw, firewalld or nftables.",
            firewall && firewall.competing ? "Two firewall managers are active at once; only one should own the rules." : "", true),
        row("dns", "Network", "Encrypted DNS", working === "dns" ? "working" : !dns ? "unavailable" : !dnsSupported ? "unavailable" : dnsEncrypted ? (dns.mode === "strict" ? "on" : "warn") : "off",
            !dns ? "Unknown" : !dnsSupported ? "Not supported by current resolver" : dnsEncrypted ? "DNS-over-TLS · " + dns.providerLabel : "Plain DNS",
            dns ? (dnsSupported ? "systemd-resolved" : dns.resolver) : "", dns ? (dnsSupported ? "Name lookups on " + (dns.link || "the default route") + (dnsEncrypted ? " travel inside TLS to " + dns.providerLabel + (dns.mode === "opportunistic" ? ", falling back when TLS fails" : "") + "." : " are sent in the clear to " + (dns.providerLabel || "your network") + ".") : dns.reason) : "",
            dns && dnsEncrypted && dns.mode === "opportunistic" ? "Opportunistic mode falls back to plain DNS when TLS fails; strict never does." : "", publicNetwork),
        row("discovery", "Network", "Network discovery", working === "discovery" ? "working" : !discovery || !discovery.available ? "unavailable" : discovery.answering ? (publicNetwork ? "warn" : "off") : "on",
            !discovery || !discovery.available ? "Unknown" : discovery.answering ? "Answering name queries" : "Quiet on this network",
            discovery ? [discovery.avahi ? "Avahi" : "", discovery.mdns ? "mDNS" : "", discovery.llmnr ? "LLMNR" : ""].filter(Boolean).join(" · ") || "systemd-resolved" : "",
            discovery && discovery.available ? (discovery.answering ? "This computer answers multicast name queries, so others on the network can find it by name." : "Multicast name queries go unanswered; this computer stays unlisted.") : (discovery ? discovery.reason : ""),
            discovery && discovery.answering && publicNetwork ? "On a public network, answering discovery announces this computer to strangers." : "", publicNetwork),
        row("exposure", "Network", "Local exposure", !exposure ? "unavailable" : exposure.all + exposure.lan === 0 ? "on" : (publicNetwork && exposure.all > 0 ? "warn" : "warn"),
            !exposure ? "Not scanned" : exposure.exposed === 0 ? "Nothing listens beyond this computer" : exposure.exposed + (exposure.exposed === 1 ? " service visible" : " services visible") + " to your network",
            "kernel socket tables", exposure ? exposure.local + " local only · " + exposure.lan + " on this network · " + exposure.all + " on every interface" : "",
            exposure && exposure.all > 0 ? "A service on every interface answers any network you join; the firewall decides who reaches it." : "", false),
        row("wifi", "Privacy", "Private Wi-Fi address", working === "wifi" ? "working" : !wifi || !wifi.available || !wifi.connection ? "unavailable" : wifiPolicy === "stable" || wifiPolicy === "random" ? "on" : wifiPolicy === "hardware" ? "off" : "warn",
            !wifi || !wifi.available ? (wifi ? wifi.reason : "Unknown") : !wifi.connection ? "No Wi-Fi network saved yet" : ({ stable: "Stable private address", random: "Randomized address", hardware: "Hardware address", default: "System default", custom: "Custom address" })[wifiPolicy] || "Unknown",
            "NetworkManager", wifi && wifi.available && wifi.connection ? wifi.connection + (wifi.connected ? " · connected" : " · last used") : (wifi ? wifi.reason : ""),
            wifi && wifi.available && wifi.connection && wifiPolicy === "default" ? "NetworkManager's default keeps the hardware address unless the profile says otherwise." : "", false),
        row("ipv6", "Privacy", "IPv6 privacy", working === "ipv6" ? "working" : !ipv6 || !ipv6.available ? "unavailable" : ipv6.active ? "on" : ipv6.partial ? "warn" : "off",
            !ipv6 || !ipv6.available ? (ipv6 ? ipv6.reason : "Unknown") : ipv6.active ? "Temporary addresses" : ipv6.partial ? "Temporary addresses generated, public preferred" : "Stable address",
            "NetworkManager", ipv6 && ipv6.available ? (ipv6.active ? "Outgoing IPv6 connections use short-lived addresses, so sites cannot track the interface." : "The interface's stable IPv6 address identifies it across sites.") : "", "", publicNetwork),
        row("vpn", "Privacy", "VPN", vpn ? "on" : "off", vpn ? "Active" : "Not connected", "NetworkManager", vpn ? "Traffic leaves through the VPN." : "Traffic leaves through " + networkLabel + " directly.", "", false),
        row("lock", "Session", "Lock screen privacy", Config.saved.lockPrivacy ? "on" : "off", Config.saved.lockPrivacy ? "Hidden while locked" : "Details shown while locked", "CEDAR", Config.saved.lockPrivacy ? "Media, events, reminders and device names stay hidden on the lock screen." : "The lock screen shows media, events and device names.", "", true),
        row("idle", "Session", "Lock after inactivity", Config.idleLockSeconds > 0 ? "on" : "off", Config.idleLockSeconds > 0 ? "After " + Math.round(Config.idleLockSeconds / 60) + " min" : "Never", "CEDAR", Config.idleLockSeconds > 0 ? "An unattended session locks itself." : "An unattended session stays open.", "", true),
        row("local", "Services", "Local-only mode", Config.localOnly ? "on" : "off", Config.localOnly ? "No external requests" : "Weather and artwork may reach out", "CEDAR", Config.localOnly ? "CEDAR makes no requests to weather, location or artwork services." : "Weather, location or artwork requests may leave this computer.", "", false),
        row("clipboard", "Services", "Clipboard history", Config.saved.clipboardHistory ? "off" : "on", Config.saved.clipboardHistory ? "Kept" : "Not kept", "CEDAR", Config.saved.clipboardHistory ? "Copied text is kept in CEDAR's clipboard history until cleared." : "Nothing you copy is kept.", "", false),
        row("trails", "Services", "Activity trails", Config.saved.forestTrails ? "off" : "on", Config.saved.forestTrails ? "Recorded" : "Not recorded", "CEDAR", Config.saved.forestTrails ? "Opened panels and applications are kept as trails until the session locks." : "Nothing you open is recorded.", "", false)
    ]
    readonly property var groups: ["Network", "Privacy", "Session", "Services"]
    readonly property int onCount: protections.filter(p => p.state === "on").length
    readonly property int countable: protections.filter(p => p.state !== "unavailable").length
    readonly property var recommendedOff: protections.filter(p => p.recommended && (p.state === "off" || p.state === "warn"))
    readonly property var failed: protections.filter(p => p.state === "fail")
    readonly property bool atRisk: failed.length > 0 || (!!exposure && exposure.all > 0 && !!firewall && firewall.available && !firewallOn)
    readonly property string posture: !ready ? "reading" : atRisk ? "risk" : recommendedOff.length ? "attention" : "protected"
    readonly property string headline: posture === "reading" ? "Reading your protections…" : posture === "risk" ? "At risk" : posture === "attention" ? "Attention required" : "Protected"
    readonly property string subline: posture === "reading" ? "" : posture === "risk" ? (failed.length ? failed[0].label + ": " + failed[0].value : "Services answer every network and the firewall is off") : posture === "attention" ? recommendedOff.length + (recommendedOff.length === 1 ? " recommended protection is off" : " recommended protections are off") : onCount + " of " + countable + " protections active"
    readonly property string summary: posture === "reading" ? "Reading…" : headline + " · " + onCount + " / " + countable
    function protection(id) { return protections.find(p => p.id === id) || null; }

    // --------------------------------------------------------------- actions
    function refresh() { if (Config.testMode || busy) return; worker.send({ action: "snapshot" }); }
    function rescan() { if (Config.testMode || busy) return; worker.send({ action: "exposure" }); }
    function setFirewall(enable) { act("firewall", { action: "firewall", enable: !!enable }); }
    function setDns(mode, provider) { act("dns", { action: "dns", mode: mode, provider: provider || Config.saved.shieldDnsProvider || "cloudflare" }); }
    function setWifiPolicy(policy) { act("wifi", { action: "wifi", policy: policy }); }
    function setIpv6(enable) { act("ipv6", { action: "ipv6", enable: !!enable }); }
    function setDiscovery(enable) { act("discovery", { action: "discovery", enable: !!enable }); }
    property var pendingAction: null
    function act(id, request) {
        if (Config.testMode || busy || ShellState.locked) return;
        error = ""; working = id; pendingAction = request;
        worker.send(request);
    }
    // The network profile decides what is recommended; "Apply recommended" runs
    // the first recommended protection that is off, one verified step at a time.
    function setProfile(value) {
        if (!connectionKey || !["trusted", "public"].includes(value)) return;
        const next = Object.assign({}, store.profiles); next[connectionKey] = value;
        store.profiles = next; store.save();
        record("profile", "Network profile set to " + value, networkLabel);
    }
    function applyRecommended() {
        const first = recommendedOff[0];
        if (!first) return;
        if (first.id === "firewall") setFirewall(true);
        else if (first.id === "dns") setDns("strict");
        else if (first.id === "discovery") setDiscovery(false);
        else if (first.id === "ipv6") setIpv6(true);
        else if (first.id === "lock") Config.set("lockPrivacy", true);
        else if (first.id === "idle") Config.set("idleLockSeconds", 600);
    }
    ServiceRequest {
        id: worker
        script: "scripts/shield.py"
        timeoutMs: 150000              // a pkexec prompt waits for the user
        onResult: value => {
            const first = !root.ready;
            root.data = Object.assign({}, root.data, value);
            if (value.exposure) root.scannedAt = Date.now();
            root.ready = true; root.working = "";
            if (root.pendingAction) { root.record("action", root.actionLabel(root.pendingAction) + " verified", root.protection(root.pendingAction.action)?.value || ""); Capabilities.refresh(); }
            root.pendingAction = null;
            if (first) root.record("check", "Protections checked", root.onCount + " of " + root.countable + " active");
        }
        onFailed: message => {
            root.error = message; root.ready = true; root.working = "";
            if (root.pendingAction) root.record("failure", root.actionLabel(root.pendingAction) + " did not complete", message);
            root.pendingAction = null;
        }
    }
    function actionLabel(request) {
        return ({ firewall: request.enable ? "Firewall enabled" : "Firewall disabled", dns: request.mode === "off" ? "Encrypted DNS turned off" : "Encrypted DNS set to " + request.mode,
                  wifi: "Wi-Fi address policy set to " + request.policy, ipv6: request.enable ? "IPv6 privacy enabled" : "IPv6 privacy disabled",
                  discovery: request.enable ? "Network discovery enabled" : "Network discovery quieted" })[request.action] || request.action;
    }
    // Activity: only what Shield itself observed — a protection changing state
    // (after a read, an action, a setting or a network change), an action and
    // its result, a network or profile change. Diffed once per burst of changes.
    property var lastStates: null
    onProtectionsChanged: if (ready) diff.restart()
    Timer { id: diff; interval: 250; onTriggered: root.noteChanges() }
    function noteChanges() {
        const now = protections.map(p => ({ id: p.id, label: p.label, state: p.state, value: p.value }));
        if (lastStates) {
            for (const p of now) {
                const old = lastStates.find(b => b.id === p.id);
                if (old && old.state !== p.state && p.state !== "working" && old.state !== "working")
                    record(p.state === "on" ? "on" : p.state === "fail" ? "failure" : "change", p.label + ": " + p.value, old.value + " → " + p.value);
            }
        }
        lastStates = now;
    }
    function record(kind, title, detail) {
        const entry = { at: Date.now(), kind: kind, title: String(title).slice(0, 120), detail: String(detail || "").slice(0, 200) };
        store.activity = [entry].concat(store.activity).slice(0, 100);
        store.save();
    }
    readonly property var activity: store.activity

    // ----------------------------------------------------------- persistence
    // ~/.local/state/cedar/shield.json: per-network profiles, the activity log
    // and the window's last size. Never the protections themselves.
    QtObject {
        id: store
        property var profiles: ({})
        property var activity: []
        property var window: ({ width: 1120, height: 760 })
        function save() { file.setText(JSON.stringify({ profiles: profiles, activity: activity, window: window }) + "\n"); }
    }
    FileView {
        id: file; path: Config.stateDir + "/shield.json"; atomicWrites: true; printErrors: false; blockLoading: true
        onLoaded: {
            try {
                const saved = JSON.parse(text() || "{}");
                if (saved && typeof saved === "object") {
                    store.profiles = saved.profiles && typeof saved.profiles === "object" ? saved.profiles : ({});
                    store.activity = Array.isArray(saved.activity) ? saved.activity.slice(0, 100) : [];
                    if (saved.window && saved.window.width > 0) store.window = saved.window;
                }
            } catch (_) {}
        }
    }
    readonly property var windowSize: store.window
    function rememberWindow(width, height) { if (width >= 720 && height >= 520) { store.window = { width: width, height: height }; store.save(); } }

    // ------------------------------------------------------------- the app
    function openApp() { if (ShellState.locked) return; windowOpen = true; }
    // A page asked for from outside (IPC, Go, `cedar shield network`): the
    // window opens if needed and ShieldPages consumes the request.
    readonly property var pageIds: ["overview", "protections", "network", "activity", "settings"]
    property string requestedPage: ""
    function openPage(page) {
        if (ShellState.locked) return;
        const id = String(page || "").toLowerCase();
        if (!pageIds.includes(id)) return;
        windowOpen = true; requestedPage = ""; requestedPage = id;
    }
    function closeApp() { windowOpen = false; }
    function toggleApp() { if (windowOpen) closeApp(); else openApp(); }
    onOpenChanged: if (open) refresh()
    // Signals: the posture is a row on the Core pill only while it asks for
    // something (attention: high; at risk: critical, sticky). Protected
    // removes it. Published from real reads, never from a guess.
    onPostureChanged: syncSignal()
    onSublineChanged: if (ready) syncSignal()
    function syncSignal() {
        if (!ready || !CoreService.enabled) return;
        if (posture === "attention" || posture === "risk")
            CoreService.publish({ id: "shield", type: "warning", priority: posture === "risk" ? "critical" : "high", sticky: posture === "risk", persistent: true,
                                  title: "Shield · " + headline, subtitle: subline, announce: !CoreService.rows.some(r => r.id === "shield"), remember: true,
                                  actions: [{ id: "open", label: "Open Shield" }] });
        else CoreService.remove("shield", false);
    }
    // A network change moves the DNS path, the listeners and the profile:
    // one fresh read, debounced, whether or not the window is open (a setting).
    property string lastNetwork: ""
    Connections {
        target: Network
        function onLabelChanged() {
            if (Network.state !== "connected") return;
            if (root.lastNetwork && root.lastNetwork !== Network.label) root.record("network", "Network changed", root.lastNetwork + " → " + Network.label);
            root.lastNetwork = Network.label;
            if (root.open || Config.saved.shieldWatchNetwork) settle.restart();
        }
    }
    Timer { id: settle; interval: 1500; onTriggered: root.refresh() }
    Connections { target: ShellState; function onLockedChanged() { if (ShellState.locked) root.windowOpen = false; } }
}
