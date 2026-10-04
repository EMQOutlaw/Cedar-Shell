import QtQuick

// Owns one conversation. Never log responses or retain them after completion.
QtObject {
    id: root
    required property var context
    property bool enabled: false
    property string status: "Enter your password"
    property string pendingResponse: ""
    property bool hasPending: false
    property bool hadError: false
    readonly property bool busy: !!context && context.active && (!context.responseRequired || hasPending)
    signal succeeded()
    signal clearInputs()

    function reset() {
        pendingResponse = ""; hasPending = false; hadError = false;
        watchdog.stop();
        if (context && context.active) context.abort();
        clearInputs();
        status = "Enter your password";
    }
    onEnabledChanged: reset()
    function submit(value) {
        if (!enabled || !context || busy || !value.length) return;
        pendingResponse = value; hasPending = true; hadError = false;
        status = "Checking…";
        clearInputs();
        watchdog.restart();
        if (!context.active && !context.start()) {
            fail("Unable to start authentication. Check the system PAM service.");
            return;
        }
        respond();
    }
    function respond() {
        if (!enabled || !context.active || !context.responseRequired || !hasPending) return;
        const response = pendingResponse;
        pendingResponse = ""; hasPending = false;
        context.respond(response);
    }
    function fail(message) {
        pendingResponse = ""; hasPending = false; hadError = true;
        watchdog.stop(); clearInputs(); status = message;
    }
    property Timer watchdog: Timer {
        interval: 30000
        onTriggered: {
            if (root.context.active) root.context.abort();
            root.fail("Authentication timed out. Try again.");
        }
    }
    // Result values are supplied by the caller to keep this controller testable.
    function completed(success, infrastructureError, maxTries) {
        pendingResponse = ""; hasPending = false;
        watchdog.stop(); clearInputs();
        if (!enabled) return;
        if (success) { succeeded(); return; }
        if (hadError) return;
        status = infrastructureError ? "Authentication unavailable. Check the system PAM service."
               : maxTries ? "Too many attempts. Wait before trying again."
               : "Password not accepted. Try again.";
    }
    property Connections messages: Connections {
        target: root.context
        function onResponseRequiredChanged() { root.respond(); }
        function onPamMessage() {
            if (!root.enabled) return;
            if (root.context.message) root.status = root.context.message;
            root.respond();
        }
    }
}
