import QtQuick
import Quickshell
import Quickshell.Io
import "modules"
import "services"
ShellRoot {
    NotificationServer {}
    IpcHandler {
        target: "test"
        function count(): int { return NoticeStore.history.length; }
        function live(): int { return NoticeStore.live.length; }
        function body(): string { return NoticeStore.history[0]?.body || ""; }
        function dismiss(): void { if (NoticeStore.live.length) NoticeStore.live[0].dismiss(); }
        function quit(): void { Qt.quit(); }
    }
}
