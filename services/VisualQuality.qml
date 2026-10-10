pragma Singleton
import QtQuick
import Quickshell
import ".."

// One shell-wide visual-quality policy. Components consume `level`, never a
// gaming or battery check of their own:
//   normal    the full CEDAR experience
//   efficient Performance mode: no breathing light, spores, entrance sweeps,
//             spectrum or ambient telemetry (battery saver, a fullscreen
//             window, or chosen by hand)
//   gaming    Gaming Mode: everything in efficient, and the desktop quiets
//             itself around the game (Gaming owns the rest of that transaction)
// Decorative loops already rest through Theme.reducedMotion and Motion; this
// policy drives that gate, so a single binding reaches every one of them.
Singleton {
    id: root
    readonly property string level: Gaming.active ? "gaming" : Config.performanceActive ? "efficient" : "normal"
    readonly property bool normal: level === "normal"
    readonly property bool efficient: level === "efficient"
    readonly property bool gaming: level === "gaming"
    // Why the level is what it is, for badges and the Health card.
    readonly property string reason: gaming ? "Gaming Mode" : efficient ? Config.performanceReason : ""
    // Decorative motion and ambient effects stop below normal.
    readonly property bool decorative: normal
    // How long a functional morph takes, as a fraction of Theme's nominal
    // durations: the full motion at normal quality, shorter in Performance
    // mode, near-instant in Gaming Mode. Reduced Motion disables the Behaviors
    // altogether, so it needs no scale. One number, read by every surface.
    readonly property real preset: ({ calm: .7, balanced: 1, expressive: 1.25, off: 0 })[Config.saved.motionPreset] ?? 1
    // Functional surface motion is independent of ambience. Efficient/Gaming
    // shorten it via motionScale; only the user's motion choices disable it.
    readonly property bool functionalMotion: !Config.saved.reducedMotion && preset > 0
    readonly property bool effects: preset > 0 && !Theme.reducedMotion
    readonly property real motionScale: (gaming ? .35 : efficient ? .6 : 1) * (preset > 0 ? (preset > 1 ? 1.3 : preset) : 1)
    // Brightness and reach of decorative effects: the preset times the user's intensity.
    readonly property real effectIntensity: effects ? Config.saved.effectIntensity * (preset > 1 ? 1.2 : preset) : 0
    function ms(nominal) { return Math.round(nominal * motionScale); }
    // The awakening: announced once per shell run, by the first bar whose window
    // the compositor has mapped, so the drawing-in is seen rather than run
    // before the bar exists on screen. Never in test mode or with effects off.
    property bool awakenedOnce: false
    signal awakened()
    Timer { interval: 5000; running: !VisualQuality.awakenedOnce && !Config.testMode; onTriggered: VisualQuality.awakenedOnce = true }
    function awaken() {
        if (awakenedOnce || Config.testMode || !effects) return;
        awakenedOnce = true;
        awakened();
    }
}
