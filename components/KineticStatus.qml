import QtQuick
import ".."

// A status word in the data face: spaced capitals that relay their changed
// letters (CONNECTING → CONNECTED, PROTECTED → ATTENTION).
KineticLabel {
    transitionStyle: "relay"
    duration: Theme.expand
    font.family: Theme.dataFont
    font.pixelSize: 9
    font.letterSpacing: 1.2
    maximumAnimatedLength: 20
}
