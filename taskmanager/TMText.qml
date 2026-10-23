import QtQuick
Text {
    property bool technical: false
    property bool secondary: false
    textFormat: Text.PlainText
    font.family: technical ? TM.mono : TM.font
    font.pixelSize: (technical ? 11 : 14) * TM.scale
    color: secondary ? TM.muted : TM.text
    elide: Text.ElideRight
}
