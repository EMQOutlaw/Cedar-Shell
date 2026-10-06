import QtQuick
import ".."
// Renders a normalized combo such as "SUPER + SHIFT + F" as quiet keycaps.
Row {
    id: root
    property string keys: ""
    property color accent: Theme.teal
    readonly property var names: ({SUPER:"Super", CTRL:"Ctrl", ALT:"Alt", SHIFT:"Shift", RETURN:"Enter", KP_ENTER:"Enter", SPACE:"Space", BACKSPACE:"⌫", DELETE:"Del", TAB:"Tab", LEFT:"←", RIGHT:"→", UP:"↑", DOWN:"↓", ESCAPE:"Esc", PRINT:"PrtSc"})
    readonly property var media: ({AUDIORAISEVOLUME:"Vol +", AUDIOLOWERVOLUME:"Vol −", AUDIOMUTE:"Mute", AUDIOMICMUTE:"Mic mute", AUDIOPLAY:"Play", AUDIOPAUSE:"Pause", AUDIONEXT:"Next", AUDIOPREV:"Prev", AUDIOSTOP:"Stop", MONBRIGHTNESSUP:"Bright +", MONBRIGHTNESSDOWN:"Bright −", KBDBRIGHTNESSUP:"Kbd +", KBDBRIGHTNESSDOWN:"Kbd −", CALCULATOR:"Calc", SEARCH:"Search", POWEROFF:"Power"})
    function label(part) {
        if (names[part]) return names[part];
        if (part.toUpperCase().startsWith("XF86")) {
            const rest = part.slice(4).toUpperCase();
            return media[rest] || rest.charAt(0) + rest.slice(1).toLowerCase();
        }
        return part.length > 1 ? part.charAt(0) + part.slice(1).toLowerCase() : part;
    }
    spacing: 4
    Accessible.role: Accessible.StaticText
    Accessible.name: keys
    Repeater {
        model: root.keys ? root.keys.split("+").map(p => p.trim()).filter(Boolean) : []
        Rectangle {
            required property string modelData
            width: Math.max(24, cap.implicitWidth + 14); height: 24; radius: 5
            color: Qt.alpha(root.accent, .07)
            border.width: 1; border.color: Qt.alpha(root.accent, .32)
            Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 1; height: 2; radius: 1; color: Qt.alpha(root.accent, .18) }
            Text {
                id: cap
                anchors.centerIn: parent; anchors.verticalCenterOffset: -1
                text: root.label(parent.modelData); textFormat: Text.PlainText
                font.family: Theme.dataFont; font.pixelSize: Theme.small - 1
                color: root.enabled ? Theme.text : Theme.muted
            }
        }
    }
}
