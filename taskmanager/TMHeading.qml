import QtQuick
import "../components/core/Kinetic.js" as Kinetic
Item {
    id: root
    property string text: ""
    property real size: 23
    property color color: TM.text
    property alias font: label.font
    implicitHeight: label.implicitHeight
    implicitWidth: label.implicitWidth
    clip: true
    property string previous: ""
    onTextChanged: {
        const style=Kinetic.choose("resolve", previous, text, 24, !TM.kinetic || !visible);
        previous=text;
        if(style!=="none") { if(!settle.running) {label.opacity=.35;label.y=6;} settle.restart(); }
    }
    onVisibleChanged: if(!visible) { settle.stop(); label.opacity=1; label.y=0; }
    TMText { id: label; width: parent.width; text: root.text; font.pixelSize: root.size * TM.scale; color: root.color }
    ParallelAnimation {
        id: settle
        NumberAnimation { target: label; property: "opacity"; to: 1; duration: TM.ms(180) }
        NumberAnimation { target: label; property: "y"; to: 0; duration: TM.ms(220); easing.type: Easing.OutCubic }
    }
    Accessible.role: Accessible.StaticText
    Accessible.name: text
}
