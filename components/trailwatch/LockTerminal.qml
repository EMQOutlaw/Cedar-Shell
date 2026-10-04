import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../.."
import ".."
import "../../services"

Rectangle {
    id: root
    required property var auth
    property bool responseVisible: false
    property bool active: false
    property bool preview: false
    signal submitted(string value)
    readonly property alias field: password
    function refocus() {
        if (active && !auth.busy)
            password.forceActiveFocus();
    }
    function submit() {
        if (!auth.busy && password.text.length) {
            const value = password.text;
            password.clear();
            submitted(value);
        }
    }
    implicitHeight: 118
    color: Theme.surface
    radius: 10
    border.color: password.activeFocus ? Qt.alpha(Theme.green, .7) : Theme.border
    onActiveChanged: if (active)
        Qt.callLater(refocus)
    Connections {
        target: root.auth
        function onClearInputs() {
            password.clear();
        }
        function onBusyChanged() {
            if (!root.auth.busy)
                Qt.callLater(root.refocus);
        }
    }
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 6
        RowLayout {
            Layout.fillWidth: true
            FieldText {
                text: "ACCESS TERMINAL"
                font.pixelSize: 10
                font.letterSpacing: 2
                color: Theme.muted
                Layout.fillWidth: true
            }
            FieldText {
                text: Trailwatch.capsKnown ? (Trailwatch.keyboard.capslock ? "CAPS LOCK ON" : "CAPS OFF") : "CAPS UNKNOWN"
                font.pixelSize: 10
                color: Trailwatch.keyboard.capslock ? Theme.amber : Theme.muted
            }
        }
        RowLayout {
            Layout.fillWidth: true
            TextField {
                id: password
                objectName: "trailwatchPassword"
                Layout.fillWidth: true
                implicitHeight: 36
                enabled: !root.auth.busy
                focus: true
                echoMode: root.responseVisible ? TextInput.Normal : TextInput.Password
                passwordCharacter: "•"
                passwordMaskDelay: 0
                selectByMouse: false
                placeholderText: root.auth.busy ? "Checking…" : root.preview ? "Preview · authentication disabled" : "Enter password"
                color: Theme.text
                placeholderTextColor: Theme.muted
                selectionColor: Theme.border
                selectedTextColor: Theme.white
                font.family: Theme.dataFont
                font.pixelSize: Theme.normal
                inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                background: Rectangle {
                    color: Theme.background
                    radius: 4
                }
                Accessible.name: "Unlock password"
                onAccepted: root.submit()
                Keys.onEscapePressed: clear()
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_U && (event.modifiers & Qt.ControlModifier)) {
                        clear();
                        event.accepted = true;
                    }
                }
                Component.onCompleted: Qt.callLater(root.refocus)
            }
            StationButton {
                text: root.auth.busy ? "WAIT" : "UNLOCK →"
                enabled: !root.auth.busy && password.text.length > 0
                accent: Theme.green
                onClicked: {
                    root.submit();
                    root.refocus();
                }
            }
        }
        FieldText {
            Layout.fillWidth: true
            text: root.preview ? "Visual preview · no session lock" : root.auth.status
            color: root.auth.status === "Enter your password" ? Theme.muted : root.auth.busy ? Theme.teal : Theme.amber
            font.pixelSize: 11
            wrapMode: Text.WordWrap
            maximumLineCount: 2
        }
    }
}
