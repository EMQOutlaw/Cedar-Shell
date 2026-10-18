import QtQuick
import Quickshell
import "../.."
import "../../services"
import "../../components/SettingsSchema.js" as Schema

// SettingsService without a window: routes, navigation, drafts, depth, search,
// persistence and the lock guard. No page renders here; check_desktop_ui.py
// draws the pages.
ShellRoot {
    id: window
    function check(ok, label) { if (!ok) { console.error("FAIL: " + label); Qt.exit(1); } }
    Timer { id: finish; interval: 300; onTriggered: Qt.quit() }
    Component.onCompleted: {
        const s = SettingsService;
        check(!s.windowOpen && s.page === "overview" && !s.blocked && s.level === "simple" && !s.canGoBack, "starts closed on Overview in the Simple view");

        // Routes from ShellState land in the service, never in a panel.
        ShellState.settingsPage = "power"; ShellState.open("settings");
        check(s.windowOpen && s.open && s.page === "power" && ShellState.panel === "" && ShellState.settingsPage === "" && ShellState.settingsSection === "power", "ShellState.open(settings) opens the window on the requested page and clears the request");
        ShellState.toggle("settings");
        check(!s.windowOpen, "toggle with no page closes the window");
        ShellState.toggle("settings");
        check(s.windowOpen && s.page === "power", "toggle reopens where it was");
        ShellState.settingsPage = "time"; ShellState.toggle("settings");
        check(s.windowOpen && s.page === "time", "toggle with a page navigates instead of closing");

        // Navigation and history.
        check(s.navigate("appearance", "fontScale") && s.anchor === "fontScale" && s.canGoBack && s.history.length === 3, "navigate sets the anchor and records history");
        const generation = s.generation;
        check(s.navigate("appearance", "panelRadius") && s.generation === generation + 1 && s.history.length === 3, "same-page navigation bumps the generation without a history entry");
        check(s.back() && s.page === "time" && s.history.length === 2 && s.anchor === "", "back returns to the previous page");
        check(!s.navigate("nowhere", "") && s.page === "time", "unknown pages are refused");
        check(s.navigate("", "barOpacity") && s.page === "bar" && s.anchor === "barOpacity", "a key alone resolves its page");
        s.clearAnchor();
        check(s.anchor === "", "the window can clear the anchor after the highlight");

        // A draft holds navigation until the user decides.
        s.blocked = true;
        check(!s.navigate("time", "") && s.page === "bar" && s.pendingPage === "time", "a draft blocks navigation and records where the user wanted to go");
        check(!s.back() && s.pendingPage === "time", "back is held by the same draft");
        s.cancelPending();
        check(s.pendingPage === "" && s.page === "bar", "cancel keeps the page");
        s.navigate("notifications", "doNotDisturb"); s.confirmPending();
        check(s.page === "notifications" && s.anchor === "doNotDisturb" && s.pendingPage === "", "confirm completes the pending navigation with its anchor");
        s.blocked = false;
        s.navigate("power", "");
        const historyBeforeBack = s.history.length;
        s.blocked = true;
        check(!s.back() && s.pendingBack, "draft defers a Back action");
        s.confirmPending();
        check(s.page === "notifications" && s.history.length === historyBeforeBack - 1, "confirmed Back consumes history instead of appending it");
        s.blocked = false;

        // Depth: Simple folds advanced rows and pages; a jump reveals its row.
        const hidden = Schema.fields.find(f => Schema.levelOf(f) === "advanced");
        const another = Schema.fields.find(f => Schema.levelOf(f) === "advanced" && f.key !== hidden.key);
        check(!s.shows(hidden) && s.shows(Schema.fields.find(f => f.key === "clock24")), "Simple hides advanced rows and shows everyday rows");
        check(!s.menu.some(m => m.pages.some(p => p.id === "application-theming")), "Simple folds advanced pages away");
        s.navigate(hidden.page, hidden.key);
        check(s.shows(hidden) && !s.shows(another), "jumping to an advanced row reveals that row only");
        check(s.setLevel("advanced") === "advanced" && Config.saved.settingsLevel === "advanced" && s.advanced && s.shows(another), "Advanced persists in Config and shows every row");
        check(s.menu.some(m => m.pages.some(p => p.id === "application-theming")), "Advanced lists every page");
        check(s.menu.every(m => m.pages.length > 0) && s.menu.length === Schema.menu.length, "every category has pages in Advanced");
        check(s.setLevel("anything") === "simple" && s.level === "simple", "an unknown depth falls back to Simple");
        check(s.menuId === Schema.menuOf(s.page) && s.menuId !== "", "the current page knows its category");

        // Search covers preferences, pages and page controls; the JSON form is bounded.
        const found = s.search("24-hour");
        check(found.length > 0 && found[0].key === "clock24", "search finds a preference by its label");
        check(s.search("Field Notes").some(r => r.page === "notes" && r.key === ""), "search finds a page by its name");
        check(s.search("").length === 0, "an empty query finds nothing");
        const rows = JSON.parse(s.searchJson("notification", 3));
        check(Array.isArray(rows) && rows.length === 3 && rows.every(r => "page" in r && "key" in r && "label" in r && "group" in r), "searchJson returns bounded rows");
        check(JSON.parse(s.searchJson("notification", 500)).length <= 40, "searchJson never exceeds the search limit");

        // Window size and recent pages.
        check(s.windowSize.width >= s.minimumWidth && s.windowSize.height >= s.minimumHeight, "a default size is ready before any save");
        check(!s.rememberWindow(100, 100) && s.windowSize.width !== 100, "sizes below the minimum are ignored");
        check(s.rememberWindow(1300, 900) && s.windowSize.width === 1300 && s.windowSize.height === 900, "a settled size is remembered");
        s.navigate("bar", "");
        check(s.recent.length > 0 && s.recent[0].page === "bar" && s.recent.length <= 6 && !s.recent.some(r => r.page === "overview"), "recent pages are bounded, lead with the current page and skip Overview");

        // Scoped reset through the service.
        Config.set("barOpacity", .3); Config.set("clock24", false); s.resetPage("bar");
        check(Config.barOpacity === .94 && Config.saved.clock24 === false, "resetPage restores one page and leaves the others");
        check(s.hasPreferences("bar") && !s.hasPreferences("about"), "hasPreferences knows which pages can reset");

        // The lock closes the window and refuses every route.
        ShellState.locked = true;
        check(!s.windowOpen && !s.open, "lock closes the window");
        ShellState.settingsPage = "power"; ShellState.open("settings");
        check(!s.windowOpen && s.page === "bar", "nothing opens or navigates while locked");
        ShellState.locked = false;

        const status = JSON.parse(s.status());
        check(status.level === "simple" && status.page === "bar" && status.windowOpen === false && status.window.width === 1300 && status.recent[0] === "bar", "status reports the view");
        console.log("PASS: Settings service routes, navigation, drafts, depth, search, persistence and lock");
        finish.start();
    }
}
