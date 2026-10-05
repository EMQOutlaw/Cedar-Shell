import QtQuick
import QtQuick.Controls
import QtTest
import Quickshell
import "../.."
import "../../components"
import "../../components/PopupPlacement.js" as Placement
import "../../services"
import "../../modules"
import "../../components/StableRows.js" as StableRows
ShellRoot {
    FloatingWindow {
        id: window; visible: true; implicitWidth: 800; implicitHeight: 600
        Item {
            id: canvas; anchors.fill: parent
            StationButton { id: button; x: 40; y: 40; text: "Action"; hint: "Action hint" }
            BarButton { id: bar; x: 180; y: 40; text: "Bar" }
            StationCombo { id: combo; x: 640; y: 540; width: 140; model: ["One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight"] }
            SettingRow { id: setting; x: 20; y: 130; width: 320; title: "Long setting title"; description: "A longer description wraps naturally when text is scaled and controls move below the label."; StationButton { text: "Change" } }
        }
        Loader { id: page; active:false; asynchronous:true; width:700;height:450;sourceComponent:Component { SettingsPanel { active:true } } }
        Loader { id: menuPage; active:false; asynchronous:true; anchors.fill:parent; source:Qt.resolvedUrl("modules/MenuContent.qml") }
        Loader { id: networkPage; active:false; asynchronous:true; width:500; sourceComponent:Component { ConnectionSettings {} } }
        ListModel { id: rows }
        ServiceRequest { id: bounded; script:"tests/response_limit.py"; maximumResponse:1024; timeoutMs:2000; property string error:""; onFailed:message=>error=message }
        ListView { id: view; x:400;y:80;width:250;height:160;model:rows
            delegate: StationButton { required property string itemId;required property string label;text:label;width:230;height:36 }
        }
        TestCase {
            name: "Controls"; when: window.visible
            function test_responseLimit() {
                verify(bounded.send({action:"test"}));
                tryVerify(()=>bounded.error.length>0,3000);
                verify(bounded.error.indexOf("response limit")>=0);
                tryCompare(bounded,"running",false,1000);
            }
            function test_quietHover() {
                for (const control of [button, bar]) {
                    mouseMove(canvas, 780, 10); wait(30);
                    const color = control.background.color.toString(), ink = control.contentItem.color.toString();
                    const w = control.width, h = control.height, x = control.x, y = control.y;
                    mouseMove(control, control.width/2, control.height/2); wait(40);
                    verify(control.hovered);
                    compare(control.background.color.toString(), color); compare(control.contentItem.color.toString(), ink);
                    compare(control.width,w); compare(control.height,h); compare(control.x,x); compare(control.y,y);
                    control.forceActiveFocus(Qt.TabFocusReason); wait(20); verify(control.visualFocus);
                    const outline = control.background.children[0]; compare(outline.border.width, 2);
                    mousePress(control, control.width/2, control.height/2); verify(control.down);
                    mouseRelease(control, control.width/2, control.height/2);
                    control.enabled=false; wait(10); compare(control.contentItem.color.toString(),Theme.muted.toString()); control.enabled=true;
                }
            }
            function test_popupAndScale() {
                mouseClick(combo, combo.width/2, combo.height/2); wait(120); verify(combo.popup.visible);
                verify(combo.popup.x>=12); verify(combo.popup.y>=12);
                verify(combo.popup.x+combo.popup.width<=canvas.width-12);
                verify(combo.popup.y+combo.popup.height<=canvas.height-12);
                verify(combo.popup.y<combo.y, "Bottom-edge dropdown flips above its anchor");
                keyClick(Qt.Key_Escape); wait(40); verify(!combo.popup.visible);
                const old=setting.implicitHeight; Theme.fontScale=1.75; wait(100);
                verify(setting.compact); verify(setting.implicitHeight>=old); verify(setting.implicitHeight>=52);
                Theme.fontScale=1;
            }
            function test_modelIdentity() {
                StableRows.reconcile(rows,[{itemId:"one",label:"First"},{itemId:"two",label:"Second"}],"itemId");wait(50);
                const first=view.itemAtIndex(0);verify(first!==null);first.forceActiveFocus(Qt.TabFocusReason);
                StableRows.reconcile(rows,[{itemId:"two",label:"Second"},{itemId:"one",label:"Updated"}],"itemId");wait(50);
                compare(view.itemAtIndex(1),first);compare(first.text,"Updated");verify(first.activeFocus);
                StableRows.reconcile(rows,[{itemId:"one",label:"Updated"}],"itemId");wait(20);compare(view.itemAtIndex(0),first);
            }
            function test_repeatedPageLifetime() {
                DesktopSettings.data=Object.assign({},DesktopSettings.data,{input:{sensitivity:0}});
                DesktopSettings.loadInput();DesktopSettings.editInput("sensitivity",0.4);
                for(let i=0;i<100;++i){page.active=true;tryCompare(page,"status",Loader.Ready,3000);verify(page.item!==null);page.active=false;tryCompare(page,"item",null,1000);}
                verify(DesktopSettings.inputDirty);compare(DesktopSettings.inputDraft.sensitivity,0.4);
                DesktopSettings.editInput("sensitivity",0);verify(!DesktopSettings.inputDirty);
                verify(!SystemStats.demanded, "Test mode does not start telemetry helpers");
                for(let i=0;i<100;++i){menuPage.active=true;tryCompare(menuPage,"status",Loader.Ready,3000);menuPage.item.focusMenu();verify(window.activeFocusItem!==null);menuPage.active=false;tryCompare(menuPage,"item",null,1000);}
            }
            function test_networkDisappears() {
                networkPage.active=true;tryCompare(networkPage,"status",Loader.Ready,3000);
                Network.data=Object.assign({},Network.data,{networks:[{path:"/test/ap",ssid:"Fixture",security:"wpa2",strength:60,active:false,saved:false,device:"/test/device"}]});
                networkPage.item.selected={path:"/test/ap",ssid:"Fixture",security:"wpa2"};
                const password=findChild(networkPage.item,"networkPassword");verify(password!==null);password.text="synthetic-not-a-real-secret";
                Network.data=Object.assign({},Network.data,{networks:[]});
                compare(networkPage.item.selected,null);compare(password.text,"");
                networkPage.active=false;
            }
            function test_setupPages() {
                window.implicitWidth=1100;window.implicitHeight=800;page.width=1000;page.height=700;
                page.active=true;tryCompare(page,"status",Loader.Ready,3000);
                page.item.navigate("setup");wait(150);
                function find(item,name){if(item.objectName===name)return item;for(const child of item.children || []){const found=find(child,name);if(found)return found;}return null;}
                tryVerify(()=>find(page.item,"firstRunPage")!==null,3000);
                for(let step=0;step<6;++step){SetupFlow.step=step;wait(40);verify(!SetupFlow.busy);}
                SetupFlow.step=1;
                SetupFlow.plan={mode:"Adopted Hybrid",roles:{bar:"CEDAR",lock:"Existing verified locker (retained)"},recovery:"Fixture: no desktop actions enabled"};
                wait(30);
                const directory=Quickshell.env("CEDAR_SCREENSHOT_DIR");
                let saved=false;page.grabToImage(result=>{saved=result.saveToFile(directory+"/setup-wide.png");});tryVerify(()=>saved,3000);
                page.width=420;wait(60);saved=false;page.grabToImage(result=>{saved=result.saveToFile(directory+"/setup-narrow.png");});tryVerify(()=>saved,3000);
                page.active=false;page.width=700;page.height=450;window.implicitWidth=800;window.implicitHeight=600;SetupFlow.plan=null;
            }
            function test_geometry() {
                let seed=19;
                function random() { seed=(seed*1664525+1013904223)>>>0; return seed/4294967296; }
                for(let i=0;i<5000;++i) {
                    const work={x:-2000+random()*3000,y:-1000+random()*1600,width:1+random()*2000,height:1+random()*1400};
                    const anchor={x:work.x-100+random()*(work.width+200),y:work.y-100+random()*(work.height+200),width:random()*300,height:random()*80};
                    const fit=Placement.fitPopup(anchor,{width:1+random()*1000,height:1+random()*1000},work,["bottom","top","left","right"][i%4]);
                    verify(fit.x>=work.x);verify(fit.y>=work.y);verify(fit.x+fit.width<=work.x+work.width+.00001);verify(fit.y+fit.height<=work.y+work.height+.00001);
                }
                let rejected=false;try{Placement.fitPopup({x:NaN,y:0,width:1,height:1},{width:1,height:1},{x:0,y:0,width:10,height:10});}catch(_){rejected=true;}verify(rejected);
            }
            function cleanupTestCase() { console.log("PASS: quiet controls, popup containment and scale"); Qt.quit(); }
        }
    }
}
