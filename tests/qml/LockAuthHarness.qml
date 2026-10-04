import QtQuick
import Quickshell
import "../../components"
ShellRoot {
    id: root
    property int successes: 0
    function check(ok, name) { if (!ok) { console.error("FAIL:", name); Qt.exit(1); } }
    QtObject {
        id: fake
        property bool active: false
        property bool responseRequired: false
        property string message: ""
        property int responses: 0
        property bool allowStart: true
        signal pamMessage()
        function start() { active = allowStart; return active; }
        function abort() { active = false; responseRequired = false; }
        function respond(response) { root.check(response === "test-response", "queued response integrity"); responses++; responseRequired = false; }
    }
    LockAuth { id: auth; context: fake; enabled: true; onSucceeded: root.successes++ }
    Timer {
        interval: 100; running: true
        onTriggered: {
            auth.submit("test-response");
            root.check(fake.active && fake.responses === 0 && auth.hasPending, "first submit queued before asynchronous prompt");
            fake.responseRequired = true;
            root.check(fake.responses === 1 && auth.pendingResponse === "" && !auth.hasPending, "prompt consumes response once");
            fake.pamMessage();
            root.check(fake.responses === 1, "duplicate signals do not resubmit");
            fake.active = false; auth.completed(false,false,false);
            root.check(root.successes === 0, "failure cannot unlock");
            auth.submit("test-response"); fake.responseRequired = true; fake.active = false;
            auth.completed(true,false,false);
            root.check(root.successes === 1 && auth.pendingResponse === "", "retry succeeds and clears secret");
            fake.allowStart = false; auth.submit("test-response");
            root.check(auth.hadError && auth.pendingResponse === "", "startup failure clears secret");
            auth.completed(false,true,false);
            root.check(auth.status.indexOf("Unable to start") === 0, "completion preserves useful error");
            auth.enabled = false; auth.completed(true,false,false);
            root.check(root.successes === 1, "disabled authentication cannot unlock");
            console.log("PASS: lock authentication state machine"); Qt.quit();
        }
    }
}
