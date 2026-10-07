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
}
