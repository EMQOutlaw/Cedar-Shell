import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import ".."

Scope {
    id: root
    required property var service
    property bool primed: false
    property var lastNetwork: null
    property var lastBluetooth: ({})
    property var lastKeyboard: ({})
    property var lastRecordings: []
    property string lastProfile: ""
    property bool lastOnBattery: UPower.onBattery
    property string lastWorkspace: ""
    property string lastTrack: ""
    property bool lastPlaying: false
    property bool warm: false
    readonly property var battery: UPower.displayDevice
    readonly property string bluetoothState: JSON.stringify(BluetoothService.devices.map(d => ({
                path: d.dbusPath,
                name: d.name || d.deviceName,
                connected: d.connected,
                battery: d.batteryAvailable ? d.battery : null
            })))
    readonly property string workspace: Hyprland.focusedMonitor?.activeWorkspace?.name || ""
    readonly property var privacyObjects: service.enabled && Config.saved.corePrivacy ? Pipewire.links.values.concat(Pipewire.nodes.values.filter(n => !n.audio)) : []
    property string privacyState: "[]"
    onPrivacyObjectsChanged: privacyDelay.restart()
    function readPrivacy() {
        if (!service.allowed("microphone")) {
            privacyState = "[]";
            return;
        }
        privacyState = JSON.stringify(Pipewire.links.values.filter(l => l.state === PwLinkState.Active && l.source?.ready && l.target?.ready && l.target.isStream && !l.source.isStream).map(l => {
            const source = l.source, p = source.properties || {}, target = l.target;
            const camera = ["v4l2", "libcamera"].includes(p["device.api"]) || p["media.role"] === "Camera";
            const mic = !!source.audio && !source.isSink && (source.name.startsWith("alsa_input.") || source.name.startsWith("bluez_input."));
            return {
                kind: camera ? "camera" : mic ? "microphone" : "",
                source: source.id,
                target: target.id,
                name: target.properties?.["application.name"] || target.description || target.name,
                muted: source.audio?.muted ?? false
            };
        }).filter(v => v.kind));
    }
    PwObjectTracker {
        objects: root.privacyObjects
    }
    onPrivacyStateChanged: syncPrivacy()
    onBluetoothStateChanged: syncBluetooth()
    onWorkspaceChanged: {
        if (primed && workspace && workspace !== lastWorkspace)
            service.publish({
                id: "workspace",
                type: "workspace",
                title: "Workspace " + workspace,
                subtitle: Hyprland.focusedMonitor?.name || "",
                timeout: 1200
            });
        lastWorkspace = workspace;
    }
    Component.onCompleted: warmup.start()
    Timer {
        id: warmup
        interval: 1200
        onTriggered: {
            root.primed = true;
            root.lastNetwork = Network.data;
            root.lastProfile = Controls.data.profile;
            root.syncBluetooth();
            root.syncProbe();
            root.syncMedia(false);
            root.syncPower(false);
            root.syncPrivacy();
            root.syncHealth();
            Controls.refresh();
        }
    }
    Timer {
        id: privacyDelay
        interval: 60
        onTriggered: root.readPrivacy()
    }
    Variants {
        model: service.enabled && Config.saved.corePrivacy ? Pipewire.links.values : []
        Scope {
            required property var modelData
            Connections {
                target: modelData
                function onStateChanged() {
                    privacyDelay.restart();
                }
            }
        }
    }
    Timer {
        id: mediaDelay
        interval: 80
        onTriggered: root.syncMedia(true)
    }
    Timer {
        id: volumeDelay
        interval: 24
        onTriggered: if (root.service.allowed("volume") && Audio.audio)
            Audio.show()
    }
    function syncMedia(announce) {
        const p = Media.player;
        if (!p || !service.allowed("media")) {
            service.remove("media", false);
            return;
        }
        const signature = p.dbusName + "/" + p.trackTitle + "/" + p.trackArtist;
        const changed = signature !== lastTrack || p.isPlaying !== lastPlaying;
        if (p.isPlaying || p.trackTitle)
            service.publish({
                id: "media",
                type: "media",
                priority: "normal",
                title: p.trackTitle || p.identity,
                subtitle: p.trackArtist || p.identity,
                persistent: true,
                timeout: 4500,
                announce: primed && announce && changed && p.isPlaying
            });
        else
            service.remove("media", false);
        lastTrack = signature;
        lastPlaying = p.isPlaying;
    }
    function syncBluetooth() {
        const devices = JSON.parse(bluetoothState), next = {};
        for (const d of devices) {
            next[d.path] = d.connected;
            if (primed && d.connected && lastBluetooth[d.path] === false)
                service.publish({
                    id: "bluetooth/" + d.path,
                    type: "bluetooth",
                    title: d.name,
                    subtitle: "Connected" + (d.battery !== null ? " · " + Math.round(d.battery * 100) + "% battery" : ""),
                    timeout: 4000,
                    remember: true,
                    actions: []
                });
        }
        lastBluetooth = next;
    }
    function syncNetwork() {
        const data = Network.data, previous = lastNetwork;
        lastNetwork = data;
        if (!primed || !data.available || !previous?.available)
            return;
        const live = data.saved.filter(c => c.active && !["vpn", "wireguard"].includes(c.type));
        const before = previous.saved.filter(c => c.active && !["vpn", "wireguard"].includes(c.type));
        const name = live.map(c => c.name).join(", "), oldName = before.map(c => c.name).join(", ");
        if (name !== oldName)
            service.publish({
                id: "network",
                type: "network",
                priority: name ? "normal" : "high",
                title: name || "Network connection lost",
                subtitle: name ? "Connected" : "No active network connection",
                timeout: name ? 4000 : 6000,
                remember: true,
                actions: []
            });
        const vpn = data.saved.filter(c => c.active && ["vpn", "wireguard"].includes(c.type));
        const oldVpn = previous.saved.filter(c => c.active && ["vpn", "wireguard"].includes(c.type));
        if (vpn.map(c => c.path).join() !== oldVpn.map(c => c.path).join())
            service.publish({
                id: "vpn",
                type: "vpn",
                title: vpn.length ? "VPN active" : "VPN disconnected",
                subtitle: (vpn.length ? vpn : oldVpn).map(c => c.name).join(", "),
                timeout: 4500,
                remember: true
            });
    }
    function syncProbe() {
        const data = service.probe.data, ids = data.recordings.map(r => "recording/" + r.pid + "/" + r.startTicks);
        for (const r of data.recordings)
            service.publish({
                id: "recording/" + r.pid + "/" + r.startTicks,
                type: "recording",
                priority: "high",
                title: "Screen recording",
                subtitle: r.microphone === true ? "Microphone included" : r.microphone === false ? "No microphone source requested" : "Audio sources selected by recorder",
                persistent: true,
                announce: primed && !lastRecordings.includes("recording/" + r.pid + "/" + r.startTicks),
                data: r,
                actions: [
                    {
                        id: "stop-recording",
                        label: "Stop recording"
                    }
                ]
            });
        for (const id of lastRecordings)
            if (!ids.includes(id)) {
                service.remove(id, false);
                if (primed)
                    service.publish({
                        id: "recording-ended",
                        type: "recording",
                        title: "Recording stopped",
                        subtitle: "Check the recorder’s result for the saved file.",
                        timeout: 5000,
                        remember: true
                    });
            }
        lastRecordings = ids;
        for (const key of Object.keys(data.keyboard))
            if (primed && key in lastKeyboard && data.keyboard[key] !== lastKeyboard[key])
                service.publish({
                    id: "keyboard/" + key,
                    type: "keyboard",
                    title: (key === "capslock" ? "Caps Lock" : "Num Lock") + " " + (data.keyboard[key] ? "on" : "off"),
                    timeout: 1500
                });
        lastKeyboard = data.keyboard;
    }
    function syncPrivacy() {
        if (!service.allowed("microphone")) {
            service.remove("privacy/microphone", false);
            service.remove("privacy/camera", false);
            return;
        }
        const links = JSON.parse(privacyState);
        for (const kind of ["microphone", "camera"]) {
            const names = [...new Set(links.filter(l => l.kind === kind).map(l => l.name + (l.muted ? " (muted)" : "")))];
            if (names.length)
                service.publish({
                    id: "privacy/" + kind,
                    type: kind,
                    priority: "high",
                    title: kind === "camera" ? "Camera in use" : "Microphone in use",
                    subtitle: names.join(", "),
                    persistent: true,
                    announce: !service.model.rows.some(r => r.id === "privacy/" + kind)
                });
            else
                service.remove("privacy/" + kind, false);
        }
    }
    function syncPower(announce) {
        if (!primed || !battery?.isPresent)
            return;
        const percent = Math.round(battery.percentage * 100);
        if (announce && UPower.onBattery !== lastOnBattery)
            service.publish({
                id: "power-source",
                type: "power",
                title: UPower.onBattery ? "Running on battery" : "External power connected",
                subtitle: percent + "% battery",
                timeout: 4000,
                remember: true
            });
        lastOnBattery = UPower.onBattery;
        if (UPower.onBattery && percent <= 15)
            service.publish({
                id: "low-battery",
                type: "power",
                priority: percent <= 5 ? "critical" : "high",
                sticky: true,
                persistent: true,
                title: percent <= 5 ? "Critically low battery" : "Low battery",
                subtitle: percent + "% remaining",
                announce: !service.model.rows.some(r => r.id === "low-battery"),
                actions: Controls.data.profiles.includes("power-saver") ? [
                    {
                        id: "power-saver",
                        label: "Enable Power Saver"
                    }
                ] : []
            });
        else if (!UPower.onBattery || percent >= 18)
            service.remove("low-battery", false);
    }
    function syncHealth() {
        if (!primed)
            return;
        const hot = SystemStats.temperature, limit = Config.saved.coreTemperatureLimit;
        if (hot >= limit)
            service.publish({
                id: "thermal",
                type: "warning",
                priority: "critical",
                sticky: true,
                persistent: true,
                title: "High temperature · " + Math.round(hot) + "°C",
                subtitle: "Reported by the system temperature sensors.",
                announce: !service.model.rows.some(r => r.id === "thermal"),
                actions: []
            });
        else if (hot < limit - 5)
            service.remove("thermal", false);
        const disk = SystemStats.disk, threshold = Config.saved.coreDiskLimit / 100;
        if (disk >= threshold)
            service.publish({
                id: "disk",
                type: "warning",
                priority: "high",
                sticky: true,
                persistent: true,
                title: "Storage is nearly full",
                subtitle: Math.round(disk * 100) + "% used at " + Config.diskPath,
                announce: !service.model.rows.some(r => r.id === "disk"),
                actions: []
            });
        else if (disk < threshold - .03)
            service.remove("disk", false);
    }
    function notice(n) {
        if (!service.available || !Config.saved.notificationsEnabled || ShellState.locked)
            return;
        const file = n.hints?.["image-path"];
        if (Config.saved.coreScreenshots && n.appName === "omarchy-action" && n.summary.startsWith("Screenshot saved") && typeof file === "string" && (file.startsWith("/") || file.startsWith("file:"))) {
            if (service.publish({
                id: "screenshot/" + n.id,
                type: "screenshot",
                title: "Screenshot captured",
                subtitle: "Open it, copy the image, or reveal the saved file.",
                timeout: 6500,
                remember: true,
                data: {
                    path: file
                },
                actions: [
                    {
                        id: "open-file",
                        label: "Open"
                    },
                    {
                        id: "copy-image",
                        label: "Copy image"
                    },
                    {
                        id: "reveal-file",
                        label: "Reveal"
                    }
                ]
            }))
                service.routedNoticeIds = service.routedNoticeIds.concat([n.id]);
        } else if (n.urgency === 2 && service.allowed("notification")) {
            if (service.publish({
                id: "notification/" + n.id,
                type: "notification",
                priority: "critical",
                title: n.appName || "Notification",
                subtitle: n.summary,
                persistent: true,
                timeout: 6000,
                data: {
                    noticeId: n.id
                },
                actions: n.actions.map(a => ({
                            id: "notice:" + a.identifier,
                            label: a.text
                        }))
            }))
                service.routedNoticeIds = service.routedNoticeIds.concat([n.id]);
        }
    }
    Connections {
        target: Network
        function onDataChanged() {
            root.syncNetwork();
        }
    }
    Connections {
        target: service.probe
        function onDataChanged() {
            if (!service.probe.error)
                root.syncProbe();
        }
        function onErrorChanged() {
            if (service.probe.error) {
                for (const id of root.lastRecordings)
                    service.remove(id, false);
                root.lastRecordings = [];
                service.publish({
                    id: "recorder-status",
                    type: "warning",
                    priority: "high",
                    title: "Recording status unavailable",
                    subtitle: service.probe.error,
                    timeout: 6000
                });
            } else {
                service.remove("recorder-status", false);
                root.syncProbe();
            }
        }
    }
    Connections {
        target: Media
        function onPlayerChanged() {
            mediaDelay.restart();
        }
    }
    Connections {
        target: Media.player
        ignoreUnknownSignals: true
        function onPostTrackChanged() {
            mediaDelay.restart();
        }
        function onIsPlayingChanged() {
            mediaDelay.restart();
        }
    }
    Connections {
        target: Audio.microphone
        function onMutedChanged() {
            privacyDelay.restart();
        }
    }
    Connections {
        target: Audio
        function onVolumeChanged() {
            if (root.primed)
                volumeDelay.restart();
        }
        function onMutedChanged() {
            if (root.primed)
                volumeDelay.restart();
        }
    }
    Connections {
        target: ShellState
        function onOsdOpenChanged() {
            root.syncOsd();
        }
        function onOsdKindChanged() {
            root.syncOsd();
        }
        function onOsdValueChanged() {
            root.syncOsd();
        }
        function onOsdLabelChanged() {
            root.syncOsd();
        }
    }
    function syncOsd() {
        if (!ShellState.osdOpen || !["VOLUME", "BRIGHTNESS"].includes(ShellState.osdKind)) {
            service.remove("osd", false);
            return;
        }
        const volume = ShellState.osdKind === "VOLUME";
        service.publish({
            id: "osd",
            type: volume ? "volume" : "brightness",
            priority: "normal",
            title: volume ? (Audio.muted ? "Volume · muted" : "Volume") : "Brightness",
            subtitle: ShellState.osdLabel,
            progress: ShellState.osdValue,
            persistent: true,
            sticky: true,
            announce: true
        });
    }
    Connections {
        target: NoticeStore
        function onNoticeRecorded(n) {
            root.notice(n);
        }
        function onNoticeForgotten(id) {
            service.remove("notification/" + id, false);
            service.routedNoticeIds = service.routedNoticeIds.filter(n => n !== id);
        }
    }
    Connections {
        target: UPower
        function onOnBatteryChanged() {
            root.syncPower(true);
        }
    }
    Connections {
        target: root.battery
        function onPercentageChanged() {
            root.syncPower(false);
        }
        function onStateChanged() {
            root.syncPower(false);
        }
    }
    Connections {
        target: PowerProfiles
        function onProfileChanged() {
            Controls.refresh();
        }
    }
    Connections {
        target: Controls
        function onDataChanged() {
            const name = Controls.data.profile;
            if (root.primed && name && root.lastProfile && root.lastProfile !== name)
                service.publish({
                    id: "power-profile",
                    type: "power",
                    title: "Power profile",
                    subtitle: name,
                    timeout: 3000,
                    remember: true
                });
            root.lastProfile = name;
            root.syncPower(false);
        }
    }
    Connections {
        target: SystemStats
        function onTemperatureChanged() {
            root.syncHealth();
        }
        function onDiskChanged() {
            root.syncHealth();
        }
    }
    Connections {
        target: Quickshell
        function onClipboardTextChanged() {
            if (root.primed && Config.saved.coreClipboard && !ShellState.locked)
                service.publish({
                    id: "clipboard",
                    type: "clipboard",
                    title: "Copied",
                    subtitle: "",
                    timeout: 1200
                });
        }
    }
    Connections {
        target: Config.saved
        function onCoreEnabledChanged() {
            if (service.enabled) {
                root.syncMedia(false);
                root.syncProbe();
                root.syncPower(false);
                root.syncPrivacy();
                root.syncHealth();
            }
        }
        function onCoreVolumeChanged() {
            if (!Config.saved.coreVolume)
                service.remove("osd", false);
        }
        function onCorePrivacyChanged() {
            privacyDelay.restart();
        }
        function onCoreMediaChanged() {
            root.syncMedia(false);
        }
        function onCoreTemperatureLimitChanged() {
            root.syncHealth();
        }
        function onCoreDiskLimitChanged() {
            root.syncHealth();
        }
        function onCoreNotificationsChanged() {
            if (!Config.saved.coreNotifications) {
                for (const r of service.model.rows.filter(a => a.type === "notification"))
                    service.remove(r.id, false);
                service.routedNoticeIds = [];
            }
        }
        function onCoreConnectionsChanged() {
            if (!Config.saved.coreConnections)
                for (const r of service.model.rows.filter(a => ["bluetooth", "network", "vpn"].includes(a.type)))
                    service.remove(r.id, false);
        }
        function onCorePowerChanged() {
            if (!Config.saved.corePower) {
                for (const r of service.model.rows.filter(a => a.type === "power"))
                    service.remove(r.id, false);
            } else
                root.syncPower(false);
        }
        function onCoreWarningsChanged() {
            if (!Config.saved.coreWarnings) {
                service.remove("thermal", false);
                service.remove("disk", false);
            } else
                root.syncHealth();
        }
    }
}
