import QtQuick
import QtQuick.Controls
import ".."
import "PopupPlacement.js" as Placement
ComboBox {
    id: root
    implicitHeight: Theme.controlHeight
    // Coordinates belong to the containing window's overlay (logical pixels).
    // A host with reserved edges can supply its smaller usable rectangle.
    property rect popupWorkArea: Qt.rect(0, 0, Overlay.overlay ? Overlay.overlay.width : 0, Overlay.overlay ? Overlay.overlay.height : 0)
    function placePopup() {
        const overlay = Overlay.overlay;
        if (!overlay || popupWorkArea.width <= 0 || popupWorkArea.height <= 0) { popup.close(); return; }
        const point = mapToItem(overlay, 0, 0);
        const fit = Placement.fitPopup({x: point.x, y: point.y, width: width, height: height},
            {width: Math.max(width, 160), height: Math.max(44, Math.min(280, list.contentHeight + 8))},
            popupWorkArea, "bottom", 12, 4);
        popup.x = fit.x; popup.y = fit.y; popup.width = fit.width; popup.height = fit.height;
    }
    onPopupWorkAreaChanged: if (popup.visible) placePopup()
    onWidthChanged: if (popup.visible) placePopup()
    onXChanged: if (popup.visible) placePopup()
    onYChanged: if (popup.visible) placePopup()
    onVisibleChanged: if (!visible) popup.close()
    font.family: Theme.dataFont; font.pixelSize: Theme.small
    contentItem: Text { text: root.displayText; color: root.enabled ? Theme.text : Theme.muted; font: root.font; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight; leftPadding: 12; rightPadding: 24 }
    background: Rectangle { color: Theme.surface; radius: Theme.controlRadius; border.width: root.visualFocus ? Theme.focusWidth : 1; border.color: root.visualFocus ? Theme.teal : Theme.border }
    indicator:Text { x:root.width-width-12; anchors.verticalCenter:parent.verticalCenter; text:"⌄"; color:root.enabled ? Theme.teal:Theme.muted; font.pixelSize:16 }
    delegate: ItemDelegate {
        width: list.width
        implicitHeight: Theme.controlHeight
        contentItem: Text { text: root.textRole ? modelData[root.textRole] : modelData; color: Theme.text; font: root.font; elide: Text.ElideRight }
        background: Rectangle { color: highlighted ? Theme.elevated : Theme.surface }
        highlighted: root.highlightedIndex === index
    }
    popup: Popup {
        parent: root.Overlay.overlay
        // Controls.Popup remains inside the existing window. PanelWindow cannot
        // use a native PopupWindow anchor; do not invent a compositor work area.
        popupType: Popup.Item
        padding: 4
        onAboutToShow: root.placePopup()
        onOpened: root.placePopup()
        background: Rectangle { radius: Theme.controlRadius; color: Theme.surface; border.color: Theme.border }
        contentItem: ListView { id: list; clip: true; model: root.popup.visible ? root.delegateModel : null; currentIndex: root.highlightedIndex; onContentHeightChanged: if (root.popup.visible) root.placePopup(); ScrollIndicator.vertical: ScrollIndicator {} }
    }
}
