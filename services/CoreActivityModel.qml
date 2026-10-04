import QtQuick
import Quickshell
import "../components/core/Activities.js" as Policy

Scope {
    id: root
    property var state: Policy.create()
    property double now: Date.now()
    property string heldId: ""
    property string selectedId: ""
    readonly property var rows: state.rows
    readonly property var history: state.history
    readonly property var ranked: Policy.ranked(state, now, heldId)
    readonly property var foreground: Policy.foreground(state, now, heldId, selectedId)
    function publish(event) {
        now = Date.now();
        state = Policy.publish(state, event, now);
    }
    function remove(id, remember = true) {
        state = Policy.remove(state, id, Date.now(), remember);
        if (selectedId === id)
            selectedId = "";
    }
    function hold(id) {
        if (heldId === id)
            return;
        if (heldId && heldId !== id) {
            const row = rows.find(r => r.id === heldId);
            if (row && !row.persistent)
                state = Policy.publish(state, Object.assign({}, row, {
                    announce: false
                }), Date.now());
        }
        heldId = id;
    }
    function clearHistory() {
        state = Object.assign({}, state, {
            history: []
        });
    }
    // Settled persistent activities need no polling. Only expire live deadlines.
    Timer {
        interval: 250
        repeat: true
        running: root.rows.some(r => r.attentionUntil > root.now || (r.expiresAt > 0 && r.id !== root.heldId))
        onTriggered: {
            root.now = Date.now();
            root.state = Policy.expire(root.state, root.now, root.heldId);
        }
    }
}
