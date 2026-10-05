import QtQuick
import Quickshell
import Quickshell.Io

// No window or authentication object. Preserve the old keyboard IPC contracts.
// With `cedarLock: "trailwatch"` in the bar configuration, this bar also
// answers Omarchy's `lock` IPC from CEDAR's published lock state, so idle, lid,
// sleep and keyboard lock requests reach Trailwatch without rebinding anything.
Item {
    id: root
    readonly property bool barHidden: true
    readonly property int barSize: 0
    property var barConfig: ({})
    property bool forwarding: false
    readonly property string cedarShell: String(barConfig.cedarShellPath || "")
    readonly property bool trailwatch: String(barConfig.cedarLock || "") === "trailwatch" && cedarShell.startsWith("/")
    readonly property string lockStatePath: String(barConfig.cedarLockState || "")
    property var lockState: ({})
    property double now: Date.now()
    property double lockRequestedAt: 0
    // CEDAR writes a heartbeat every 5 s; three missed beats mean no locker.
    readonly property bool lockFresh: trailwatch && Number(lockState.updated) > 0 && now - Number(lockState.updated) < 15000
    readonly property bool lockReady: lockFresh && lockState.ready === true
    readonly property bool lockLocked: lockFresh && lockState.locked === true
    readonly property bool lockSecure: lockFresh && lockState.secure === true
    readonly property bool lockRequested: lockLocked || (lockRequestedAt > 0 && now - lockRequestedAt < 3000)
    function send(target, method, args = []) {
        if (forwarding && cedarShell.startsWith("/"))
            Quickshell.execDetached(["qs", "ipc", "-p", cedarShell, "call", target, method, ...args]);
    }
    function lockRequest(): string {
        if (!root.lockReady) return "missing-pam";
        if (root.lockLocked) return "ok";
        root.lockRequestedAt = Date.now(); root.now = root.lockRequestedAt;
        Quickshell.execDetached(["qs", "ipc", "-p", root.cedarShell, "call", "lock", "lock"]);
        return "ok";
    }
    function lockedText(): string { return root.lockLocked ? "true" : "false"; }
    function lockStatus(): string {
        return JSON.stringify({
            locked: root.lockLocked, requested: root.lockRequested, pending: root.lockRequested && !root.lockLocked,
            sessionLocked: root.lockLocked, secure: root.lockSecure, realScreens: Quickshell.screens.length,
            passwordPam: root.lockReady, fingerprint: false, authenticating: false,
            lastEvent: root.lockFresh ? String(root.lockState.event || "") : "stale",
            lastEventAt: root.lockFresh ? new Date(Number(root.lockState.updated)).toISOString() : "", provider: "cedar"
        });
    }
    FileView {
        path: root.trailwatch ? root.lockStatePath : ""
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { try { root.lockState = JSON.parse(text()) || ({}); } catch (_) { root.lockState = ({}); } root.now = Date.now(); }
        onLoadFailed: root.lockState = ({})
    }
    Timer { interval: 1000; running: root.trailwatch; repeat: true; onTriggered: root.now = Date.now() }
    LazyLoader {
        active: root.trailwatch
        component: IpcHandler {
            target: "lock"
            function lock(): string { return root.lockRequest(); }
            function isLocked(): string { return root.lockedText(); }
            function status(): string { return root.lockStatus(); }
        }
    }
    IpcHandler {
        target: "cedarBridge"
        function enable(): bool { root.forwarding = true; return true; }
        function disable(): bool { root.forwarding = false; return true; }
    }
    IpcHandler {
        enabled: root.forwarding
        target: "notifications"
        function dismissOne(): void { root.send("notifications", "dismissOne"); }
        function dismissAll(): void { root.send("notifications", "dismissAll"); }
        function invokeLast(): void { root.send("notifications", "invokeLast"); }
        function showHistory(): void { root.send("notifications", "toggle"); }
    }
    IpcHandler {
        enabled: root.forwarding
        target: "osd"
        function show(payload: string): string { root.send("osd", "fromOmarchy", [payload]); return "ok"; }
    }
}
