import QtQuick
import ".."

// A reading that changes often: a short vertical resolution, and a static
// update whenever the previous change was less than a second ago, so a
// clock or a live meter never animates every tick.
KineticLabel {
    transitionStyle: "resolve"
    duration: Theme.fast
    minimumInterval: 900
    maximumAnimatedLength: 12
    travel: 4
}
