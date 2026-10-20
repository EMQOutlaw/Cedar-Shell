import QtQuick
import QtQuick.Layouts
import Quickshell
import ".."
import "../modules"
import "../services"
import "core/StrataGeometry.js" as Geometry
Item {
    id: root
    property bool active: false
    property bool expanded: false
    property var palette: ({})
    readonly property bool palettePreview: Object.keys(palette).length > 0
    property real origin: .5
    property string previewText: "Preview"
    implicitHeight: expanded ? 220 : 120
    Layout.fillWidth: true
    clip: true
    readonly property var targetRect: Geometry.target({barWidth:width-24, wantedWidth:320, wantedHeight:140, availableHeight:140, minimumHeight:0, edge:8,anchor:{x:(width-24)*origin,width:1}})
    Behavior on implicitHeight { enabled:root.active && VisualQuality.functionalMotion; NumberAnimation { duration:VisualQuality.ms(Theme.morphGrow); easing.type:Easing.OutCubic } }
    SettingsBackdrop { anchors.fill:parent; strength:.7 }
    StrataBarFrame {
        id:frame; x:12;y:22;width:parent.width-24;height:Config.barHeight
        centerWidth:120; awakening:root.expanded ? .35:0
        foundation:root.palette.background || Theme.strataFoundation
        materialSurface:root.palette.surface || Theme.strataSurface
        grain:root.palette.border || Theme.strataGrain
        eventAccent:root.palette.green || Theme.strataAccent
    }
    // Real bar renderer, disabled as a whole: no tray, workspace or media action
    // can reach the desktop from a preview. No second layer-shell window exists.
    StrataBarContents {
        visible: !root.palettePreview
        x:24;y:27;width:Math.max(0,parent.width-48);height:Math.max(24,Config.barHeight-10)
        output:Quickshell.screens[0] || null
        enabled:false
    }
    // Palette previews use their own ink throughout without changing the live
    // Theme singleton or instantiating another set of desktop controllers.
    RowLayout {
        visible: root.palettePreview
        x:28; y:27; width:Math.max(0,parent.width-56); height:Math.max(24,Config.barHeight-10)
        spacing:12
        GlowText { text:"CEDAR"; color:root.palette.green || Theme.green; font.family:Theme.labelFont; font.bold:true }
        GlowText { text:"1   2   3"; color:root.palette.muted || Theme.muted }
        Item { Layout.fillWidth:true }
        GlowText { text:"12:30"; color:root.palette.text || Theme.text; font.family:Theme.dataFont }
        Item { Layout.fillWidth:true }
        GlowText { text:"Wi-Fi  ·  80%"; color:root.palette.text || Theme.text }
    }
    DropFrame {
        x:12+root.targetRect.x; y:22+Config.barHeight-5
        width:root.targetRect.width; height:root.expanded ? root.targetRect.height:0
        visible:height>0; clip:true
        Behavior on height { enabled:root.active && VisualQuality.functionalMotion; NumberAnimation { duration:VisualQuality.ms(Theme.morphGrow); easing.type:Easing.OutCubic } }
        Behavior on x { enabled:root.active && VisualQuality.functionalMotion; NumberAnimation { duration:VisualQuality.ms(Theme.expand); easing.type:Easing.OutCubic } }
        RowLayout {
            anchors.centerIn:parent; spacing:16
            CedarHeartwood { id:heart; size:34; active:root.active; unfolding:root.expanded; intensity:VisualQuality.effectIntensity }
            KineticLabel { text:root.previewText; animateChanges:root.active && VisualQuality.functionalMotion; font.family:Theme.labelFont; font.pixelSize:Theme.title; color:Theme.strataText }
        }
    }
    // Catch pointer input; preview buttons below own all simulation.
    MouseArea { anchors.fill:parent; acceptedButtons:Qt.AllButtons; onWheel:event=>event.accepted=true }
    GlowText { anchors.left:parent.left; anchors.bottom:parent.bottom; anchors.margins:10; text:"CEDAR preview · system controls are inactive"; font.pixelSize:Theme.small-1; color:Theme.muted }
    function play() { root.expanded=!root.expanded; if(root.active)heart.pulse(); }
    onActiveChanged:if(!active)expanded=false
}
