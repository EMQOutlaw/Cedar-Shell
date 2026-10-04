import QtQuick
import Quickshell
import Quickshell.Io

// No window or authentication object. Preserve the old keyboard IPC contracts.
Item {
    id: root
    readonly property bool barHidden: true
    readonly property int barSize: 0
    property var barConfig: ({})
    property bool forwarding: false
    function send(target, method, args = []) {
        const source = String(barConfig.cedarShellPath || "");
        if (forwarding && source.startsWith("/"))
            Quickshell.execDetached(["qs", "ipc", "-p", source, "call", target, method, ...args]);
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
