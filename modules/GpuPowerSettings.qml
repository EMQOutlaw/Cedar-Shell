import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower
import "../"
import "../components"
import "../services"

// Settings › Graphics & Power: the machine, as a quiet instrument. A live
// dossier card (GPU and CPU, real readings, sampled only while you watch),
// the system power profile (the Controls service owns it — this page shows
// it), and an honest word about the tuning knobs this session cannot reach.
// The Ryoku Graphics & Power pattern in CEDAR's vocabulary.
ColumnLayout {
    id: root
    property string highlightKey: ""
    property bool active: false
    readonly property bool wide: width > 980
    // Live telemetry is explicit and session-scoped (the Dictation meter's
    // rule): sampling runs only while this page is open, visible, unlocked,
    // toggled on, and outside a test environment.
    property bool live: false
    readonly property bool meterAllowed: active && visible && !ShellState.locked && !Config.testMode
    property var telemetry: null
    property string telemetryError: ""
    property double lastStamp: 0
    property int ageTick: 0  // re-evaluates the "Ns ago" stamp once a second
    spacing: Theme.spaceLg

    ServiceRequest {
        id: probe
        script: "scripts/gpu_power.py"
        onResult: result => {
            root.telemetry = result;
            root.telemetryError = "";
            root.lastStamp = Date.now();
        }
        onFailed: value => { root.telemetryError = value; }
    }
    Timer {
        id: sampler; interval: 2000; repeat: true; running: root.live && root.meterAllowed
        onTriggered: if (root.meterAllowed && root.live && !probe.busy) probe.send({action: "snapshot"})
    }
    onLiveChanged: if (live && meterAllowed) probe.send({action: "snapshot"})
    function refreshTelemetry() {
        if (meterAllowed && !probe.busy) probe.send({action: "snapshot"});
    }
    Connections {
        target: root
        function onMeterAllowedChanged() { if (root.live && root.meterAllowed) probe.send({action: "snapshot"}) }
    }

    component FCell: SettingsSection {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        Layout.minimumWidth: 0
    }
    // One instrument reading: a label, a mono value, and a slim bar under it.
    component Meter: ColumnLayout {
        id: meter
        property string label: ""
        property real value: -1          // -1: not reported
        property real max: 100
        property string unit: "%"
        property color fill: Theme.teal
        readonly property string reading: value < 0 ? "—"
            : (unit === "°C" ? Math.round(value) + "°C"
            : (unit === "W" ? value.toFixed(1) + " W"
            : (unit === "GHz" ? value.toFixed(2) + " GHz"
            : (unit === "MB" ? Math.round(value) + " MB"
            : (unit === "raw" ? value.toFixed(2)
            : Math.round(value) + "%")))))
        readonly property real fraction: value < 0 || max <= 0 ? 0 : Math.max(0, Math.min(1, value / max))
        spacing: 4
        Layout.fillWidth: true
        RowLayout {
            Layout.fillWidth: true; spacing: Theme.spaceSm
            GlowText { Layout.fillWidth: true; text: meter.label; color: Theme.muted; font.pixelSize: Theme.small }
            GlowText { text: meter.reading; color: Theme.text; font.family: Theme.dataFont; font.pixelSize: Theme.small }
        }
        Rectangle {
            Layout.fillWidth: true; implicitHeight: 6; radius: 3
            color: Qt.alpha(Theme.teal, .12)
            Rectangle {
                width: parent.width * meter.fraction; height: parent.height; radius: 3
                color: meter.fill
                Behavior on width { enabled: !Theme.reducedMotion; NumberAnimation { duration: Theme.transition } }
            }
        }
    }
    function tempTone(celsius) {
        if (celsius === null || celsius === undefined) return Theme.muted;
        if (celsius >= 80) return Theme.ember;
        if (celsius >= 65) return Theme.amber;
        return Theme.green;
    }

    // ── The machine: the live dossier ─────────────────────────────────────
    FCell {
        objectName: "gpuMachine"
        heading: "The machine"; caption: "Real readings from this computer's graphics and processor. Live sampling is opt-in and runs only while this page is open."
        badge: root.live && root.meterAllowed ? "LIVE" : "PAUSED"
        badgeColor: root.live && root.meterAllowed ? Theme.green : Theme.muted
        SettingRow {
            Layout.fillWidth: true; title: "Live telemetry"; objectName: "gpuLiveToggle"
            description: root.live ? "Sampling every two seconds while Settings is open and unlocked." : "Show live readings. They sample only while this page is open."
            StationToggle { Layout.fillWidth: true; accessibleLabel: "Live telemetry"; checked: root.live; enabled: root.meterAllowed || root.live; onToggled: value => root.live = value }
        }
        GlowText {
            visible: root.telemetryError !== ""
            text: root.telemetryError; color: Theme.amber; Layout.fillWidth: true; wrapMode: Text.WordWrap; font.pixelSize: Theme.small
        }
        GlowText {
            visible: root.telemetryError === "" && root.telemetry !== null
                     && root.telemetry.gpus.length === 0 && root.telemetry.cpu.threads === 0
            text: "No graphics telemetry source is available: nvidia-smi is absent and no kernel DRM card reports utilization. The readouts appear when a source exists."
            color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap; font.pixelSize: Theme.small
        }
        GlowText {
            // The PAUSED state must not show stale numbers without an age. A
            // one-second tick makes the age live: Date.now() alone is not a
            // reactive binding and the age would freeze on the first frame.
            visible: root.telemetry !== null && (!root.live || !root.meterAllowed)
            text: root.ageTick >= 0 ? "Last reading " + Math.max(0, Math.round((Date.now() - root.lastStamp) / 1000)) + " s ago." : ""
            color: Theme.muted; font.pixelSize: Theme.small; Layout.fillWidth: true

            Timer { interval: 1000; repeat: true; running: parent.visible; onTriggered: root.ageTick++ }
        }
        GlowText {
            visible: root.telemetryError === "" && root.telemetry === null && !root.live
            text: "Turn on Live telemetry to read the machine."; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap; font.pixelSize: Theme.small
        }
        SettingsSurface {
            visible: root.telemetry !== null
            Layout.fillWidth: true; padding: Theme.spaceMd
            ColumnLayout {
                width: parent.width; spacing: Theme.spaceMd
                // Per-GPU dossier, the hero of the card. The Repeater model is
                // the COUNT: the telemetry object is reassigned wholesale on
                // every sample, and an array model would destroy and rebuild
                // every card — the bars would never animate and the dot would
                // restart its breath each tick.
                Repeater {
                    model: root.telemetry ? root.telemetry.gpus.length : 0
                    ColumnLayout {
                        id: gpuCard
                        required property int index
                        readonly property var modelData: root.telemetry ? root.telemetry.gpus[gpuCard.index] : null
                        Layout.fillWidth: true; spacing: Theme.spaceSm
                        RowLayout {
                            Layout.fillWidth: true; spacing: Theme.spaceSm
                            Rectangle { width: 8; height: 8; radius: 4; color: root.live && root.meterAllowed ? Theme.green : Theme.muted; opacity: root.live && root.meterAllowed ? liveBreath.value : 1 }
                            Breath { id: liveBreath; running: root.live && root.meterAllowed && Motion.active; from: 1; to: .35; rise: 1400; fall: 1800 }
                            GlowText { Layout.fillWidth: true; text: gpuCard.modelData.name || "GPU"; color: Theme.text; font.family: Theme.labelFont; font.pixelSize: Math.round(18 * Theme.fontScale); elide: Text.ElideRight }
                            StatusPill { visible: gpuCard.modelData.pstate !== ""; text: gpuCard.modelData.pstate; tone: Theme.muted }
                        }
                        GridLayout {
                            Layout.fillWidth: true; columns: root.wide ? 2 : 1; columnSpacing: Theme.spaceLg; rowSpacing: Theme.spaceSm
                            Meter { label: "Utilization"; value: gpuCard.modelData.load ?? -1; fill: Theme.teal; Layout.fillWidth: true; Layout.minimumWidth: 0 }
                            Meter {
                                label: "Memory"
                                value: (gpuCard.modelData.memoryUsed !== null && gpuCard.modelData.memoryTotal > 0) ? gpuCard.modelData.memoryUsed : -1
                                max: gpuCard.modelData.memoryTotal > 0 ? gpuCard.modelData.memoryTotal : 1
                                unit: "MB"; fill: Theme.teal; Layout.fillWidth: true; Layout.minimumWidth: 0
                            }
                            Meter {
                                // No reported limit: the bar is text-only — a full
                                // bar would claim "near the limit" with no limit known.
                                label: "Power draw" + (gpuCard.modelData.powerLimit !== null ? " · limit " + Math.round(gpuCard.modelData.powerLimit) + " W" : " · limit unknown")
                                value: gpuCard.modelData.powerDraw ?? -1
                                max: gpuCard.modelData.powerLimit > 0 ? gpuCard.modelData.powerLimit : 0  // 0: fraction 0, text-only
                                unit: "W"
                                fill: gpuCard.modelData.powerLimit !== null && (gpuCard.modelData.powerDraw ?? 0) > 0.9 * gpuCard.modelData.powerLimit ? Theme.amber : Theme.green
                                Layout.fillWidth: true; Layout.minimumWidth: 0
                            }
                            Meter {
                                label: "Temperature"
                                value: gpuCard.modelData.temperature ?? -1
                                unit: "°C"; max: 100
                                fill: root.tempTone(gpuCard.modelData.temperature)
                                Layout.fillWidth: true; Layout.minimumWidth: 0
                            }
                        }
                        GlowText {
                            visible: gpuCard.modelData.source === "nvidia"
                            Layout.fillWidth: true; wrapMode: Text.WordWrap
                            text: "Clock " + (gpuCard.modelData.clock !== null ? Math.round(gpuCard.modelData.clock) + " MHz" : "—")
                                  + " · max " + (gpuCard.modelData.clockMax !== null ? Math.round(gpuCard.modelData.clockMax) + " MHz" : "—")
                                  + " · fan " + (gpuCard.modelData.fan !== null ? Math.round(gpuCard.modelData.fan) + "%" : "—")
                                  + " · persistence " + (gpuCard.modelData.persistence || "unknown")
                                  + " · driver tuning (power limit, clocks, persistence) writes through the privileged helper below" + (root.telemetry?.applyHelper === true ? "" : " — not installed yet, so this page reports them only") + "."
                            color: Theme.muted; font.family: Theme.dataFont; font.pixelSize: Theme.small
                        }
                    }
                }
                // The processor, one row of real state.
                ColumnLayout {
                    visible: (root.telemetry?.cpu?.threads ?? 0) > 0
                    Layout.fillWidth: true; spacing: Theme.spaceSm
                    RowLayout {
                        Layout.fillWidth: true; spacing: Theme.spaceSm
                        GlowText { Layout.fillWidth: true; text: root.telemetry?.cpu?.model || "CPU"; color: Theme.text; font.family: Theme.labelFont; font.pixelSize: Math.round(18 * Theme.fontScale); elide: Text.ElideRight }
                        StatusPill { text: (root.telemetry?.cpu?.threads ?? 0) + " threads"; tone: Theme.muted }
                    }
                    GridLayout {
                        Layout.fillWidth: true; columns: root.wide ? 2 : 1; columnSpacing: Theme.spaceLg; rowSpacing: Theme.spaceSm
                        Meter { label: "Clock average"; value: root.telemetry?.cpu?.freqAvg ?? -1; unit: "GHz"; max: 6; fill: Theme.teal; Layout.fillWidth: true; Layout.minimumWidth: 0 }
                        Meter { label: "Load · 1 min"; value: root.telemetry?.cpu?.load1 ?? -1; unit: "raw"; max: Math.max(1, root.telemetry?.cpu?.threads ?? 1); fill: (root.telemetry?.cpu?.load1 ?? 0) > 0.9 * (root.telemetry?.cpu?.threads ?? 1) ? Theme.amber : Theme.teal; Layout.fillWidth: true; Layout.minimumWidth: 0 }
                    }
                    GlowText {
                        Layout.fillWidth: true; wrapMode: Text.WordWrap
                        text: "Load " + (root.telemetry?.cpu?.load1 ?? "—") + " / " + (root.telemetry?.cpu?.load5 ?? "—") + " / " + (root.telemetry?.cpu?.load15 ?? "—")
                              + " over " + (root.telemetry?.cpu?.threads || "—") + " threads"
                              + " · governor " + (root.telemetry?.cpu?.governor || "—")
                              + " · energy preference " + (root.telemetry?.cpu?.epp || "—")
                              + " · governor and preference follow the power profile below; CEDAR does not write them directly."
                        color: Theme.muted; font.family: Theme.dataFont; font.pixelSize: Theme.small
                    }
                }
            }
        }
        GlowText {
            visible: root.live && root.meterAllowed && probe.busy && root.telemetry === null
            text: "Waiting for the first reading…"; color: Theme.muted; font.pixelSize: Theme.small; Layout.fillWidth: true
        }
    }

    // ── Power profile: the Controls service's own cards ───────────────────
    FCell {
        objectName: "powerProfile"
        heading: "Power profile"
        caption: "The system profile this computer's power service applies. The governor and energy preference above follow it."
        badge: UPower.displayDevice?.isPresent ? Math.round(UPower.displayDevice.percentage * 100) + "% · " + (UPower.onBattery ? "on battery" : "plugged in") : ""
        badgeColor: UPower.displayDevice?.isPresent && UPower.onBattery && UPower.displayDevice.percentage < .2 ? Theme.amber : Theme.green
        GridLayout {
            Layout.fillWidth: true; columns: root.width < 560 ? 1 : Math.max(1, Controls.data.profiles.length); columnSpacing: 10; rowSpacing: 10
            Repeater {
                model: Controls.data.profiles
                StationButton {
                    id: profile
                    required property string modelData
                    readonly property bool inUse: Controls.data.profile === modelData
                    readonly property var info: ({ "power-saver": { title: "Power saver", detail: "Longer battery, quieter and cooler." }, "balanced": { title: "Balanced", detail: "The everyday default." }, "performance": { title: "Performance", detail: "Full speed while plugged in." } })
                    Layout.fillWidth: true; implicitHeight: 76; checked: inUse; enabled: !Controls.busy
                    Accessible.name: (info[modelData]?.title || modelData) + (inUse ? ", in use" : "")
                    Accessible.role: Accessible.RadioButton
                    onClicked: if (!inUse) Controls.run({ action: "profile", value: modelData })
                    background: Rectangle { radius: 10; color: profile.inUse ? Qt.alpha(Theme.green, .07) : Theme.background; border.width: profile.inUse || profile.visualFocus ? 2 : 1; border.color: profile.inUse || profile.visualFocus ? Theme.green : profile.hovered ? Qt.alpha(Theme.teal, .45) : Qt.alpha(Theme.teal, .14) }
                    contentItem: ColumnLayout {
                        spacing: 3
                        Text { text: profile.info[profile.modelData]?.title || profile.modelData.replace("-", " "); textFormat: Text.PlainText; font.family: Theme.labelFont; font.pixelSize: Math.round(20 * Theme.fontScale); color: profile.inUse ? Theme.green : Theme.text }
                        Text { Layout.fillWidth: true; text: profile.info[profile.modelData]?.detail || ""; textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: 10; color: Theme.muted; wrapMode: Text.WordWrap }
                    }
                }
            }
        }
        GlowText { visible: !Controls.data.profiles.length; text: Controls.data.errors?.power || "System power profiles are unavailable on this device."; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap; font.pixelSize: Theme.small }
    }

    GlowText {
        visible: Controls.error !== ""; text: Controls.error; color: Theme.amber; Layout.fillWidth: true; wrapMode: Text.WordWrap; font.pixelSize: Theme.small
    }

    // ── Tuning · this session (NVIDIA only: the knobs are nvidia-smi's) ────
    FCell {
        id: tuning
        objectName: "gpuTuning"
        heading: "Tuning · this session"
        caption: "Runtime state the driver holds until reboot. Applying runs the privileged helper through pkexec — the authorization dialog is polkit's; CEDAR never holds a password. The wrapper re-validates every value as root."
        visible: tuning.gpu !== null
        readonly property var gpu: {
            const gpus = root.telemetry ? root.telemetry.gpus : [];
            for (let i = 0; i < gpus.length; i++)
                if (gpus[i].source === "nvidia" && gpus[i].uuid) return gpus[i];
            return null;
        }
        readonly property bool working: { Requests.generation; return Requests.isBusy("gpu-power") }
        readonly property var lastApplied: (root.telemetry?.program && root.telemetry.program.lastApplied && root.telemetry.program.lastApplied[gpu?.uuid]) || null
        // A reset is the driver no longer running what was last applied.
        readonly property bool resetDetected: lastApplied !== null && lastApplied.powerLimit !== undefined
            && gpu !== null && gpu.powerLimit !== null && Math.round(gpu.powerLimit) !== Math.round(lastApplied.powerLimit)
        property int limitW: -1
        property int persistenceWanted: 0
        property string message: ""
        property string applyError: ""
        readonly property bool draft: gpu !== null && limitW >= 0
            && (limitW !== Math.round(gpu.powerLimit ?? 0)
                || persistenceWanted !== (gpu.persistence === "enabled" ? 1 : 0))
        onGpuChanged: if (gpu && limitW < 0) {
            limitW = Math.round(gpu.powerLimit ?? 0);
            persistenceWanted = gpu.persistence === "enabled" ? 1 : 0;
        }
        function apply() {
            message = ""; applyError = "";
            Requests.send("gpu-power", "scripts/gpu_power.py",
                { action: "apply", gpu: { uuid: gpu.uuid, powerLimit: limitW, persistence: persistenceWanted } },
                tuning,
                result => {
                    message = "Tuning applied — the driver holds it until reboot.";
                    root.refreshTelemetry();
                },
                value => { applyError = value; }, 135000);
        }
        SettingRow {
            visible: root.telemetry?.applyHelper === false
            Layout.fillWidth: true; title: "Privileged helper not installed"
            description: "Driver tuning writes through /usr/local/sbin/cedar-gpu-apply — root-owned, re-validating every value as root, one file to delete to revoke. Until it exists this section reports state only."
            StationField { Layout.fillWidth: true; readOnly: true; text: "sudo install -m 755 -o root -g root ~/.config/quickshell/cedar/scripts/cedar-gpu-apply /usr/local/sbin/cedar-gpu-apply"; Accessible.name: "Helper install command" }
        }
        SettingRow {
            Layout.fillWidth: true
            title: "Power limit"
            description: root.telemetry?.applyHelper === false ? "Read-only until the privileged helper is installed."
                : "The card's power budget in watts, live until reboot. Driver range " + Math.round(tuning.gpu?.powerMinLimit ?? 0) + "–" + Math.round(tuning.gpu?.powerMaxLimit ?? 0) + " W."
            StationSlider {
                Layout.fillWidth: true
                enabled: root.telemetry?.applyHelper === true && !tuning.working && tuning.gpu !== null
                from: tuning.gpu?.powerMinLimit ?? 0; to: tuning.gpu?.powerMaxLimit ?? 1; stepSize: 1
                value: tuning.limitW < 0 ? (tuning.gpu?.powerLimit ?? 0) : tuning.limitW
                onMoved: tuning.limitW = Math.round(value)
                Accessible.name: "GPU power limit in watts"
            }
        }
        SettingRow {
            Layout.fillWidth: true; title: "Persistence mode"
            description: root.telemetry?.applyHelper === false ? "Read-only until the privileged helper is installed." : "Keeps the NVIDIA driver initialized when no client is using it. With it off, the driver drops runtime tuning — including your power limit — whenever the GPU fully idles."
            StationToggle { Layout.fillWidth: true; accessibleLabel: "Persistence mode"; enabled: root.telemetry?.applyHelper === true && !tuning.working; checked: tuning.persistenceWanted === 1; onToggled: value => tuning.persistenceWanted = value ? 1 : 0 }
        }
        // A driver re-initialization (idle teardown with persistence off, or
        // reboot) resets runtime tuning. The saved intent is remembered; the
        // difference is shown, never silently papered over.
        ColumnLayout {
            visible: tuning.resetDetected
            Layout.fillWidth: true; spacing: 4
            GlowText {
                Layout.fillWidth: true; wrapMode: Text.WordWrap; color: Theme.amber; font.pixelSize: Theme.small
                text: "The driver is no longer running your applied power limit (" + (tuning.lastApplied?.powerLimit ?? "?") + " W) — it reset on re-initialization. Applying here restores it."
            }
            StationButton { text: tuning.working ? "Working…" : "Re-apply " + (tuning.lastApplied?.powerLimit ?? "") + " W"; enabled: !tuning.working && root.telemetry?.applyHelper === true; onClicked: tuning.apply() }
        }
        RowLayout {
            Layout.fillWidth: true; spacing: Theme.spaceSm
            StationButton { text: tuning.working ? "Applying…" : "Apply tuning"; accent: Theme.green; enabled: tuning.draft && root.telemetry?.applyHelper === true && !tuning.working; onClicked: tuning.apply() }
            GlowText { visible: tuning.draft && !tuning.working; text: "Unsaved tuning — the driver still runs the values above."; color: Theme.teal; font.pixelSize: Theme.small }
        }
        GlowText { visible: tuning.message !== ""; text: tuning.message; color: Theme.green; Layout.fillWidth: true; wrapMode: Text.WordWrap; font.pixelSize: Theme.small }
        GlowText { visible: tuning.applyError !== ""; text: tuning.applyError; color: Theme.amber; Layout.fillWidth: true; wrapMode: Text.WordWrap; font.pixelSize: Theme.small }
    }

    // ── CPU profile programmer: per-power-profile cpufreq values ───────────
    FCell {
        id: programmer
        objectName: "cpuProgrammer"
        heading: "CPU profile programmer"
        caption: "Per-profile governor, energy preference and clock ceiling, written through the same privileged helper and saved for this machine. The power service switches profiles on its own — re-apply after it does, or CEDAR offers to."
        visible: root.telemetry !== null && root.telemetry.cpu.threads > 0 && root.telemetry.applyHelper === true
        readonly property bool working: { Requests.generation; return Requests.isBusy("gpu-power") }
        property string editing: Controls.data.profile || "balanced"
        property var drafts: ({})
        property string message: ""
        property string applyError: ""
        function values(profile) {
            if (drafts[profile]) return drafts[profile];
            const saved = (root.telemetry?.program?.profiles || {})[profile] || {};
            return { governor: saved.governor || root.telemetry?.cpu?.governor || "",
                     epp: saved.epp || root.telemetry?.cpu?.epp || "",
                     maxFreqKHz: saved.maxFreqKHz ?? null };
        }
        function setDraft(field, value) {
            const next = JSON.parse(JSON.stringify(drafts));
            const v = values(editing);
            (next[editing] = next[editing] || { governor: v.governor, epp: v.epp, maxFreqKHz: v.maxFreqKHz })[field] = value;
            drafts = next;
        }
        function save() {
            message = ""; applyError = "";
            const v = values(editing);
            const cpuPayload = {};
            if (v.governor) cpuPayload.governor = v.governor;
            if (v.epp) cpuPayload.epp = v.epp;
            if (v.maxFreqKHz) cpuPayload.maxFreqKHz = Math.round(v.maxFreqKHz);
            const profiles = JSON.parse(JSON.stringify(root.telemetry?.program?.profiles || {}));
            (profiles[editing] = profiles[editing] || {}).governor = v.governor;
            profiles[editing].epp = v.epp;
            profiles[editing].maxFreqKHz = v.maxFreqKHz;
            // Save first, then apply the same values: the reply of the save
            // carries the fresh program state, and only a SAVED profile is
            // one this page can honestly call "programmed".
            Requests.send("gpu-power", "scripts/gpu_power.py",
                { action: "program-save", profiles: profiles }, programmer,
                result => {
                    if (root.telemetry) root.telemetry = Object.assign({}, root.telemetry, { program: result });
                    Requests.send("gpu-power", "scripts/gpu_power.py",
                        { action: "apply", cpu: cpuPayload }, programmer,
                        applyResult => {
                            message = "Saved and applied to the " + editing + " profile.";
                            if (root.telemetry) root.telemetry = Object.assign({}, root.telemetry, { program: result });
                            root.refreshTelemetry();
                        },
                        value => { applyError = "Saved, but the apply failed: " + value; root.refreshTelemetry(); }, 135000);
                },
                value => { applyError = value; }, 135000);
        }
        SettingRow {
            Layout.fillWidth: true; title: "Editing profile"; description: "Which profile you are programming — not necessarily the live one."
            ChoiceChips { Layout.fillWidth: true; accessibleLabel: "Profile to edit"; enabled: !programmer.working; options: Controls.data.profiles.map(p => ({ value: p, label: p })); current: programmer.editing; onChosen: value => programmer.editing = value }
        }
        SettingRow {
            Layout.fillWidth: true; title: "Governor"
            ChoiceChips { Layout.fillWidth: true; accessibleLabel: "CPU governor"; enabled: !programmer.working; options: (root.telemetry?.cpu?.governors || []).map(g => ({ value: g, label: g })); current: programmer.values(programmer.editing).governor || (root.telemetry?.cpu?.governors || [])[0] || "performance"; onChosen: value => programmer.setDraft("governor", value) }
        }
        SettingRow {
            Layout.fillWidth: true; title: "Energy preference"
            ChoiceChips { Layout.fillWidth: true; accessibleLabel: "Energy preference"; enabled: !programmer.working; options: (root.telemetry?.cpu?.preferences || []).map(p => ({ value: p, label: p })); current: programmer.values(programmer.editing).epp || (root.telemetry?.cpu?.preferences || [])[0] || "default"; onChosen: value => programmer.setDraft("epp", value) }
        }
        SettingRow {
            Layout.fillWidth: true; title: "Clock ceiling"
            // The slider is enabled only when the kernel reported a real range:
            // a magic default would claim a ceiling this machine may not have.
            readonly property var range: (root.telemetry?.cpu?.freqMinKHz && root.telemetry?.cpu?.freqMaxKHz)
                ? { min: root.telemetry.cpu.freqMinKHz / 1000, max: root.telemetry.cpu.freqMaxKHz / 1000 } : null
            description: !range ? "The kernel did not report a clock range, so the ceiling is not editable here."
                : (programmer.values(programmer.editing).maxFreqKHz ? (programmer.values(programmer.editing).maxFreqKHz / 1000000).toFixed(2) + " GHz maximum for this profile." : "The hardware ceiling applies.")
            StationSlider {
                Layout.fillWidth: true
                enabled: !programmer.working && parent.range !== null
                from: parent.range ? parent.range.min : 0
                to: parent.range ? parent.range.max : 1
                stepSize: 25000
                value: {
                    const kHz = programmer.values(programmer.editing).maxFreqKHz;
                    if (kHz && parent.range) return Math.min(kHz / 1000, parent.range.max);
                    return parent.range ? parent.range.max : 0;
                }
                onMoved: programmer.setDraft("maxFreqKHz", Math.round(value) * 1000)
                Accessible.name: "Clock ceiling in GHz for the " + programmer.editing + " profile"
            }
        }
        RowLayout {
            Layout.fillWidth: true; spacing: Theme.spaceSm
            StationButton { text: programmer.working ? "Working…" : "Save & apply for “" + programmer.editing + "”"; accent: Theme.green; enabled: !programmer.working && root.telemetry?.applyHelper === true; onClicked: programmer.save() }
            StatusPill { text: (root.telemetry?.program?.profiles || {})[programmer.editing] ? "saved" : "unsaved"; tone: (root.telemetry?.program?.profiles || {})[programmer.editing] ? Theme.green : Theme.muted }
        }
        GlowText { visible: programmer.message !== ""; text: programmer.message; color: Theme.green; Layout.fillWidth: true; wrapMode: Text.WordWrap; font.pixelSize: Theme.small }
        GlowText { visible: programmer.applyError !== ""; text: programmer.applyError; color: Theme.amber; Layout.fillWidth: true; wrapMode: Text.WordWrap; font.pixelSize: Theme.small }
    }
    GlowText {
        text: "Idle, Gaming Mode and screen brightness live on Power & Idle."
        color: Theme.muted; font.pixelSize: Theme.small; Layout.fillWidth: true; wrapMode: Text.WordWrap
    }
}
