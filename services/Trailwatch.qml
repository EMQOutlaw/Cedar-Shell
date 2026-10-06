pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.UPower
import ".."
import "../components"
import "../components/trailwatch/Policy.js" as Policy

Singleton {
    id: root
    property int viewers: 0
    property bool shielded: false
    readonly property bool active: viewers > 0
    property var extra: ({
            at: 0,
            reminders: null,
            failed: null,
            agenda: {
                status: "unconfigured",
                events: []
            },
            gpus: []
        })
    property bool sourceError: false
    property double now: Date.now()
    readonly property bool extraFresh: !sourceError && now - extra.at < 90000
    readonly property var battery: UPower.displayDevice
    readonly property bool hasBattery: !!battery?.ready && battery.isPresent
    readonly property string power: hasBattery ? Math.round(battery.percentage * 100) + "%" : battery?.ready ? "AC" : "—"
    readonly property bool lowPower: hasBattery && UPower.onBattery && battery.percentage <= .2
    readonly property string powerState: hasBattery ? (battery.state === UPowerDeviceState.Charging ? "Charging" : battery.state === UPowerDeviceState.FullyCharged ? "Fully charged" : UPower.onBattery ? "On battery" : "External power") : battery?.ready ? "External power · no battery" : "Power source unavailable"
    readonly property string profile: Controls.error ? "Profile unavailable" : Controls.data.profile || "Profile unavailable"
    readonly property var connected: BluetoothService.devices.filter(d => d.connected)
    readonly property var deviceBatteries: connected.filter(d => d.batteryAvailable)
    readonly property bool netKnown: Network.data.available
    readonly property bool linked: netKnown && Network.data.devices.some(d => d.state === 100)
    readonly property string link: !netKnown ? "Unavailable" : Network.data.devices.some(d => d.type === 1 && d.state === 100) ? "Ethernet" : Network.data.devices.some(d => d.type === 2 && d.state === 100) ? "Wi-Fi" : linked ? "Network" : "Disconnected"
    readonly property string internet: !netKnown ? "Network unavailable" : !linked ? "Offline" : Network.data.connectivity === 4 ? "Online" : Network.data.connectivity === 2 ? "Captive portal" : Network.data.connectivity === 3 ? "Limited connectivity" : "Link active · internet unverified"
    readonly property bool vpn: netKnown && (Network.data.active || []).some(c => c.state === 2 && (c.vpn || ["vpn", "wireguard"].includes(c.type)))
    readonly property bool capsKnown: Object.prototype.hasOwnProperty.call(keyboard, "capslock")
    readonly property var keyboard: CoreService.enabled ? (CoreService.probe.error ? {} : CoreService.probe.data.keyboard) : (lockProbe.error ? {} : lockProbe.data.keyboard)
    readonly property bool weatherStale: Weather.stale || !Weather.updatedAt || now - Weather.updatedAt.getTime() > 1800000
    readonly property var ready: Policy.readiness({
        lowPower: lowPower,
        hot: SystemStats.temperature >= Config.saved.coreTemperatureLimit,
        disk: SystemStats.disk * 100 >= Config.saved.coreDiskLimit,
        failed: extraFresh ? extra.failed : 0,
        storm: !weatherStale && Weather.code >= 95,
        offline: netKnown && !linked,
        known: netKnown && SystemStats.available,
        quiet: Config.saved.doNotDisturb
    })
    readonly property string forestState: ready.warning ? "EMBER" : CoreService.recording || CoreService.privacy.length ? "WATCH" : Config.saved.doNotDisturb ? "QUIET" : profile === "performance" ? "HUNT" : Media.player?.isPlaying || CoreService.timer.active ? "FLOW" : !SystemStats.available ? "AWAKE" : "REST"
    readonly property string forestPhrase: ({
            EMBER: "Something needs attention.",
            HUNT: "Focused on the hunt.",
            FLOW: "Signals through the trees.",
            AWAKE: "The light stays on.",
            QUIET: "The woods are quiet.",
            WATCH: "Keeping watch.",
            REST: "The forest settles."
        })[forestState]
    CoreProbe {
        id: lockProbe
        enabled: root.active && !CoreService.enabled
    }
    function refresh() {
        now = Date.now();
        if (!Config.testMode && !reader.running)
            reader.send({});
    }
    onActiveChanged: if (!active) {
        shielded = false;
    } else {
        refresh();
        Network.refresh();
        Weather.refresh();
        Controls.refresh();
    }
    Timer {
        interval: 30000
        running: root.active
        repeat: true
        onTriggered: {
            root.refresh();
            Controls.refresh();
        }
    }
    ServiceRequest {
        id: reader
        script: "scripts/trailwatch.py"
        onResult: value => {
            root.extra = value;
            root.sourceError = false;
            root.now = Date.now();
        }
        onFailed: value => root.sourceError = true
    }
}
