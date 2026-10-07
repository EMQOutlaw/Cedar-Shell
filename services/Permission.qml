pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Polkit
import ".."

// CEDAR is the session's polkit authentication agent. When a program asks
// for a privileged action through pkexec or polkit (Shield's firewall,
// Avahi, a package manager), polkit hands the request here and the
// PermissionPrompt window asks the user. The password goes from the field to
// polkit's helper over D-Bus inside this process; it is never logged,
// echoed, or placed in a command line. Locking the session cancels any
// request. Not registered in test mode, or under the Omarchy adapter, where
// the Omarchy shell owns the agent.
Singleton {
    id: root
    readonly property bool enabled: !Config.testMode && Config.stage >= 3 && !Config.omarchyIntegration
    readonly property bool registered: agent.isRegistered
    property bool active: false
    property string message: ""
    property string prompt: ""
    property string supplementary: ""
    property bool supplementaryIsError: false
    property bool responseRequired: false
    property bool responseVisible: false
    property bool failed: false
    property string identity: Quickshell.env("USER") || ""
    property int attempts: 0

    function sync() {
        const flow = agent.flow;
        if (!flow) { active = false; return; }
        message = String(flow.message || "A program needs permission to continue.");
        prompt = String(flow.inputPrompt || "Password");
        supplementary = String(flow.supplementaryMessage || "");
        supplementaryIsError = !!flow.supplementaryIsError;
        responseRequired = !!flow.isResponseRequired;
        responseVisible = !!flow.responseVisible;
        failed = !!flow.failed;
        try { identity = String(flow.selectedIdentity?.name || flow.selectedIdentity || identity); } catch (_) {}
        active = agent.isActive && !ShellState.locked;
    }
    function submit(secret) {
        const flow = agent.flow;
        if (!flow || !flow.isResponseRequired) return;
        attempts += 1;
        flow.submit(secret);
    }
    function cancel() {
        const flow = agent.flow;
        if (flow) flow.cancelAuthenticationRequest();
        active = false; attempts = 0;
    }
    PolkitAgent {
        id: agent
        path: "/org/cedar/PolkitAgent"
        onAuthenticationRequestStarted: { root.attempts = 0; root.sync(); }
        onIsActiveChanged: root.sync()
        onFlowChanged: root.sync()
    }
    Connections {
        target: agent.flow
        function onInputPromptChanged() { root.sync(); }
        function onSupplementaryMessageChanged() { root.sync(); }
        function onSupplementaryIsErrorChanged() { root.sync(); }
        function onIsResponseRequiredChanged() { root.sync(); }
        function onResponseVisibleChanged() { root.sync(); }
        function onFailedChanged() { root.sync(); }
        function onSelectedIdentityChanged() { root.sync(); }
        function onIsCompletedChanged() { root.sync(); }
        function onAuthenticationSucceeded() { root.active = false; root.attempts = 0; }
        function onAuthenticationRequestCancelled() { root.active = false; root.attempts = 0; }
    }
    Connections { target: ShellState; function onLockedChanged() { if (ShellState.locked && root.active) root.cancel(); } }
}
