pragma Singleton
import QtQuick
import Quickshell

Singleton {
    // All literal colors live here. scripts/export-themes.py derives app palettes.
    readonly property color background: "#080F0D"
    readonly property color surface: "#101E19"
    readonly property color elevated: "#192D25"
    readonly property color border: "#315C4D"
    readonly property color green: "#9DFFB0"
    readonly property color brightGreen: "#4DFF9A"
    readonly property color teal: "#3FE0C5"
    readonly property color amber: "#F2C879"
    readonly property color ember: "#E58B73"
    readonly property color text: "#E3F2E9"
    readonly property color muted: "#A0B9AD"
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
