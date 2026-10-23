pragma Singleton
import QtQuick
QtObject {
    readonly property real scale: Task.style.fontScale || 1
    readonly property string font: Task.style.font || "sans-serif"
    readonly property string mono: Task.style.mono || "monospace"
    readonly property color base: Task.style.background
    readonly property color surface: Task.style.surface
    readonly property color elevated: Task.style.elevated
    readonly property color border: Task.style.border
    readonly property color text: Task.style.text
    readonly property color muted: Task.style.muted
    readonly property color accent: Qt.tint(muted, Qt.alpha(Task.style.green, .24))
    readonly property color cpu: Task.style.teal
    readonly property color memory: Task.style.violet
    readonly property color gpu: Task.style.amber
    readonly property color storage: Task.style.blue
    readonly property color danger: Task.style.ember
    readonly property color warning: Task.style.amber
    readonly property int tier: Task.style.reducedMotion ? 2 : Task.style.visualMode === "minimal" ? 2 : Task.style.visualMode === "reduced" || Task.style.efficient ? 1 : 0
    readonly property bool motion: tier < 2
    readonly property bool effects: tier === 0 && Task.style.effectIntensity > 0
    readonly property bool kinetic: motion && Task.style.kinetic !== false
    readonly property real motionScale: (tier === 1 ? .6 : 1) * (Task.style.motionScale || 1)
    function ms(n) { return motion ? Math.round(n * motionScale) : 0; }
}
