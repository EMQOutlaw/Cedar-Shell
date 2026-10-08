pragma Singleton
import QtQuick
import Quickshell
import ".."

Singleton {
    id: root
    // In-memory snapshots only: never retain a destroyed Notification object.
    property var history: []
    property var live: []
    signal noticeRecorded(var notice)
    signal noticeForgotten(int id)
    readonly property var popups: live.filter(n => Config.saved.notificationsEnabled && !(CoreService.available && CoreService.routedNoticeIds.includes(n.id)) && (n.urgency === 2 || !Config.saved.doNotDisturb || Focus.allows(n.appName)))
    function record(n) {
        const entry = {id: n.id, app: n.appName, summary: n.summary, body: n.body, timestamp: Date.now(), critical: n.urgency === 2};
        history = [entry].concat(history.filter(e => e.id !== n.id)).slice(0, 100);
        // Route before publishing the popup list, avoiding a one-frame duplicate.
        noticeRecorded(n);
        live = live.filter(e => e.id !== n.id).concat([n]);
    }
    function forget(id) { live = live.filter(e => e.id !== id); noticeForgotten(id); }
    function dismiss(id) { const n = live.find(e => e.id === id); if (n) n.dismiss(); }
    function clear() { history = []; }
}
