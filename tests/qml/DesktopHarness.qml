import QtQuick
import Quickshell
import "../.."
import "../../modules"
import "../../services"
ShellRoot {
    Component { FieldStation {} }
    FloatingWindow {
        id: window
        visible: true; implicitWidth: 1180; implicitHeight: 800
        SettingsPanel { id: settings; width:1180; height:800; active: true }
        ControlPanel { id: control; width: 720; height: 760; active: visible; visible: false }
        Component.onCompleted: {
            DesktopSettings.data={
                monitors:[{name:"DP-1",description:"Wide display",width:3440,height:1440,refreshRate:175,vrr:false,availableModes:["3440x1440@175.00Hz","3440x1440@60.00Hz"],x:0,y:0,scale:1,transform:0},
                    {name:"DP-2",description:"Second display",width:2560,height:1440,refreshRate:240,vrr:true,availableModes:["2560x1440@240.00Hz"],x:3440,y:0,scale:1,transform:0}],
                bindings:[{keys:"SUPER + F",description:"Files",arg:"nautilus",dispatcher:"exec",category:"Applications",editable:true}],
                input:{kb_layout:"us",kb_variant:"",repeat_rate:40,repeat_delay:250,sensitivity:0,accel_profile:"adaptive",numlock_by_default:true,natural_scroll:false,"touchpad:tap-to-click":true,"touchpad:natural_scroll":true,"touchpad:disable_while_typing":true,"touchpad:scroll_factor":1},
                hasTouchpad:true,unsupported:{},owned:{bindings:[]},pending:null
            };
            DesktopSettings.refreshed();
            SettingsInfo.data={hostname:"cedar-station",kernel:"6.18.4-arch1",os:"Arch Linux",version:"Development build",versions:{quickshell:"Quickshell 0.3",hyprland:"Hyprland 0.55",qt:"6.10"},theme:"CEDAR",wallpaper:"",wallpapers:[],themes:[{name:"cedar",label:"CEDAR",preview:""},{name:"nord",label:"Nord",preview:""},{name:"everforest",label:"Everforest",preview:""}],services:[{name:"PipeWire",unit:"pipewire.service",status:"Healthy",detail:"active · running",user:true},{name:"WirePlumber",unit:"wireplumber.service",status:"Healthy",detail:"active · running",user:true},{name:"Bluetooth",unit:"bluetooth.service",status:"Unavailable",detail:"not installed",user:false}]};
            Network.data={available:true,enabled:true,hardware:true,label:"Ridge",devices:[{path:"/device/1",name:"wlan0",type:2}],
                networks:[{path:"/ap/1",device:"/device/1",ssid:"Ridge",strength:89,security:"wpa-psk",active:true,saved:"/connection/1"},
                    {path:"/ap/2",device:"/device/1",ssid:"Nearby network",strength:57,security:"wpa-psk",active:false,saved:""}],
                saved:[{path:"/connection/1",name:"Ridge",type:"wifi",active:"/active/1"},{path:"/connection/2",name:"Work VPN",type:"vpn",active:""}]};
            DefaultApps.data=DEFAULT_APPS_FIXTURE;
            Controls.data={profiles:["power-saver","balanced","performance"],profile:"balanced",nightlight:false,errors:{}};
        }
        property int step:0
        property string shot:""
        readonly property var sections:["overview","appearance","apps","desktop","bar","core","displays","input","keybinds","connections","shield","audio","notifications","power","time","system","about"]
        function check(ok,label){if(!ok){console.error("FAIL: "+label);Qt.exit(1);}}
        Timer {
            id:capture; interval:180
            onTriggered:{
                if(window.shot.startsWith("settings-narrow"))window.check(settings.width===480 && settings.narrow && settings.findItem(settings,"settingsSearch").width>400,"Narrow layout uses 480 pixels");
                (control.visible ? control:settings).grabToImage(r=>r.saveToFile(Quickshell.env("CEDAR_SCREENSHOT_DIR")+"/"+window.shot+".png"));
            }
        }
        Timer {
            interval:350; running:true; repeat:true
            onTriggered:{
                const count=window.sections.length;
                if(window.step<count*2){
                    settings.section=window.sections[window.step%count];
                    settings.width=window.step<count ? 1180:480;
                    window.shot="settings-"+(window.step<count ? "wide-":"narrow-")+settings.section;
                } else if(window.step<count*2+3){
                    control.visible=true;settings.width=1180;control.tab=["quick","network","bluetooth"][window.step-count*2];
                    window.shot="control-"+control.tab;
                } else if(window.step===count*2+3){
                    control.visible=false;settings.searchText="VRR";window.shot="search-vrr";
                    window.check(settings.results.some(r=>r.key==="vrr"),"VRR search indexes the actual display control");
                } else if(window.step===count*2+4){
                    settings.navigate("bar","barOpacity");window.shot="search-target";
                } else if(window.step===count*2+5){
                    window.check(settings.findItem(settings,"barOpacity")!==null,"Search target exists in rendered page");
                    Config.set("mainDisplay","DP-2");Config.set("clock24",false);Config.set("barOpacity",.3);settings.resetPage();
                    window.check(Config.saved.mainDisplay==="DP-2" && Config.saved.clock24===false && Config.barOpacity===.94,"Page reset preserves unrelated display and time preferences");
                    settings.navigate("input");window.shot="input-draft";
                } else if(window.step===count*2+6){
                    const input=settings.findItem(settings,"inputPage");input.change("sensitivity",.4);
                    DesktopSettings.data=Object.assign({},DesktopSettings.data,{input:Object.assign({},DesktopSettings.data.input,{sensitivity:.7})});DesktopSettings.refreshed();
                    window.check(input.dirty && input.draft.sensitivity===.4 && input.externalChange,"Refresh retains dirty input draft and reports changes");
                    settings.navigate("appearance");window.check(settings.section==="input" && settings.pendingPage==="appearance","Navigation protects unapplied edits");
                    window.shot="input-conflict";
                } else {console.log("PASS: Settings search, scoped reset, external changes, and draft navigation");Qt.quit();return;}
                capture.restart();window.step++;
            }
        }
    }
}
