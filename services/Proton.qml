pragma Singleton
import QtQuick
import Quickshell
import ".."
import "../components"

// Proton VPN, driven through Proton's own CLI by scripts/protonvpn.py.
//
// Up/down comes from NetworkManager, which CEDAR already watches: the CLI
// brings its tunnel up as a "ProtonVPN <server>" WireGuard (or VPN) profile.
// `protonvpn status`/`info` cost about a second of Python each and talk to the
// keyring, so they run only while the Connections drop is open, after an
// action, and when the tunnel comes up or goes down there. Nothing polls.
Singleton {
    id: root
    property var data: ({ installed: false, conflict: false, signedIn: false, account: "", plan: "", paid: false,
                          status: { connected: false, connecting: false, text: "", server: "", location: "", load: "", protocol: "" },
                          config: ({}), countries: [], error: "" })
    property bool probed: false
    property string error: ""
    // What the running action is doing, for the card: "Connecting to Japan…".
    property string working: ""
    readonly property bool busy: request.busy
    readonly property bool loading: probe.busy

    readonly property var tunnel: (Network.data.active || []).find(c => c.state === 2 && /^ProtonVPN/i.test(c.name) && (c.vpn || Network.tunnelTypes.includes(c.type))) || null
    readonly property bool connected: tunnel !== null || data.status.connected
    readonly property string server: data.status.server || (tunnel ? tunnel.name.replace(/^ProtonVPN\s*/i, "") : "")
    readonly property bool killSwitch: data.config["kill-switch"] === "standard"
    readonly property bool netShield: !!data.config.netshield && data.config.netshield !== "off"
    readonly property var countries: data.countries || []

    readonly property bool watching: Network.expanded && !Config.testMode
    onWatchingChanged: if (watching) refresh()
    onConnectedChanged: if (watching && !busy) settle.restart()

    function refresh() {
        if (Config.testMode || ShellState.locked) return;
        probe.send({ action: "status", countries: countries.length === 0 });
    }
    function run(req, label) {
        if (Config.testMode || ShellState.locked || request.busy) return;
        error = ""; working = label || "Working…";
        request.send(req);
    }
    function connectTo(target, country, name) {
        run({ action: "connect", target: target, country: country || "" },
            target === "country" ? "Connecting to " + name + "…" : target === "fastest" ? "Connecting to the fastest server…" : "Connecting…");
    }
    function disconnect() { run({ action: "disconnect" }, "Disconnecting…"); }
    function setOption(key, value) { run({ action: "config", key: key, value: value }, "Saving…"); }
    // Password and 2FA belong to Proton's own prompt; CEDAR never sees them.
    function signIn() {
        Quickshell.execDetached(Config.terminal.concat(["-e", "sh", "-c", "read -rp 'Proton username: ' u && protonvpn signin \"$u\"; printf '\\nPress Enter to close. '; read -r _"]));
        ShellState.close();
    }
    function install() {
        Quickshell.execDetached(Config.terminal.concat(["-e", "sh", "-c", "sudo pacman -S --needed proton-vpn-cli; printf '\\nPress Enter to close. '; read -r _"]));
        ShellState.close();
    }

    // The tunnel's own up/down settles a moment after NetworkManager reports it.
    Timer { id: settle; interval: 1200; onTriggered: root.refresh() }

    ServiceRequest {
        id: probe
        script: "scripts/protonvpn.py"
        timeoutMs: 40000
        onResult: value => {
            const keep = root.data.countries || [];
            root.data = Object.assign({}, value, { countries: (value.countries || []).length ? value.countries : keep });
            root.probed = true;
            if (value.error) root.error = value.error;
        }
        onFailed: message => { root.error = message; root.probed = true; }
    }
    ServiceRequest {
        id: request
        script: "scripts/protonvpn.py"
        // `protonvpn connect` can take most of a minute.
        timeoutMs: 100000
        onResult: value => {
            root.working = "";
            root.data = Object.assign({}, value, { countries: root.data.countries || [] });
        }
        onFailed: message => { root.working = ""; root.error = message; root.refresh(); }
    }
}
