import QtQuick
import QtQuick.Layouts
import ".."
import "../components"
import "../services"
ColumnLayout {
    id:root
    property bool active:false
    property string highlightKey:""
    spacing:16
    onActiveChanged:if(active)Shield.refresh()
    Component.onCompleted:if(active)Shield.refresh()
    SettingsFields {page:"privacy";groups:["Privacy"];highlightKey:root.highlightKey;Layout.fillWidth:true}
    ShieldPages {embedded:true;Layout.fillWidth:true;implicitHeight:760;onClosed:SettingsService.closeApp()}
}
