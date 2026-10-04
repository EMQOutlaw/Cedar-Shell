import QtQuick
import QtQuick.Layouts
import Quickshell
import ".."
import "../components"

import "../services"

ColumnLayout {
    id: root
    objectName: "sessionControls"
    spacing: 16
    property bool embedded: false
    property string pending: ""
    onVisibleChanged: pending = ""
    function choose(action) {
        if (ShellState.locked)
            return;
        if (action === "lock") {
            ShellState.lock(false);
            return;
        }
        if (action === "suspend") {
            ShellState.lock(true);
            return;
        }
        pending = action;
    }
    function confirm() {
        if (ShellState.locked)
            return;
        if (Config.testMode) {
            pending = "";
            return;
        }
        const commands = {
            logout: ["hyprctl", "dispatch", "hl.dsp.exit()"],
            reboot: ["systemctl", "reboot"],
            shutdown: ["systemctl", "poweroff"]
        };
        if (commands[pending])
            Quickshell.execDetached(commands[pending]);
        Canopy.close();
        ShellState.close();
    }

    GlowText {
        visible: !root.embedded
        text: "TEND THE LIGHT"
        font.family: Theme.labelFont
        font.pixelSize: 28
        color: Theme.green
    }
    GlowText {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: root.pending ? "Confirm " + root.pending + "?" : "Rest a while. We'll keep your place."
        color: Theme.muted
    }
    GridLayout {
        Layout.fillWidth: true
        columns: root.width < 550 ? 2 : 5
        Repeater {
            model: ["lock", "suspend", "logout", "reboot", "shutdown"]
            StationButton {
                required property string modelData
                text: modelData.toUpperCase()
                Layout.fillWidth: true
                accent: modelData === "shutdown" ? Theme.ember : Theme.green
                onClicked: root.choose(modelData)
            }
        }
    }
    RowLayout {
        StationButton {
            visible: root.pending !== ""
            text: "CONFIRM"
            accent: Theme.amber
            onClicked: root.confirm()
        }
        StationButton {
            visible: !root.embedded || root.pending !== ""
            text: root.pending ? "CANCEL" : "CLOSE"
            onClicked: if (root.pending)
                root.pending = ""
            else {
                Canopy.close();
                ShellState.close();
            }
        }
    }
}
