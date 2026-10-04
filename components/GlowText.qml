import QtQuick
import ".."

Text {
    font.family: Theme.dataFont
    font.pixelSize: Theme.normal
    color: Theme.text
    textFormat: Text.PlainText
    renderType: Text.QtRendering
    property bool glow: false
    style: glow ? Text.Outline : Text.Normal
    styleColor: Qt.alpha(Theme.green, 0.22)
}
