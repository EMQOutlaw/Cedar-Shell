pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pam
import ".."
import "../components"

Scope {
    id: root
    readonly property string status: authController.status
    property bool hadSecureLock: false
    Component.onCompleted: { ShellState.nativeLockReady = true; refreshFingerprint(); }
    Component.onDestruction: { ShellState.nativeLockReady = false; ShellState.fingerprint = ""; }
    // Keep this ID distinct from TrailwatchView.auth: an implicit lock-surface
    // component otherwise resolves `auth: auth` to its own unset property.
    LockAuth {
        id: authController
        context: pam
        enabled: (ShellState.locked || ShellState.authTest) && !Config.testMode
        onClearInputs: root.clearInputs()
        onSucceeded: {
            if (!ShellState.locked) {
                authController.status = "Authentication succeeded. Your password works.";
                ShellState.authTests++;
                return;
            }
            root.release();
        }
    }
    function release() {
        root.stopFingerprint();
        if (root.hadSecureLock) ShellState.securedUnlocks++;
        lock.locked = false;
        ShellState.locked = false;
        ShellState.suspendAfterLock = false;
    }
    // Fingerprint: a second PAM conversation that needs no typed response, on
    // the same service Omarchy's lock uses. It starts only once the compositor
    // lock is secure, retries while locked, and is aborted on unlock. The
    // password path above is untouched by it.
    property bool fingerprintConfigured: false
    function startFingerprint() {
        if (!ShellState.locked || !ShellState.lockSecure || !fingerprintConfigured || Config.testMode) return;
        if (fingerprintPam.active) return;
        ShellState.fingerprint = "scanning";
        if (!fingerprintPam.start()) ShellState.fingerprint = "unavailable";
    }
    function stopFingerprint() {
        fingerprintRetry.stop();
        if (fingerprintPam.active) fingerprintPam.abort();
        ShellState.fingerprintMessage = "";
        ShellState.fingerprint = fingerprintConfigured ? "ready" : "";
    }
    PamContext {
        id: fingerprintPam
        config: "omarchy-lock-fingerprint"
        configDirectory: Config.pamDirectory
        onPamMessage: if (ShellState.locked && message) ShellState.fingerprintMessage = message
        onCompleted: result => {
            if (!ShellState.locked) return;
            if (result === PamResult.Success) { ShellState.fingerprint = "accepted"; ShellState.fingerprintMessage = ""; root.release(); return; }
            ShellState.fingerprint = "retry";
            fingerprintRetry.restart();
        }
        onError: error => {
            if (!ShellState.locked) return;
            ShellState.fingerprint = "retry";
            fingerprintRetry.restart();
        }
    }
    // fprintd ends a verification after its own attempt limit; a short pause
    // before the next one keeps the reader from being hammered.
    Timer { id: fingerprintRetry; interval: 600; onTriggered: root.startFingerprint() }
    ServiceRequest {
        id: fingerprintCheck
        script: "scripts/fingerprint.py"
        onResult: value => {
            root.fingerprintConfigured = value.configured === true;
            if (ShellState.fingerprint === "" || ShellState.fingerprint === "ready" || ShellState.fingerprint === "unavailable")
                ShellState.fingerprint = root.fingerprintConfigured ? "ready" : "";
            root.startFingerprint();
        }
        onFailed: message => { root.fingerprintConfigured = false; ShellState.fingerprint = ""; }
    }
    function refreshFingerprint() { if (!Config.testMode && !fingerprintCheck.running) fingerprintCheck.send({}); }
    PamContext {
        id: pam
        config: Config.pamService
        configDirectory: Config.pamDirectory
        // The default user is the current user; do not trust an inherited USER.
        onCompleted: result => authController.completed(result === PamResult.Success,
            result === PamResult.Error, result === PamResult.MaxTries)
        onError: error => {
            console.warn("CEDAR authentication error:", PamError.toString(error));
            authController.fail("Authentication unavailable: " + PamError.toString(error));
        }
    }
    IdleMonitor {
        enabled: !Config.testMode && !Config.authOnly && !Config.externalIdle && Config.idleLockSeconds > 0 && !ShellState.locked && !ShellState.authTest
        timeout: Config.idleLockSeconds
        respectInhibitors: true
        onIsIdleChanged: if (isIdle) ShellState.lock(false)
    }
    signal clearInputs()
    function submit(value) { authController.submit(value); }
    Connections {
        target: ShellState
        function onLockedChanged() {
            if (ShellState.locked && !Config.testMode) {
                root.hadSecureLock = false;
                lock.locked = true;
                root.clearInputs();
                root.refreshFingerprint();
            } else if (!ShellState.locked)
                root.stopFingerprint();
        }
    }
    PanelWindow {
        id: testWindow
        visible: ShellState.authTest && !ShellState.locked
        onVisibleChanged: if (visible) testPassword.forceActiveFocus()
        screen: Quickshell.screens.find(s => s.name === ShellState.preferredOutput()) || Quickshell.screens[0]
        implicitWidth: 480; implicitHeight: 260
        color: Theme.background
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "cedar-auth-test"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        contentItem.focus: true
        contentItem.Keys.onEscapePressed: ShellState.authTest = false
        ColumnLayout {
            anchors.fill: parent; anchors.margins: 24; spacing: 16
            GlowText { text: "TEST AUTHENTICATION"; color: Theme.teal }
            GlowText { text: authController.status; Layout.fillWidth: true; wrapMode: Text.WordWrap }
            TextField {
                id: testPassword
                Layout.fillWidth: true; echoMode: TextInput.Password; enabled: !authController.busy
                placeholderText: "Enter your password locally"
                onEnabledChanged: if (enabled && ShellState.authTest) forceActiveFocus()
                inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                onAccepted: { authController.submit(text); text = ""; }
                Component.onCompleted: forceActiveFocus()
                Connections { target: root; function onClearInputs() { testPassword.text = ""; } }
            }
            RowLayout {
                StationButton { text: "Test"; enabled: !authController.busy; onClicked: { authController.submit(testPassword.text); testPassword.text = ""; } }
                StationButton { text: "Close"; onClicked: ShellState.authTest = false }
            }
            GlowText { text: "This checks your password without locking the desktop."; font.pixelSize: 11; Layout.fillWidth: true; wrapMode: Text.WordWrap }
        }
    }
    WlSessionLock {
        id: lock
        onSecureChanged: {
            ShellState.lockSecure = secure;
            if (secure) { root.hadSecureLock = true; root.startFingerprint(); }
            if (secure && ShellState.suspendAfterLock) {
                ShellState.suspendAfterLock = false;
                Quickshell.execDetached(["systemctl", "suspend"]);
            }
        }
        WlSessionLockSurface {
            id: surface
            color: Theme.background // Always opaque; never a faux lock overlay.
            TrailwatchView {
                anchors.fill: parent
                auth: authController
                active: surface.visible && ShellState.locked
                responseVisible: pam.responseVisible
                onSubmitted: value => root.submit(value)
            }
        }
    }
}
