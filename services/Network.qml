pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import ".."
import "../components"
import "../components/StableRows.js" as StableRows

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
    readonly property alias networks: networkRows
    readonly property alias savedNetworks: savedRows
    ListModel {id:networkRows}
    ListModel {id:savedRows}
    onDataChanged: {
        StableRows.reconcile(networkRows,data.networks || [],"path");
        StableRows.reconcile(savedRows,(data.saved || []).filter(row=>row.type!=="loopback"),"path");
    }
    readonly property string label: data.available ? (data.status?.label || data.label) : "Network unavailable"
    readonly property string state: data.available ? (data.status?.state || "unknown") : "unavailable"
    readonly property string kind: data.status?.kind || "unknown"
    // An active access-point profile is a hotspot this computer is sharing.
    readonly property var hotspot: data.available ? ((data.saved || []).find(row => row.mode === "ap" && row.active) || null) : null
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
    // A short notice for the network chip after a change: {title, detail, tone, until}.
    // Tone is "ok", "lost" or "vpn". Core no longer carries network or VPN rows.
    property var notice: null
    function announce(title, detail, tone, duration) {
        const ms = duration || 4000;
        notice = { title: title, detail: detail || "", tone: tone || "ok", until: Date.now() + ms };
        noticeClear.interval = ms;
        noticeClear.restart();
    }
    Timer { id: noticeClear; onTriggered: root.notice = null }
    readonly property bool expanded: !ShellState.locked && ((ShellState.panel === "settings" && ShellState.settingsSection === "connections") || (Canopy.shown && ["network", "quick"].includes(Canopy.topic)))
    property string generation: ""
    property int sequence: 0
    property int retryDelay: 1000
    function refresh() { if (stream.running) stream.write(JSON.stringify({action:"refresh"})+"\n"); }
    onExpandedChanged: if (stream.running) stream.write(JSON.stringify({action:"expanded",value:expanded})+"\n")
    function run(request) {
        if (ShellState.locked || Config.testMode || action.running)
            return;
        error = "";
        action.send(request);
    }
    Process {
        id: stream
        command: ["python3", Quickshell.shellPath("scripts/connections.py"), "--watch"]
        stdinEnabled: true
        running: !Config.testMode
        onStarted: { root.generation="";root.sequence=0;write(JSON.stringify({action:"expanded",value:root.expanded})+"\n"); }
        stdout: SplitParser {
            onRead: line => {
                if (line.length>4*1024*1024) {stream.running=false;return;}
                try {
                    const event=JSON.parse(line);
                    if(event.schema!==1 || event.kind!=="snapshot" || (root.generation && event.generation!==root.generation) || event.sequence<=root.sequence)return;
                    root.generation=event.generation;root.sequence=event.sequence;root.retryDelay=1000;root.data=event.data;
                } catch(_) { root.error="Network status returned an invalid response."; }
            }
        }
        onExited: {
            root.data=Object.assign({},root.data,{available:false});
            if(!Config.testMode) retry.restart();
        }
    }
    Timer { id:retry;interval:root.retryDelay;onTriggered:{root.retryDelay=Math.min(60000,root.retryDelay*2);stream.running=true;} }
    ServiceRequest {
        id: action
        script: "scripts/connections.py"
        onResult: value => {
            // The subscribed stream owns snapshots; an older action result
            // must not replace a newer hotplug or connection revision.
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
}
