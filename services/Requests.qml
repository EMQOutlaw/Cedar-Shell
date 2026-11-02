pragma Singleton
import QtQuick
import Quickshell
import "../components"

// Page-independent requests. A ServiceRequest declared inside a page is that
// page's child and is killed when the page unloads (a Settings section swap,
// a Canopy drop closing) - mid-write if the helper was applying something.
// Requests owns one ServiceRequest per named channel for the life of the
// shell, so the helper always finishes; only the delivery depends on the
// caller still existing.
//
// Callbacks travel with the request, not the channel: each send passes its
// caller as ServiceRequest's tag, which moves with the payload through start,
// queueing (latest wins) and a timeout drop, so a reply always reaches the
// caller whose payload produced it. A caller replaced in the queue before its
// request started is never answered, exactly as its payload never runs. A
// caller destroyed in the meantime is skipped; its closures are dropped, never
// run against a dead page. Pattern adapted from dux-shell's Proc.qml (MIT).
Singleton {
    id: root
    // Advances whenever any channel starts or settles; bind busy state as
    // `{ Requests.generation; return Requests.isBusy("name"); }`.
    property int generation: 0
    property var channels: ({})

    function send(name, script, value, owner, onResult, onFailed, timeoutMs) {
        let c = channels[name];
        if (!c) {
            const request = requestComponent.createObject(root, { script: script, timeoutMs: timeoutMs || 45000 });
            c = { script: script, request: request };
            channels[name] = c;
            request.result.connect(data => root.deliver(name, true, data));
            request.failed.connect(message => root.deliver(name, false, message));
            request.busyChanged.connect(() => root.generation++);
        } else if (c.script !== script) {
            console.warn("Requests: channel " + name + " belongs to " + c.script + ", not " + script);
            return false;
        }
        if (timeoutMs)
            c.request.timeoutMs = timeoutMs;
        return c.request.send(value, { owner: owner, onResult: onResult, onFailed: onFailed });
    }

    function isBusy(name) {
        const c = channels[name];
        return !!(c && c.request.busy);
    }

    // Destroyed QObject wrappers stay truthy; Qt.isQtObject is the reliable liveness probe.
    function alive(owner) { return !owner || Qt.isQtObject(owner); }

    function deliver(name, ok, payload) {
        const c = channels[name];
        if (!c)
            return;
        // Read synchronously: `tag` is the emitting request's own caller.
        const slot = c.request.tag;
        if (!slot || !root.alive(slot.owner))
            return;
        const fn = ok ? slot.onResult : slot.onFailed;
        if (typeof fn !== "function")
            return;
        try {
            fn(payload);
        } catch (e) {
            console.warn("Requests: " + name + " callback failed: " + e);
        }
    }

    Component {
        id: requestComponent
        ServiceRequest { script: "" }
    }
}
