pragma Singleton
import QtQuick
import Quickshell
import ".."
import "../components"

// Tailscale, driven through its own CLI by scripts/tailscale.py.
//
// `tailscale status --json` is answered locally by tailscaled and costs little,
// so it runs when the Connections drop opens, after an action, and when the
// tailscale0 tunnel appears or vanishes in NetworkManager (which lists it as
// an externally managed tun). Nothing polls.
//
// Tailscale and Proton VPN never run together here: each claims routes and
// DNS the other wants, and Proton's kill switch cuts the tailnet. Up waits
// while Proton is connected (TailscaleCard); Proton waits while Tailscale is
// up (ProtonCard). scripts/tailscale.py and scripts/protonvpn.py hold the
// same guard, so two surfaces cannot race past each other.
Singleton {
    id: root
    property var data: ({ installed: false, running: false,
                          status: { state: "NoState", up: false, needsLogin: false, hostname: "", ip: "", tailnet: "", peers: 0, peersOnline: 0, exitNode: "", health: [] },
                          error: "" })
    property bool probed: false
    property string error: ""
    // What the running action is doing, for the card: "Bringing Tailscale up…".
    property string working: ""
    readonly property bool busy: request.busy
    readonly property bool loading: probe.busy
    readonly property bool installed: data.installed

    // tailscale0 as NetworkManager sees it. The interface outlives `tailscale down`,
    // so it only stands in for the real answer until the first probe lands.
    readonly property var device: (Network.data.active || []).find(c => c.state === 2 && /^tailscale/i.test(c.name)) || null
    readonly property bool up: probed ? data.status.up : device !== null
    readonly property bool needsLogin: data.status.needsLogin

    readonly property bool watching: Network.expanded && !Config.testMode
    onWatchingChanged: if (watching) refresh()
    onDeviceChanged: if (watching && !busy) settle.restart()

    function refresh() {
        if (Config.testMode || ShellState.locked) return;
        probe.send({ action: "status" });
    }
    function run(req, label) {
        if (Config.testMode || ShellState.locked || request.busy) return;
        error = ""; working = label || "Working…";
        request.send(req);
    }
    function bringUp() { run({ action: "up" }, "Bringing Tailscale up…"); }
    function bringDown() { run({ action: "down" }, "Bringing Tailscale down…"); }
    // `tailscale up` prints a login link and waits for the browser; that belongs in a terminal.
    function signIn() {
        Quickshell.execDetached(Config.terminal.concat(["-e", "sh", "-c", "tailscale up; printf '\\nPress Enter to close. '; read -r _"]));
        ShellState.close();
    }
    // tailscaled is a system service; starting it is root's, in the open.
    function startService() {
        Quickshell.execDetached(Config.terminal.concat(["-e", "sh", "-c", "sudo systemctl start tailscaled; printf '\\nPress Enter to close. '; read -r _"]));
        ShellState.close();
    }

    // The tunnel's own up/down settles a moment after NetworkManager reports it.
    Timer { id: settle; interval: 1200; onTriggered: root.refresh() }

    ServiceRequest {
        id: probe
        script: "scripts/tailscale.py"
        timeoutMs: 20000
        onResult: value => {
            root.data = value;
            root.probed = true;
            if (value.error) root.error = value.error;
        }
        onFailed: message => { root.error = message; root.probed = true; }
    }
    ServiceRequest {
        id: request
        script: "scripts/tailscale.py"
        timeoutMs: 70000
        onResult: value => { root.working = ""; root.data = value; root.probed = true; }
        onFailed: message => { root.working = ""; root.error = message; root.refresh(); }
    }
}
