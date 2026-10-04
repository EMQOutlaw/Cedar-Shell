import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pam
import "components"

// An ordinary window: no session lock, notifications, idle monitor or desktop.
ShellRoot {
    settings.watchFiles: false
    PamContext {
        id: pam
        config: Config.pamService
        configDirectory: Config.pamDirectory
        onCompleted: result => auth.completed(result === PamResult.Success, result === PamResult.Error, result === PamResult.MaxTries)
        onError: error => auth.fail("Authentication unavailable: " + PamError.toString(error))
    }
    LockAuth {
        id: auth
        context: pam
        enabled: true
        onClearInputs: password.text = ""
        onSucceeded: { console.log("CEDAR_AUTH_OK"); Qt.quit(); }
    }
    FloatingWindow {
        title: "CEDAR — Test Authentication"
        visible: true
        color: Theme.background
        implicitWidth: 500
        implicitHeight: 300
        onVisibleChanged: if (!visible) Qt.quit()
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24
            GlowText { text: "Before enabling Trailwatch"; color: Theme.green; font.pixelSize: Theme.title }
            GlowText { text: "Test your password locally. This window does not lock the desktop."; Layout.fillWidth: true; wrapMode: Text.WordWrap }
            TextField {
                id: password
                Layout.fillWidth: true
                echoMode: TextInput.Password
                enabled: !auth.busy
                placeholderText: "Your login password"
                Accessible.name: "Login password for local authentication test"
                inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
                onAccepted: { auth.submit(text); text = ""; }
                Component.onCompleted: forceActiveFocus()
            }
            GlowText { text: auth.status; Layout.fillWidth: true; wrapMode: Text.WordWrap }
            RowLayout {
                StationButton { text: "Test"; enabled: !auth.busy; onClicked: { auth.submit(password.text); password.text = ""; } }
                StationButton { text: "Cancel"; onClicked: Qt.quit() }
            }
        }
    }
}
