import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower
import ".."
import "../components"
import "../services"

// Tend the light: lock, suspend, log out, reboot or shut down. Hosted as its
// own bar drop from the pill (Super+Esc) or in the centred overlay when the
// Canopy is off. Destructive choices arm first and confirm second.
ColumnLayout {
    id: root
    objectName: "sessionControls"
    spacing: 16
    property bool embedded: false
    property string pending: ""
    property int selected: 0
    readonly property var actions: ["lock", "suspend", "logout", "reboot", "shutdown"]
    readonly property var glyphs: ({ lock: "󰌾", suspend: "󰤄", logout: "󰍃", reboot: "󰜉", shutdown: "󰐥" })
    readonly property var words: ({ lock: "Lock", suspend: "Suspend", logout: "Log out", reboot: "Reboot", shutdown: "Shut down" })
    readonly property var notes: ({ lock: "Trailwatch keeps your place", suspend: "Lock, then sleep", logout: "End this Hyprland session", reboot: "Restart the machine", shutdown: "Power off" })
    function beat(order, span = .4) { return root.embedded ? Canopy.ease(.06 * order, span) : 1; }
    onVisibleChanged: { pending = ""; if (visible) Qt.callLater(() => root.forceActiveFocus()); }
    Component.onCompleted: if (visible) Qt.callLater(() => root.forceActiveFocus())
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
    function leave() {
        if (root.pending) { root.pending = ""; return; }
        Canopy.close();
        ShellState.close();
    }
    // Keyboard: arrows move, Enter chooses then confirms, Escape disarms then closes.
    focus: true
    Keys.onPressed: event => {
        switch (event.key) {
        case Qt.Key_Right: case Qt.Key_Tab: root.selected = (root.selected + 1) % root.actions.length; break;
        case Qt.Key_Left: case Qt.Key_Backtab: root.selected = (root.selected + root.actions.length - 1) % root.actions.length; break;
        case Qt.Key_Return: case Qt.Key_Enter:
            if (root.pending) root.confirm(); else root.choose(root.actions[root.selected]);
            break;
        case Qt.Key_Escape:
            if (!root.pending) return;   // let the host close the panel
            root.pending = "";
            break;
        default: return;
        }
        event.accepted = true;
    }

    // Title: the lantern phrase, with a filament that lights beneath it.
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 6
        opacity: root.beat(0)
        transform: Translate { y: 6 * (1 - root.beat(0)) }
        RowLayout {
            Layout.fillWidth: true
            GlowText {
                text: "TEND THE LIGHT"
                font.family: Theme.labelFont
                font.pixelSize: root.embedded ? 22 : 28
                font.letterSpacing: 2 + 6 * (1 - root.beat(0, .6))
                color: Theme.green
            }
            Item { Layout.fillWidth: true }
            StationButton { visible: root.embedded; text: "×"; hint: "Close"; iconOnly: true; onClicked: root.leave() }
        }
        Item {
            Layout.fillWidth: true
            implicitHeight: 1
            Rectangle {
                width: parent.width * root.beat(.3, .6)
                height: 1
                color: Qt.alpha(Theme.teal, .28)
                Rectangle { anchors.right: parent.right; width: Math.min(parent.width, 100); height: 1; color: Theme.green; opacity: .8 * (1 - root.beat(.6, .4)) }
            }
        }
    }
    Flow {
        Layout.fillWidth: true
        spacing: 8
        opacity: root.beat(1)
        transform: Translate { y: 6 * (1 - root.beat(1)) }
        StatusPill { text: "Up " + SystemStats.uptime; tone: Theme.teal }
        StatusPill {
            visible: UPower.displayDevice?.isPresent ?? false
            text: Math.round((UPower.displayDevice?.percentage ?? 0) * 100) + "% · " + (UPower.onBattery ? "battery" : "plugged in")
            tone: UPower.onBattery && (UPower.displayDevice?.percentage ?? 1) < .2 ? Theme.amber : Theme.green
        }
        StatusPill { visible: root.pending !== ""; text: "Confirm " + root.words[root.pending]; tone: Theme.amber }
    }
    GlowText {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: root.pending ? root.words[root.pending] + ": " + root.notes[root.pending] + ". Press Enter or Confirm to go ahead." : "Rest a while. We'll keep your place."
        color: root.pending ? Theme.amber : Theme.muted
        opacity: root.beat(1)
    }
    // One tile per action; the armed one glows amber, shut down keeps an ember edge.
    GridLayout {
        Layout.fillWidth: true
        columns: root.width < 460 ? 3 : 5
        columnSpacing: 8; rowSpacing: 8
        uniformCellWidths: true
        Repeater {
            model: root.actions
            Item {
                id: tile
                required property string modelData
                required property int index
                readonly property bool current: index === root.selected
                readonly property bool armed: root.pending === modelData
                readonly property bool grave: modelData === "shutdown"
                readonly property real sweep: root.beat(2 + index * .7, .4)
                readonly property color tone: armed ? Theme.amber : grave ? Theme.ember : Theme.teal
                Layout.fillWidth: true; Layout.preferredWidth: 1
                implicitHeight: 84
                opacity: sweep
                scale: .92 + .08 * sweep
                Accessible.role: Accessible.Button
                Accessible.name: root.words[modelData]
                ChamferFrame {
                    anchors.fill: parent
                    cut: 7
                    fill: tile.armed ? Qt.alpha(Theme.amber, .08) : tile.current ? Qt.alpha(Theme.green, .06) : hover.containsMouse ? Qt.alpha(Theme.teal, .05) : Qt.alpha(Theme.background, .5)
                    stroke: tile.armed ? Qt.alpha(Theme.amber, .7) : tile.current ? Qt.alpha(Theme.green, .55) : tile.grave ? Qt.alpha(Theme.ember, .35) : hover.containsMouse ? Qt.alpha(Theme.teal, .35) : Qt.alpha(Theme.teal, .13)
                    line: tile.current || tile.armed; lineColor: tile.armed ? Theme.amber : Theme.green; lineFraction: .55
                }
                Column {
                    anchors.centerIn: parent
                    width: parent.width - 10
                    spacing: 6
                    Text {
                        width: parent.width; horizontalAlignment: Text.AlignHCenter
                        text: root.glyphs[tile.modelData]
                        textFormat: Text.PlainText
                        font.family: Theme.resolveFont("JetBrainsMono Nerd Font", "monospace")
                        font.pixelSize: 24
                        color: tile.tone
                    }
                    Text {
                        width: parent.width; horizontalAlignment: Text.AlignHCenter
                        text: root.words[tile.modelData].toUpperCase()
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        font.family: Theme.dataFont; font.pixelSize: 9; font.letterSpacing: 1.2
                        color: tile.armed ? Theme.amber : tile.current ? Theme.green : Theme.text
                    }
                }
                MouseArea {
                    id: hover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onPositionChanged: root.selected = tile.index
                    onClicked: { root.selected = tile.index; if (tile.armed) root.confirm(); else root.choose(tile.modelData); }
                }
            }
        }
    }
    RowLayout {
        Layout.fillWidth: true
        opacity: root.beat(5)
        StationButton {
            visible: root.pending !== ""
            text: "CONFIRM"
            accent: Theme.amber
            onClicked: root.confirm()
        }
        StationButton {
            visible: !root.embedded || root.pending !== ""
            text: root.pending ? "CANCEL" : "CLOSE"
            onClicked: root.leave()
        }
        Item { Layout.fillWidth: true }
        GlowText {
            text: root.pending ? "ENTER confirm   /   ESC cancel" : "ENTER choose   /   arrows move   /   ESC close"
            color: Theme.muted
            font.pixelSize: 10
            elide: Text.ElideRight
        }
    }
}
