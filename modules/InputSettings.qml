import QtQuick
import QtQuick.Layouts
import ".."
import "../services"
import "../components"
import "../components/SettingsSchema.js" as Schema
ColumnLayout {
    id: root
    objectName:"inputPage"
    property bool active:false
    property string highlightKey:""
    readonly property var draft: DesktopSettings.inputDraft
    readonly property var base: DesktopSettings.inputBase
    readonly property var edits: DesktopSettings.inputEdits
    readonly property bool dirty: DesktopSettings.inputDirty
    readonly property bool externalChange: DesktopSettings.inputExternalChange
    property bool resetConfirm:false
    readonly property var fields:Schema.inputFields.filter(f=>f.key in draft && (!f.key.startsWith("touchpad:") || DesktopSettings.data.hasTouchpad===true))
    readonly property var layouts: String(draft.kb_layout ?? "").split(",").map(s=>s.trim())
    readonly property var variants: String(draft.kb_variant ?? "").split(",").map(s=>s.trim())
    function load(){DesktopSettings.loadInput();}
    function change(key,value){DesktopSettings.editInput(key,value);}
    function has(key){return root.fields.some(f=>f.key===key);}
    function field(key){return Schema.inputFields.find(f=>f.key===key) || {label:key,description:""};}
    // Layouts and variants are parallel comma lists; edit them together.
    function setLayouts(pairs){
        pairs=pairs.filter(p=>p.layout!=="");
        change("kb_layout",pairs.map(p=>p.layout).join(","));
        if(has("kb_variant"))change("kb_variant",pairs.some(p=>p.variant) ? pairs.map(p=>p.variant).join(","):"");
    }
    readonly property var pairs: layouts.map((l,i)=>({layout:l,variant:variants[i] || ""})).filter(p=>p.layout!=="")
    onActiveChanged:if(active)DesktopSettings.refresh()
    Component.onCompleted:if(!DesktopSettings.inputDirty)load()
    spacing:16
    component InputRow: SettingRow {
        property string key:""
        objectName:key; Layout.fillWidth:true; visible:root.has(key)
        title:root.field(key).label; description:root.field(key).description
        highlighted:root.highlightKey===key; enabled:!DesktopSettings.busy
    }
    SettingsCard {
        visible:root.externalChange; Layout.fillWidth:true; padding:14
        GlowText { text:"Input configuration changed outside this page. Reload before applying changes to the same options."; color:Theme.amber; Layout.fillWidth:true; wrapMode:Text.WordWrap; font.pixelSize:Theme.small }
        StationButton { text:"Reload active values"; onClicked:root.load() }
    }

    SettingsSection {
        visible:root.has("kb_layout") || root.has("numlock_by_default")
        heading:"Keyboard layout"; caption:"The first layout is used at login. Select another to make it the default."
        Flow {
            objectName:"kb_layout"; visible:root.has("kb_layout"); Layout.fillWidth:true; spacing:8
            Repeater {
                model:root.pairs
                Rectangle {
                    id:chip
                    required property var modelData
                    required property int index
                    width:chipRow.implicitWidth+20; height:Theme.controlHeight; radius:Theme.controlRadius
                    color:index===0 ? Qt.alpha(Theme.teal,.12):Qt.alpha(Theme.teal,.035)
                    border.width:root.highlightKey==="kb_layout" ? 2:1; border.color:index===0 ? Qt.alpha(Theme.teal,.55):Qt.alpha(Theme.teal,.16)
                    RowLayout {
                        id:chipRow; anchors.centerIn:parent; spacing:6
                        StationButton {
                            implicitHeight:28; padding:2
                            text:chip.modelData.layout.toUpperCase()+(chip.modelData.variant ? " · "+chip.modelData.variant:"")+(chip.index===0 ? "  DEFAULT":"")
                            hint:chip.index===0 ? "Default layout":"Make "+chip.modelData.layout+" the default layout"
                            background:Item {}
                            enabled:chip.index>0 && !DesktopSettings.busy
                            onClicked:{const p=root.pairs.slice();const [moved]=p.splice(chip.index,1);root.setLayouts([moved].concat(p));}
                        }
                        StationButton { visible:root.pairs.length>1; implicitHeight:24; implicitWidth:24; padding:0; text:"×"; hint:"Remove "+chip.modelData.layout; enabled:!DesktopSettings.busy
                            onClicked:root.setLayouts(root.pairs.filter((_,i)=>i!==chip.index)) }
                    }
                }
            }
        }
        RowLayout {
            visible:root.has("kb_layout"); Layout.fillWidth:true; spacing:8
            StationField { id:newLayout; Layout.fillWidth:true; placeholderText:"Add layout, e.g. de"; Accessible.name:"Layout code"; maximumLength:16; onAccepted:addLayout.clicked() }
            StationField { id:newVariant; objectName:"kb_variant"; visible:root.has("kb_variant"); Layout.fillWidth:true; placeholderText:"Variant (optional), e.g. nodeadkeys"; Accessible.name:"Layout variant"; maximumLength:32; onAccepted:addLayout.clicked() }
            StationButton {
                id:addLayout; text:"Add layout"
                enabled:/^[a-z]{2,8}(\([a-z0-9_-]+\))?$/i.test(newLayout.text.trim()) && /^[a-z0-9_-]*$/i.test(newVariant.text.trim()) && !DesktopSettings.busy
                onClicked:{root.setLayouts(root.pairs.concat([{layout:newLayout.text.trim().toLowerCase(),variant:newVariant.text.trim()}]));newLayout.text="";newVariant.text="";}
            }
        }
        InputRow { key:"numlock_by_default"
            StationToggle { Layout.fillWidth:true; accessibleLabel:root.field("numlock_by_default").label; checked:root.draft.numlock_by_default===true; onToggled:value=>root.change("numlock_by_default",value) }
        }
    }

    SettingsSection {
        visible:root.has("repeat_rate") || root.has("repeat_delay")
        heading:"Key repeat"; caption:"What happens when you hold a key down."
        InputRow { key:"repeat_delay"; description:"How long to hold before repeating starts."
            StationSlider { Layout.fillWidth:true; from:100; to:2000; stepSize:25; value:Number(root.draft.repeat_delay ?? 600); Accessible.name:"Repeat delay"; onMoved:root.change("repeat_delay",Math.round(value)) }
            GlowText { Layout.preferredWidth:64; horizontalAlignment:Text.AlignRight; text:Math.round(root.draft.repeat_delay ?? 0)+" ms"; color:Theme.teal; font.pixelSize:Theme.small }
        }
        InputRow { key:"repeat_rate"; description:"Characters per second once repeating."
            StationSlider { Layout.fillWidth:true; from:1; to:100; stepSize:1; value:Number(root.draft.repeat_rate ?? 25); Accessible.name:"Repeat rate"; onMoved:root.change("repeat_rate",Math.round(value)) }
            GlowText { Layout.preferredWidth:64; horizontalAlignment:Text.AlignRight; text:Math.round(root.draft.repeat_rate ?? 0)+" /s"; color:Theme.teal; font.pixelSize:Theme.small }
        }
        // One and a half seconds of holding a key, drawn to scale.
        Item {
            visible:root.has("repeat_rate") && root.has("repeat_delay")
            Layout.fillWidth:true; Layout.leftMargin:12; Layout.rightMargin:12; implicitHeight:34
            readonly property real span:1500
            readonly property real delay:Math.min(span,Number(root.draft.repeat_delay ?? 600))
            readonly property real interval:1000/Math.max(1,Number(root.draft.repeat_rate ?? 25))
            Rectangle { anchors.verticalCenter:parent.verticalCenter; anchors.verticalCenterOffset:-6; width:parent.width; height:1; color:Qt.alpha(Theme.teal,.18) }
            Rectangle { anchors.verticalCenter:parent.verticalCenter; anchors.verticalCenterOffset:-6; width:parent.width*parent.delay/parent.span; height:3; radius:2; color:Qt.alpha(Theme.amber,.55) }
            Rectangle { x:0; anchors.verticalCenter:parent.verticalCenter; anchors.verticalCenterOffset:-6; width:2; height:14; color:Theme.green }
            Repeater {
                model:Math.max(0,Math.min(120,Math.floor((parent.span-parent.delay)/parent.interval)+1))
                Rectangle {
                    required property int index
                    x:parent.width*(parent.delay+index*parent.interval)/parent.span; anchors.verticalCenter:parent.verticalCenter; anchors.verticalCenterOffset:-6
                    width:1; height:10; color:Theme.teal; opacity:.75
                }
            }
            Text { anchors.left:parent.left; anchors.bottom:parent.bottom; text:"press"; font.family:Theme.dataFont; font.pixelSize:9; color:Theme.muted }
            Text { x:Math.min(parent.width-width,parent.width*parent.delay/parent.span+4); anchors.bottom:parent.bottom; text:"repeating"; font.family:Theme.dataFont; font.pixelSize:9; color:Theme.muted }
            Text { anchors.right:parent.right; anchors.bottom:parent.bottom; text:"1.5 s"; font.family:Theme.dataFont; font.pixelSize:9; color:Theme.muted }
        }
        StationField {
            objectName:"repeatTest"; Layout.fillWidth:true
            placeholderText:root.dirty ? "Apply first, then hold a key here to feel it" : "Hold a key here to try your repeat settings"
            Accessible.name:"Key repeat test field"
        }
    }

    SettingsSection {
        visible:["sensitivity","accel_profile","natural_scroll"].some(k=>root.has(k))
        heading:"Pointer feel"; caption:"Speed and response for mice and other pointers."
        InputRow { key:"sensitivity"; description:"Zero keeps the device default."
            GlowText { text:"Slower"; color:Theme.muted; font.pixelSize:10 }
            StationSlider { Layout.fillWidth:true; from:-1; to:1; stepSize:.05; value:Number(root.draft.sensitivity ?? 0); Accessible.name:"Pointer sensitivity"; onMoved:root.change("sensitivity",Math.round(value*100)/100) }
            GlowText { text:"Faster"; color:Theme.muted; font.pixelSize:10 }
            GlowText { Layout.preferredWidth:44; horizontalAlignment:Text.AlignRight; text:(Number(root.draft.sensitivity ?? 0)>0 ? "+":"")+Number(root.draft.sensitivity ?? 0).toFixed(2); color:Theme.teal; font.pixelSize:Theme.small }
        }
        InputRow { key:"accel_profile"
            ChoiceChips { Layout.fillWidth:true; accessibleLabel:"Acceleration"; options:[{value:"adaptive",label:"Adaptive"},{value:"flat",label:"Flat"},{value:"",label:"Device"}]; current:root.draft.accel_profile; onChosen:value=>root.change("accel_profile",value) }
        }
        InputRow { key:"natural_scroll"
            StationToggle { Layout.fillWidth:true; accessibleLabel:root.field("natural_scroll").label; checked:root.draft.natural_scroll===true; onToggled:value=>root.change("natural_scroll",value) }
        }
    }

    SettingsSection {
        visible:root.fields.some(f=>f.key.startsWith("touchpad:"))
        heading:"Touchpad"; caption:"Shown because this computer reports a touchpad."
        InputRow { key:"touchpad:tap-to-click"
            StationToggle { Layout.fillWidth:true; accessibleLabel:root.field("touchpad:tap-to-click").label; checked:root.draft["touchpad:tap-to-click"]===true; onToggled:value=>root.change("touchpad:tap-to-click",value) }
        }
        InputRow { key:"touchpad:natural_scroll"
            StationToggle { Layout.fillWidth:true; accessibleLabel:root.field("touchpad:natural_scroll").label; checked:root.draft["touchpad:natural_scroll"]===true; onToggled:value=>root.change("touchpad:natural_scroll",value) }
        }
        InputRow { key:"touchpad:disable_while_typing"
            StationToggle { Layout.fillWidth:true; accessibleLabel:root.field("touchpad:disable_while_typing").label; checked:root.draft["touchpad:disable_while_typing"]===true; onToggled:value=>root.change("touchpad:disable_while_typing",value) }
        }
        InputRow { key:"touchpad:scroll_factor"
            StationSlider { Layout.fillWidth:true; from:.1; to:5; stepSize:.1; value:Number(root.draft["touchpad:scroll_factor"] ?? 1); Accessible.name:"Touchpad scroll speed"; onMoved:root.change("touchpad:scroll_factor",Math.round(value*10)/10) }
            GlowText { Layout.preferredWidth:44; horizontalAlignment:Text.AlignRight; text:Number(root.draft["touchpad:scroll_factor"] ?? 1).toFixed(1)+"×"; color:Theme.teal; font.pixelSize:Theme.small }
        }
    }

    GlowText { visible:!root.fields.length; text:"Input settings are unavailable. The service message above contains the compositor error."; color:Theme.muted; Layout.fillWidth:true; wrapMode:Text.WordWrap }
    Flow {
        Layout.fillWidth:true; spacing:8
        StationButton { text:"Apply input settings"; accent:Theme.green; checked:root.dirty; enabled:root.dirty && !DesktopSettings.busy; onClicked:DesktopSettings.apply({action:"input",values:root.edits,expected:root.base}) }
        StationButton { text:"Discard edits"; enabled:root.dirty; onClicked:root.load() }
        StationButton { text:root.resetConfirm ? "Confirm reset":"Reset Input"; accent:root.resetConfirm ? Theme.amber:Theme.teal; enabled:!DesktopSettings.busy; onClicked:{if(root.resetConfirm){DesktopSettings.apply({action:"reset-input"});root.resetConfirm=false;}else root.resetConfirm=true;} }
        StationButton { visible:root.resetConfirm; text:"Cancel"; onClicked:root.resetConfirm=false }
        GlowText { visible:root.dirty && !root.resetConfirm; height:36; verticalAlignment:Text.AlignVCenter; text:Object.keys(root.edits).length+(Object.keys(root.edits).length===1 ? " change":" changes")+" ready. Only changed options are written."; color:Theme.teal; font.pixelSize:Theme.small }
    }
    GlowText { visible:root.resetConfirm; text:"Removes only CEDAR’s input overrides. Your manually maintained Hyprland configuration takes effect again."; color:Theme.amber; Layout.fillWidth:true; wrapMode:Text.WordWrap; font.pixelSize:Theme.small }
}
