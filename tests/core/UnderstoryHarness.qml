import QtQuick
import QtTest
import Quickshell
import "../.."
import "../../modules"
import "../../services"

// Actual UI + services in CEDAR_TEST; Python substitutes only the native layer
// host for offscreen. No real session locks, radio changes or hardware actions.
ShellRoot {
    id: test
    property int step: 0
    property int renders: 0
    property int cycles: 0
    function check(ok, message) { if (!ok) { console.error("FAIL: " + message); Qt.exit(1); throw new Error(message); } }
    function named(item, name) { if (item.objectName === name) return item; for (const child of item.children || []) { const found = named(child, name); if (found) return found; } return null; }
    function shot(name) { frame.grabToImage(image => { check(image.saveToFile(Quickshell.env("CEDAR_SCREENSHOT_DIR") + "/" + name + ".png"), "saved " + name); renders++; }); }
    function network(kind, hardware) { Network.data = {available:true,hardware:hardware,enabled:true,status:{kind:kind,state:"connected",label:kind},networks:[],saved:[]}; }
    Timer { interval: 15000; running: true; onTriggered: { console.log("FAIL: harness stalled"); Qt.quit(); } }
    UnderstoryWindow { id: host; modelData: Quickshell.screens[0] }
    UnderstoryDictation { id: dictation; modelData: Quickshell.screens[0] }
    UnderstoryBar { id: bar; output: Quickshell.screens[0] }
    FloatingWindow {
        id: window
        visible: true; implicitWidth: 420; implicitHeight: 800; color: Theme.background
        TestCase { id: keyboard; when: false }
        UnderstorySettings { id: settings; visible: false; width: 240 }

        Rectangle {
            id: frame; width: 388; height: 760; color: Theme.background
            UnderstoryRail { id: rail; anchors.fill: parent; active: true }
        }
    }
    Timer {
        interval: 250; running: true; repeat: true
        onTriggered: {
            switch (test.step++) {
            case 0:
                check(!host.contentLoaded, "closed rail has no instantiated content");
                check(!dictation.contentLoaded, "idle dictation renderer is unloaded");
                check(dictation.widthFor(200) <= 200 - Config.barWidth, "dictation fits output width");
                for (const width of [180,240,388,600,1080]) check(host.widthFor(width) <= width, "horizontal width clamp " + width);
                Config.saved.barPlacement = "understory";
                Config.saved.coreEnabled = true;
                // Core pill is Strata-only now: beside the left bar there is no
                // Core surface at all (CoreHost's model, CoreService.available
                // and the presenter all refuse), so nothing may claim it.
                check(CoreService.enabled && Config.barVertical, "Core stays enabled beside the left bar");
                check(!CoreService.available, "no Core pill in Understory: not floating, not docked, nothing");
                check(Dictation.presenter === "understory", "the bar's own filament presents, never a Core pill (" + Dictation.presenter + ")");
                check(!dictation.requested, "no sidebar dictation duplicate while the Core pill cannot exist");
                for (const width of [180,240,388,600]) check(host.widthFor(width) <= width - Config.barWidth, "reserved left width " + width);
                check(bar.workspaceCapacity(480,300) <= 180, "workspace budget excludes footer");
                check(bar.workspaceCapacity(120,200) === 0, "tiny viewport never negative");
                const workspaces = named(bar.contentItem, "understoryBarWorkspaces");
                const footer = named(bar.contentItem, "understoryBarFooter");
                check(workspaces.contentHeight > workspaces.height, "40 workspaces overflow into scrolling");
                check(workspaces.mapToItem(bar.contentItem,0,workspaces.height).y <= footer.y, "workspace grid never intersects footer");
                Config.saved.barPlacement = "top";
                DesktopSettings.data = {bindings:[],monitors:[],input:{},owned:{bindings:[]}};
                settings.keys = "super   + o";
                check(settings.normalizedKeys === "SUPER + O", "typed keys normalize before conflict lookup");
                DesktopSettings.data = {bindings:[{keys:"SUPER+O",submap:"",description:"Existing"}],monitors:[],input:{},owned:{bindings:[]}};
                check(settings.conflicts.length === 1, "normalized key conflict detected");
                settings.recording = true;
                settings.record({key:Qt.Key_Escape,modifiers:0,accepted:false});
                check(!settings.recording, "Escape cancels shortcut recording");
                settings.record({key:Qt.Key_K,modifiers:Qt.ControlModifier|Qt.MetaModifier,accepted:false});
                check(settings.keys === "SUPER + CTRL + K", "keyboard shortcut capture");
                network("wired", false);
                break;
            case 1: {
                const net = named(rail,"understoryNetwork");
                check(net && net.enabled && net.label === "Wired" && net.hint.indexOf("Connections") >= 0, "wired without Wi-Fi has matching actionable transport");
                net.clicked();
                check(Canopy.topic === "network", "network control routes to Connections");
                Canopy.close();
                // Test the same action through Qt's keyboard event route.
                window.visible = false; window.visible = true;
                net.forceActiveFocus(Qt.TabFocusReason);
                keyboard.keyClick(Qt.Key_Space);
                check(Canopy.topic === "network", "Space activates focused Connections control");
                Canopy.close();
                network("wifi",true);
                break;
            }
            case 2:
                check(named(rail,"understoryNetwork").label === "Wi-Fi", "Wi-Fi display follows transport");
                check(!named(rail,"understoryAwake").enabled, "missing inhibitor disabled");
                check(!named(rail,"understoryBluetooth").visible, "missing Bluetooth hidden");
                check(!named(rail,"understoryVpn").visible, "missing VPN hidden");
                const quiet = named(rail,"understoryQuiet"), before = Config.saved.doNotDisturb;
                quiet.clicked(); check(Config.saved.doNotDisturb !== before, "quiet-hours action matches state");
                quiet.clicked(); check(Config.saved.doNotDisturb === before, "quiet-hours restores");
                check(named(rail,"understoryGaming").enabled === !Gaming.busy, "Gaming busy guard");
                named(rail,"understoryFocus").clicked(); check(Focus.windowOpen, "Focus opens existing application"); Focus.closeApp();
                Network.data = {available:false,hardware:false,networks:[],saved:[]};
                break;
            case 3:
                check(!named(rail,"understoryNetwork").enabled, "missing network service disabled");
                shot("understory");
                Understory.open(Quickshell.screens[0].name);
                break;
            case 4:
                check(host.contentLoaded && host.mapped, "open creates rail content");
                // Reproduce compositor ordering: outside-grab clear precedes
                // delivery of the opener click. Registered controls prevent it.
                const focusGrab = host.focusGrab;
                check(focusGrab !== null, "focus grab exposed for policy regression");
                if (!focusGrab.windows.includes(bar)) focusGrab.cleared();
                Understory.toggle(Quickshell.screens[0].name);
                check(!Understory.shown, "same opener closes once, never clear-then-reopens");
                Understory.open(Quickshell.screens[0].name);
                focusGrab.cleared();
                check(!Understory.shown, "genuine outside grab clear dismisses");
                Understory.close();
                break;
            case 5:
                check(!host.contentLoaded && !host.mapped, "close destroys rail content");
                frame.width = 240; frame.height = 420; Theme.fontScale = 1.5;
                break;
            case 6: {
                check(rail.compact, "narrow scaled layout reflows");
                const net = named(rail,"understoryNetwork");
                check(net.width > 0 && net.width <= frame.width, "tiles fit narrow layout");
                const instruments = named(rail,"understoryInstruments");
                check(instruments.width <= frame.width, "instrument grid wraps within narrow rail");
                const content = named(rail,"understoryContentScroll");
                check(content.height > 0 && content.contentHeight > content.height, "short rail keeps scrollable content");
                content.contentY = content.contentHeight - content.height;
                check(content.contentY > 0, "lower controls reachable");
                shot("understory-narrow");
                Theme.reducedMotion = true;
                Understory.open(Quickshell.screens[0].name);
                break;
            }
            case 7:
                check(host.contentLoaded, "reduced motion opens without delay");
                ShellState.locked = true;
                break;
            case 8:
                check(!host.contentLoaded && !host.mapped, "lock signal destroys content immediately");
                check(!rail.enabled, "all rail actions disabled under lock");
                ShellState.locked = false;
                Understory.close();
                break;
            default:
                if (test.cycles < 20) {
                    if (test.cycles % 2 === 0) { check(!host.contentLoaded, "cycle closed"); Understory.open(Quickshell.screens[0].name); }
                    else { check(host.contentLoaded, "cycle open"); Understory.close(); }
                    test.cycles++;
                    break;
                }
                if (test.cycles === 20) {
                    Config.saved.reducedMotion = false; Theme.reducedMotion = false;
                    Config.saved.barPlacement = "understory"; Config.saved.coreEnabled = false;
                    Dictation.installed = true; Dictation.daemon = true; Dictation.state = "recording";
                    test.cycles++; break;
                }
                if (test.cycles === 21) {
                    check(dictation.requested && dictation.contentLoaded, "Core-off dictation fallback maps lazily");
                    Config.fullscreenFocused = true; Config.fullscreenScreen = Quickshell.screens[0].name;
                    test.cycles++; break;
                }
                if (test.cycles === 22) {
                    check(!dictation.requested && !dictation.contentLoaded && dictation.dotOnly && dictation.visible, "covered fallback shows static dot only");
                    check(!Dictation.levelsWanted && Dictation.levelConsumers === 0, "dot-only has no level consumer");
                    check(dictation.implicitWidth <= Theme.spaceXl && dictation.implicitHeight <= Theme.spaceXl, "dot-only native geometry is tiny");
                    check(!dictation.animating && !dictation.closing, "covered fallback stops animation and exit timer");
                    check(dictation.indicatorColor === Theme.ember, "recording dot is ember");
                    for (const w of [1,8,16,48,240,1080]) check(dictation.dotLeftFor(w) + Math.min(w,dictation.dotExtent) <= w, "dot geometry clamped " + w);
                    Dictation.state = "transcribing";
                    check(dictation.dotOnly && dictation.indicatorColor === Theme.amber && !Dictation.levelsWanted, "processing dot amber without levels");
                    Config.saved.coreDictation = false;
                    check(!dictation.dotOnly && !dictation.visible, "explicit dictation setting disables dot");
                    Config.saved.coreDictation = true;
                    Config.saved.coreEnabled = true;
                    // Core is Strata-only: beside the left bar the presenter is
                    // "understory", so its own dot shows. There is no Core pill
                    // to duplicate, and no second fallback.
                    check(dictation.dotOnly && dictation.visible, "understory presenter shows its own dot; Core pill is absent");
                    Config.saved.coreEnabled = false;
                    ShellState.locked = true;
                    check(!dictation.dotOnly && !dictation.visible && !dictation.contentLoaded, "lock removes dot immediately");
                    ShellState.locked = false;
                    Dictation.state = "";
                    check(!dictation.dotOnly && !dictation.visible, "idle removes covered dot");
                    Dictation.state = "recording";
                    Config.fullscreenFocused = false;
                    Gaming.active = true;
                    test.cycles++; break;
                }
                if (test.cycles === 23) {
                    check(dictation.dotOnly && !dictation.contentLoaded && !Dictation.levelsWanted, "Gaming dot-only has no renderer or levels");
                    Gaming.active = false;
                    Dictation.state = "recording";
                    test.cycles++; break;
                }
                if (test.cycles === 24) {
                    Dictation.daemon = true; Dictation.state = "recording";
                    test.cycles++; break;
                }
                if (test.cycles === 25) {
                    // Reassert the state: the daemon's own process may have
                    // exited between cycles and reset it to idle.
                    Dictation.daemon = true; Dictation.state = "recording";
                    check(dictation.contentLoaded && !dictation.dotOnly, "uncovered fallback recreates content " + JSON.stringify({requested:dictation.requested,covered:dictation.covered,mapped:dictation.mapped,dot:dictation.dotOnly,state:Dictation.state,presenter:Dictation.presenter}));
                    Config.saved.coreEnabled = true;
                    // Core cannot take over beside the left bar (Strata-only),
                    // so the bar's presenter stays and its renderer stays loaded:
                    // no transfer, no exit timer, no duplicate surface.
                    check(dictation.contentLoaded, "understory presenter stays active; Core cannot transfer");
                    check(!dictation.closing, "no exit timer when the presenter stays with the bar");
                    ShellState.locked = true;
                    check(!dictation.mapped && !dictation.animating && !dictation.closing, "lock interrupts functional animation and exit timer");
                    ShellState.locked = false; Dictation.state = "";
                    test.cycles++; break;
                }
                if (test.cycles === 26) {
                    // Security follow-up: the left-bar mark opens Field Station,
                    // never the rail (mirrors SurfacePolicyHarness step9).
                    const mark = named(bar.contentItem, "understoryBarMark");
                    check(mark !== null, "left bar has its CEDAR mark");
                    check(mark.hint === "Field Station", "left-bar mark advertises Field Station");
                    mark.clicked();
                    check(Canopy.shown && Canopy.topic === "station" && ShellState.panel === "canopy", "left-bar mark opens the Field Station topic");
                    check(ShellState.panel !== "understory" && !Understory.shown, "left-bar mark never opens the rail");
                    Canopy.close();
                    Config.saved.canopyEnabled = false;
                    mark.clicked();
                    check(Station.windowOpen, "without Canopy the mark opens the Station app");
                    check(ShellState.panel !== "understory" && !Understory.shown, "Station route never opens the rail either");
                    Station.closeApp();
                    Config.saved.canopyEnabled = true;
                    test.cycles++; break;
                }
                check(!host.contentLoaded, "no content after ten open/close cycles");
                check(test.renders === 2, "asynchronous render completion");
                console.log("PASS: Understory rail; responsive controls and ten lifecycle cycles");
                Qt.quit();
            }
        }
    }
}
