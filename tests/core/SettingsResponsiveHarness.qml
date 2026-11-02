import QtQuick
import QtQuick.Window
import Quickshell
import "../.."
import "../../components"
import "../../components/SettingsSchema.js" as Schema
import "../../modules"
import "../../services"

ShellRoot {
    id: harness
    Settings { id: window }
    property var sizes: [
        {w:480,h:360,scale:1}, {w:760,h:540,scale:1},
        {w:979,h:540,scale:1}, {w:980,h:540,scale:1},
        {w:1280,h:840,scale:1}, {w:1920,h:1080,scale:1},
        {w:480,h:540,scale:1.3}, {w:1280,h:540,scale:1.3}
    ]
    property int sizeIndex: 0
    property int pageIndex: 0
    property int retries: 0
    property int windowsDirtiedSize: -1
    readonly property var pages: Schema.pages.map(p=>p.id)
    function check(ok, message) {
        if (!ok) { console.error("FAIL: " + sizes[sizeIndex].w + " / " + pages[pageIndex] + ": " + message); Qt.exit(1); }
        return ok;
    }
    function find(item, name) {
        if (item.objectName===name) return item;
        for (const child of item.children || []) { const found=find(child,name); if(found) return found; }
        return null;
    }
    function checkBounds(item, page) {
        if (!item.visible) return true;
        if (item instanceof SettingRow || item instanceof SettingsSection ||
            item instanceof SettingsSurface || item instanceof StationField ||
            item instanceof StationCombo || item instanceof StationSlider || item instanceof StationButton) {
            const p=item.mapToItem(page,0,0);
            if(!check(p.x>=-1 && p.x+item.width<=page.width+1,
                      item+" exceeds page width: "+p.x+" + "+item.width+" > "+page.width)) return false;
        }
        for(const child of item.children || []) if(!checkBounds(child,page)) return false;
        return true;
    }
    function prepare() {
        const size=sizes[sizeIndex];
        Theme.fontScale=size.scale;
        const nativeWindow=window.contentItem.Window.window;
        nativeWindow.width=size.w; nativeWindow.height=size.h;
        SettingsService.navigate(pages[pageIndex],"");
        retries=0;
        inspect.restart();
    }
    function advance() {
        pageIndex++;
        if(pageIndex===pages.length) { pageIndex=0; sizeIndex++; }
        if(sizeIndex===sizes.length) {
            console.log("PASS: Settings responsive layouts across "+sizes.length+" sizes and "+pages.length+" pages");
            Qt.quit();
        } else prepare();
    }
    Timer {
        id: inspect; interval:180
        onTriggered: {
            const panel=find(window.contentItem,"settingsPanel");
            const loader=find(panel,"settingsPageLoader");
            if(!loader?.item && retries++<30) { restart(); return; }
            if(!check(!!loader?.item,"page loaded")) return;
            const viewport=find(panel,"settingsScroll");
            const area=find(panel,"settingsPageArea");
            const size=sizes[sizeIndex];
            if(!check(panel.width===size.w && panel.height===size.h,"real window resize reached panel")) return;
            if(!check(viewport.height>=100 && viewport.y+viewport.height<=area.height+1,"scroll viewport stays usable")) return;
            // The windows sticky bar must never eat the viewport, including
            // the dirty state (the bar floats over the page bottom).
            if(pages[pageIndex]==="windows") {
                const bar=find(panel,"windowsApplyBar");
                if(harness.windowsDirtiedSize!==sizeIndex) {
                    harness.windowsDirtiedSize=sizeIndex;
                    if(loader.item.change) loader.item.change("gaps_in",Math.round(Number(loader.item.v("gaps_in",5))+1));
                    inspect.restart(); return;  // re-inspect with the draft dirty
                }
                if(!check(!!bar && bar.visible,"dirty windows draft shows the floating bar")) return;
                // The overlay must leave 100px of UNOBSCURED viewport and must
                // not trap the Reset row: scroll to the bottom while still dirty.
                const vpTop=viewport.mapToItem(panel,0,0).y;
                const unobscured=bar.y-Math.max(vpTop,viewport.y);  // bar floats over the viewport's bottom
                if(!check(unobscured>=100,"dirty state leaves 100px unobscured above the bar")) return;
                const flick=viewport.contentItem;
                flick.contentY=Math.max(0,flick.contentHeight-flick.height);
                const resetRow=find(panel,"windowsResetRow");
                if(!check(!!resetRow,"windows Reset row exists")) return;
                const resetBottom=resetRow.mapToItem(panel,0,resetRow.height).y;
                if(!check(resetBottom<=bar.y+1,"bottom Reset clears the floating bar while dirty")) return;
                flick.contentY=0;
                if(loader.item.discard) loader.item.discard();
            }
            if(!check(Math.abs(loader.item.width-viewport.availableWidth)<2,"page follows viewport width")) return;
            if(!checkBounds(loader.item,loader.item)) return;
            const grid=find(loader.item,"settingsThemeGrid");
            if(grid && !check(grid.columns>=1 && grid.columns<=4,"theme columns adapt")) return;
            // A resize must not trap the bottom of a long page outside its viewport.
            const flick=viewport.contentItem;
            flick.contentY=Math.max(0,flick.contentHeight-flick.height);
            if(!check(flick.contentY+flick.height>=flick.contentHeight-1,"page bottom remains reachable")) return;
            flick.contentY=0;
            const directory=Quickshell.env("CEDAR_SCREENSHOT_DIR");
            if(directory && ["overview","appearance","bar","apps"].includes(pages[pageIndex])) {
                panel.grabToImage(result=>{
                    result.saveToFile(directory+"/"+pages[pageIndex]+"-"+size.w+"-"+size.h+"-"+size.scale+".png");
                    advance();
                });
            } else advance();
        }
    }
    Component.onCompleted: {
        FIXTURE_SETUP
        SettingsInfo.data=Object.assign({},SettingsInfo.data,{themes:THEME_FIXTURE});
        SettingsService.setLevel("advanced");
        ShellState.open("settings");
        Qt.callLater(prepare);
    }
}
