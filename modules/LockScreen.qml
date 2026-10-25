pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pam
import ".."
import "../components"
import "../services"

Scope {
    id: root
    readonly property string status: authController.status
    property bool hadSecureLock: false
    property bool fingerprintAvailable: false
    property string fingerprintStatus: ""
    readonly property bool fingerprintEnabled: ShellState.locked && lock.secure && !Config.testMode && fingerprintAvailable
    function finishUnlock() {
        if (!ShellState.locked || !lock.secure) return;
        if (root.hadSecureLock) ShellState.securedUnlocks++;
        // Disable both conversations before releasing the secure surface.
        ShellState.locked = false;
        lock.locked = false;
        ShellState.suspendAfterLock = false;
    }
    function startFingerprint() {
        if (!fingerprintEnabled || fingerprintPam.active) return;
        fingerprintStatus = "Touch the fingerprint sensor or enter your password";
        if (!fingerprintPam.start()) fingerprintStatus = "Fingerprint unavailable · enter your password";
    }
    onFingerprintEnabledChanged: {
        fingerprintRetry.stop();
        if (fingerprintEnabled) startFingerprint();
        else {
            if (fingerprintPam.active) fingerprintPam.abort();
            fingerprintStatus = "";
        }
    }
    ServiceRequest {
        id: fingerprintCheck
        script: "scripts/fingerprint_status.py"
        onResult: value => root.fingerprintAvailable = value.available === true
        onFailed: root.fingerprintAvailable = false
    }
    PamContext {
        id: fingerprintPam
        config: "omarchy-lock-fingerprint"
        configDirectory: Config.pamDirectory
        onCompleted: result => {
            if (!root.fingerprintEnabled) return;
            if (result === PamResult.Success) root.finishUnlock();
            else {
                root.fingerprintStatus = "Fingerprint not accepted · try again or enter your password";
                fingerprintRetry.restart();
            }
        }
        onError: {
            root.fingerprintStatus = "Fingerprint unavailable · enter your password";
            if (root.fingerprintEnabled) fingerprintRetry.restart();
        }
        onPamMessage: {
            if (root.fingerprintEnabled && message) root.fingerprintStatus = message;
        }
    }
    Timer {
        id: fingerprintRetry
        interval: 1500
        onTriggered: root.startFingerprint()
    }
    Component.onCompleted: ShellState.nativeLockReady = true
    Component.onDestruction: ShellState.nativeLockReady = false
    // Keep this ID distinct from TrailwatchView.auth: an implicit lock-surface
    // component otherwise resolves `auth: auth` to its own unset property.
    LockAuth {
        id: authController
        property string fingerprintHint: root.fingerprintStatus
        context: pam
        enabled: (ShellState.locked || ShellState.authTest) && !Config.testMode
        onClearInputs: root.clearInputs()
        onSucceeded: {
            if (!ShellState.locked) {
                authController.status = "Authentication succeeded. Your password works.";
                ShellState.authTests++;
                return;
            }
            root.finishUnlock();
        }
    }
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
        enabled: !Config.testMode && !Config.authOnly && !Config.externalIdle && Config.idleLockSeconds > 0 && !ShellState.locked && !ShellState.authTest && !Gaming.inhibitIdle && !Awake.held
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
                // Native locking can use the installed fingerprint PAM service
                // even when the desktop is running without an Omarchy adapter.
                fingerprintCheck.send({});
                lock.locked = true;
                root.clearInputs();
            }
        }
    }
    PanelWindow {
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
            if (secure) root.hadSecureLock = true;
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
