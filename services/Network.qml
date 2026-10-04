pragma Singleton
import QtQuick
import Quickshell
import ".."
import "../components"

Singleton {
    id: root
    property var data: ({
            available: false,
            enabled: false,
            hardware: false,
            devices: [],
            networks: [],
            saved: [],
            label: "NET …"
        })
    readonly property string label: data.available ? (data.status?.label || data.label) : "Network unavailable"
    readonly property string state: data.available ? (data.status?.state || "unknown") : "unavailable"
    readonly property string kind: data.status?.kind || "unknown"
    readonly property bool vpnActive: data.available && (data.status?.vpns?.length || 0) > 0
    readonly property string statusDescription: label + (vpnActive ? " · VPN active" : "") + " · " + ({
            unknown: "Internet access not checked",
            none: "No internet access reported",
            portal: "Network sign-in required",
            limited: "Limited internet access",
            verified: "Internet access verified"
        }[data.available ? data.status?.internet || "unknown" : "unknown"])
    readonly property string glyph: state === "connecting" ? "󰔟" : state === "disconnected" ? "󰖪" : state !== "connected" ? "?" : kind === "wifi" ? "󰖩" : kind === "wired" ? "󰈀" : kind === "mobile" ? "󰏲" : "?"
    readonly property string fallbackGlyph: state === "connecting" ? "…" : state === "disconnected" ? "×" : state !== "connected" ? "?" : ({
            wifi: "W",
            wired: "E",
            mobile: "M"
        }[kind] || "?")
    property string error: ""
    readonly property bool busy: action.running
    readonly property bool expanded: ["control", "settings", "canopy"].includes(ShellState.panel)
    function refresh() {
        if (!poll.running && !action.running && !Config.testMode)
            poll.send({
                action: "snapshot"
            });
    }
    function run(request) {
        if (ShellState.locked || Config.testMode || action.running)
            return;
        error = "";
        action.send(request);
    }
    ServiceRequest {
        id: poll
        script: "scripts/connections.py"
        onResult: value => {
            root.data = value;
        }
        onFailed: message => {
            root.error = message;
            root.data = Object.assign({}, root.data, {
                available: false,
                label: "NET unavailable"
            });
        }
    }
    ServiceRequest {
        id: action
        script: "scripts/connections.py"
        onResult: value => {
            root.data = value;
            root.error = "";
            recheck.restart();
        }
        onFailed: message => {
            root.error = message;
            recheck.restart();
        }
    }
    Timer {
        id: recheck
        interval: 1500
        onTriggered: root.refresh()
    }
    Timer {
        interval: root.expanded ? 5000 : 15000
        running: !Config.testMode
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
    onExpandedChanged: if (expanded)
        refresh()
}
