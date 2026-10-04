import QtQuick
import QtQuick.Controls
import ".."
ComboBox {
    id: root
    implicitHeight: 40
    font.family: Theme.dataFont; font.pixelSize: Theme.small
    contentItem: Text { text: root.displayText; color: root.enabled ? Theme.text : Theme.muted; font: root.font; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; leftPadding: 12; rightPadding: 24 }
    background: Rectangle { color: Theme.surface; radius: 6; border.width: 1; border.color: root.activeFocus ? Theme.teal : Theme.border }
    indicator:Text { x:root.width-width-12; anchors.verticalCenter:parent.verticalCenter; text:"⌄"; color:root.enabled ? Theme.teal:Theme.muted; font.pixelSize:16 }
    delegate: ItemDelegate {
        width: root.width
        contentItem: Text { text: root.textRole ? modelData[root.textRole] : modelData; color: Theme.text; font: root.font; elide: Text.ElideRight }
        background: Rectangle { color: highlighted ? Theme.elevated : Theme.surface }
        highlighted: root.highlightedIndex === index
    }
    popup: Popup {
        y: root.height + 4; width: root.width
        implicitHeight: Math.min(280, list.contentHeight + 8); padding: 4
        background: Rectangle { radius: 6; color: Theme.surface; border.color: Theme.border }
        contentItem: ListView { id: list; clip: true; model: root.popup.visible ? root.delegateModel : null; currentIndex: root.highlightedIndex; ScrollIndicator.vertical: ScrollIndicator {} }
    }
}
