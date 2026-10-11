import QtQuick
import QtQuick.Effects
Item {
    id: root
    property alias source: picture.source
    property int pixels: 480
    Image {
        id: picture
        anchors.fill: parent
        asynchronous: true
        sourceSize.width: root.pixels
        fillMode: Image.PreserveAspectCrop
        visible: false
    }
    Rectangle {
        id: mask
        anchors.fill: parent
        radius: 14
        layer.enabled: true
        visible: false
    }
    MultiEffect {
        anchors.fill: parent
        source: picture
        maskEnabled: true
        maskSource: mask
    }
}
