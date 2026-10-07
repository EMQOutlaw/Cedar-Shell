pragma Singleton
import QtQuick
import Quickshell
import ".."
import "../components"

// What this host provides, discovered once by scripts/capabilities.py and
// cached: the firewall manager that owns the system, who answers DNS and
// whether it can do DNS-over-TLS, GameMode, the GPU vendor and its telemetry
// tool, the power-profile provider, the privilege helper and the
// distribution. Rediscovered only on refresh(): Shield opening, a privileged
// action finishing, or the user asking. Nothing here polls.
Singleton {
    id: root
    property var data: ({
            firewall: { available: false, provider: "none", owner: "none", active: false, providers: [], unit: "", competing: false },
            dns: { resolver: "unknown", dotSupported: false, dohSupported: false, resolvedActive: false, networkManager: false },
            gaming: { gameModeAvailable: false, gameModeRunning: false, gameModeRun: false, hyprctl: false, systemdInhibit: false },
            gpu: { vendor: "unknown", tool: "none", supportsUtilization: false, supportsTemperature: false, supportsPerformancePolicy: false },
            power: { provider: "none", profiles: false },
            privilege: { helper: "none", agent: false },
            distro: { id: "unknown", name: "Linux", packageManager: "unknown" },
            network: { networkManager: false, nmcli: false, bluetooth: false }
        })
    property bool ready: false
    property string error: ""
    property double discoveredAt: 0
    readonly property bool busy: probe.running
    readonly property var firewall: data.firewall
    readonly property var dns: data.dns
    readonly property var gaming: data.gaming
    readonly property var gpu: data.gpu
    readonly property var power: data.power
    readonly property var privilege: data.privilege
    readonly property var distro: data.distro
    readonly property var network: data.network
    // Privileged actions need pkexec and an authentication agent to ask the user.
    readonly property bool canElevate: privilege.helper === "pkexec" && privilege.agent
    function refresh() {
        if (Config.testMode || probe.running) return;
        probe.send({ action: "snapshot" });
    }
    ServiceRequest {
        id: probe
        script: "scripts/capabilities.py"
        timeoutMs: 20000
        onResult: value => { root.data = value; root.ready = true; root.error = ""; root.discoveredAt = Date.now(); }
        onFailed: value => { root.error = value; root.ready = true; }
    }
    Component.onCompleted: if (Config.stage >= 3) refresh()
}
