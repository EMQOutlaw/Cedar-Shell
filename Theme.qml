pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    property var palette: ({})
    function token(name, fallback) {
        const color = palette[name];
        return typeof color === "string" && /^#[0-9a-fA-F]{6}$/.test(color) ? color : fallback;
    }
    FileView {
        path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/cedar/theme.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { try { palette = JSON.parse(text()).colors || ({}); } catch (_) { palette = ({}); } }
    }
    // All literal colors live here. scripts/export-themes.py derives app palettes.
    readonly property color background: token("background", "#080F0D")
    readonly property color surface: token("surface", "#101E19")
    readonly property color elevated: token("elevated", "#192D25")
    readonly property color border: token("border", "#315C4D")
    readonly property color green: token("green", "#9DFFB0")
    readonly property color brightGreen: token("brightGreen", "#4DFF9A")
    readonly property color teal: token("teal", "#3FE0C5")
    readonly property color amber: token("amber", "#F2C879")
    readonly property color ember: token("ember", "#E58B73")
    readonly property color text: token("text", "#E3F2E9")
    readonly property color muted: token("muted", "#A0B9AD")
    readonly property color blue: "#89BFCB"
    readonly property color violet: "#BBA9D6"
    readonly property color brightEmber: "#FFAB91"
    readonly property color brightAmber: "#FFE0A0"
    readonly property color brightBlue: "#B4DEEA"
    readonly property color brightViolet: "#D7C6EF"
    readonly property color brightTeal: "#9AF4E1"
    readonly property color white: "#F4FFF8"
    readonly property color transparent: Qt.alpha(background, 0)
    readonly property color glass: Qt.alpha(background, 0.94)
    readonly property color veil: Qt.alpha(background, 0.88)
    readonly property color grid: Qt.alpha(teal, 0.045)
    readonly property var availableFonts: Qt.fontFamilies()
    function resolveFont(requested, fallback) { return availableFonts.includes(requested) ? requested : fallback; }
    property string labelFont: resolveFont("Rajdhani", "sans-serif")
    property string dataFont: resolveFont("JetBrainsMono Nerd Font", "monospace")
    property real fontScale: 1
    readonly property int small: Math.round(12*fontScale)
    readonly property int normal: Math.round(14*fontScale)
    readonly property int title: Math.round(23*fontScale)
    // Logical pixels. Output scaling belongs to Qt, never to individual controls.
    readonly property int spaceXs: 4
    readonly property int spaceSm: 8
    readonly property int spaceMd: 12
    readonly property int spaceLg: 16
    readonly property int spaceXl: 24
    readonly property int spaceXxl: 32
    readonly property int controlHeight: 36
    readonly property int settingRowHeight: 52
    readonly property int controlRadius: 8
    readonly property int cardRadius: 12
    readonly property int panelRadius: 16
    readonly property int focusWidth: 2
    readonly property int focusInset: 2
    readonly property int gap: 12
    readonly property int padding: 24
    readonly property int barHeight: 44
    readonly property int chamfer: 12
    readonly property int glowRadius: 12
    readonly property int fast: 120
    readonly property int transition: 180
    readonly property int sweep: 650
    readonly property int pulse: 4200
    readonly property int osdDuration: 1800
    property bool reducedMotion: false
}
