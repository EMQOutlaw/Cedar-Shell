import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import ".."
import "../components"
import "../services"

// The permission prompt: one chamfered card on the main display, over
// everything, with exclusive keyboard focus while a polkit request is open.
// What is asked, who is asked, a password field (shown or hidden as polkit
// says), Cancel and Authorize. A failed attempt stays on the card with the
// helper's own words. The card is created when a request starts and released
// when it ends; nothing of it exists otherwise.
PanelWindow {
    id: root
    screen: Quickshell.screens.find(s => s.name === Config.saved.mainDisplay) || Quickshell.screens[0] || null
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: Qt.alpha(Theme.background, .55)
    WlrLayershell.namespace: "cedar-permission"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    visible: Permission.active
    onVisibleChanged: if (visible) { field.text = ""; Qt.callLater(() => field.forceActiveFocus()); }
    MouseArea { anchors.fill: parent; onClicked: {} }
    ChamferFrame {
        id: card
        anchors.centerIn: parent
        width: Math.min(460, root.width - 48)
        height: column.implicitHeight + 48
        cut: 12
        fill: Qt.alpha(Theme.surface, .98)
        stroke: Qt.alpha(Permission.failed ? Theme.danger : Theme.teal, .5)
        line: true; lineColor: Permission.failed ? Theme.danger : Theme.green; lineFraction: .6
        ColumnLayout {
            id: column
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 24 }
            spacing: 10
            RowLayout {
                Layout.fillWidth: true
                SectionMark { text: "PERMISSION NEEDED"; tone: Permission.failed ? Theme.danger : Theme.teal }
                Item { Layout.fillWidth: true }
                StatusPill { text: Permission.identity; tone: Theme.teal }
            }
            GlowText { text: Permission.message; font.family: Theme.labelFont; font.pixelSize: Math.round(18 * Theme.fontScale); font.weight: Font.DemiBold; color: Theme.text; Layout.fillWidth: true; wrapMode: Text.WordWrap }
            GlowText { text: "A program is asking to act as the administrator. Your password goes to the system's authentication helper and is not kept."; font.pixelSize: Theme.small; color: Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
            GlowText { visible: Permission.supplementary !== ""; text: Permission.supplementary; font.pixelSize: Theme.small; color: Permission.supplementaryIsError ? Theme.danger : Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
            GlowText { visible: Permission.failed; text: "That was not recognised. Try again."; font.pixelSize: Theme.small; color: Theme.danger; Layout.fillWidth: true }
            StationField {
                id: field
                Layout.fillWidth: true
                visible: Permission.responseRequired
                placeholderText: Permission.prompt
                echoMode: Permission.responseVisible ? TextInput.Normal : TextInput.Password
                inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                Accessible.name: Permission.prompt
                onAccepted: root.authorize()
                Keys.onEscapePressed: Permission.cancel()
            }
            RowLayout {
                Layout.fillWidth: true; spacing: 8
                Item { Layout.fillWidth: true }
                StationButton { text: "Cancel"; onClicked: Permission.cancel() }
                StationButton { text: "Authorize"; accent: Theme.green; enabled: Permission.responseRequired; onClicked: root.authorize() }
            }
        }
    }
    function authorize() {
        if (!Permission.responseRequired) return;
        const secret = field.text;
        field.text = "";
        Permission.submit(secret);
    }
}
