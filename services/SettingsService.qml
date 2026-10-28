pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import ".."
import "../components/SettingsSchema.js" as Schema

// Settings as a service. One object owns what the Settings window shows:
// whether it is open, the page and the highlighted row, the search index, how
// deep the view goes (Simple or Advanced), a draft that holds navigation, the
// recently visited pages and the window's remembered size. The window
// (SettingsApp) is a presentation over it, like ShieldApp over Shield. Every
// route in the shell still goes through ShellState.open("settings"); it lands
// here, so the one-button rule keeps one owner and the single-entry tests
// keep their meaning.
Singleton {
    id: root

    // ------------------------------------------------------------ the window
    property bool windowOpen: false
    readonly property bool open: windowOpen && !ShellState.locked
    readonly property int minimumWidth: 480
    readonly property int minimumHeight: 360
    function openApp() { if (ShellState.locked || Config.stage < 3) return; windowOpen = true; }
    function closeApp() { windowOpen = false; cancelPending(); }
    function toggleApp() { if (windowOpen) closeApp(); else openApp(); }
    // ShellState.open/toggle("settings") arrive here with the page the caller
    // asked for (ShellState.settingsPage), or nothing for "where I left off".
    function route(page, anchor, toggle) {
        if (ShellState.locked || Config.stage < 3) return;
        if (toggle && windowOpen && !page && !anchor) { closeApp(); return; }
        windowOpen = true;
        if (page || anchor) navigate(page, anchor || "");
    }
    function openPage(page, anchor) { route(page, anchor, false); }
    function reviewUpdates() {
        if (ShellState.locked || Config.testMode) return;
        Quickshell.execDetached(["python3", Quickshell.shellPath("installer/cedar_install.py"), "--update", "--gui"]);
    }
    Connections { target: ShellState; function onLockedChanged() { if (ShellState.locked) root.windowOpen = false; } }

    // ------------------------------------------------------------ navigation
    readonly property var pageIds: Schema.pages.map(p => p.id)
    property string page: "overview"
    property string anchor: ""
    // Bumps on every accepted navigation, including to the same page, so the
    // window scrolls to and highlights the anchor again.
    property int generation: 0
    // The window sets blocked while its page holds an unapplied system draft
    // (input, displays); navigation then waits for the user's decision.
    property bool blocked: false
    property string pendingPage: ""
    property string pendingAnchor: ""
    property bool pendingBack: false
    property var history: []
    readonly property bool canGoBack: history.length > 0
    readonly property var pageInfo: Schema.pages.find(p => p.id === page) || Schema.pages[0]
    readonly property string menuId: Schema.menuOf(page)
    function label(id) { const found = Schema.pages.find(p => p.id === id); return found ? found.label : id; }
    function navigate(id, key) {
        const wanted = String(id || "");
        const target = pageIds.includes(wanted) ? wanted : (key ? Schema.pageOf(key) : "");
        if (!target) return false;
        if (blocked && target !== page) { pendingPage = target; pendingAnchor = key || ""; pendingBack = false; return false; }
        if (target !== page) history = history.concat([page]).slice(-32);
        commit(target, key || "");
        return true;
    }
    function commit(target, key) {
        page = target; anchor = key; generation++;
        pendingPage = ""; pendingAnchor = ""; pendingBack = false;
        ShellState.settingsSection = target;
        Forest.record("settings", "Settings / " + label(target), target);
        remember(target);
    }
    function back() {
        if (!history.length) return false;
        const previous = history[history.length - 1];
        if (blocked && previous !== page) { pendingPage = previous; pendingAnchor = ""; pendingBack = true; return false; }
        history = history.slice(0, -1);
        commit(previous, "");
        return true;
    }
    // The user chose to leave the draft behind: the window discards it first,
    // then this completes the navigation it held.
    function confirmPending() {
        if (!pendingPage) return;
        const target = pendingPage, key = pendingAnchor;
        if (pendingBack) history = history.slice(0, -1);
        else if (target !== page) history = history.concat([page]).slice(-32);
        commit(target, key);
    }
    function cancelPending() { pendingPage = ""; pendingAnchor = ""; pendingBack = false; }
    function clearAnchor() { anchor = ""; }

    // --------------------------------------------------------------- the view
    // Simple shows what most people change; Advanced shows every row and every
    // page. Search finds everything either way, and jumping to an advanced row
    // reveals it on its own.
    readonly property string level: Config.saved.settingsLevel === "advanced" ? "advanced" : "simple"
    readonly property bool advanced: level === "advanced"
    function setLevel(value) { const next = value === "advanced" ? "advanced" : "simple"; Config.set("settingsLevel", next); return next; }
    function toggleLevel() { return setLevel(advanced ? "simple" : "advanced"); }
    function shows(spec) { return advanced || !spec || Schema.levelOf(spec) === "basic" || (anchor !== "" && spec.key === anchor); }
    function showsPage(id) { const found = Schema.pages.find(p => p.id === id); return !found || advanced || !found.advanced || id === page; }
    // The menu the window draws: categories with the pages the view shows.
    readonly property var menu: Schema.menu.map(m => ({ id: m.id, label: m.label, description: m.description, pages: m.pages.filter(id => root.showsPage(id)).map(id => Schema.pages.find(p => p.id === id)) })).filter(m => m.pages.length)

    // ----------------------------------------------------------------- search
    readonly property var entries: Schema.fields
        .concat(DefaultApps.data.roles.map(r => ({ page: "apps", key: r.id, label: r.label, description: r.description, aliases: "default applications" })))
        .concat(Schema.pages.map(p => ({ page: p.id, key: "", label: p.label, description: p.description })))
        .concat(Schema.extras.filter(e => e.key !== "vrr" || DesktopSettings.data.monitors.some(m => "vrr" in m)))
        .concat(Schema.inputFields.filter(f => f.key in DesktopSettings.data.input && (!f.key.startsWith("touchpad:") || DesktopSettings.data.hasTouchpad === true)).map(f => Object.assign({ page: "input" }, f)))
    function search(text) { return Schema.search(entries, String(text || "")); }
    function searchJson(text, limit) {
        const rows = search(text).slice(0, Math.max(1, Math.min(40, Number(limit) || 10)));
        return JSON.stringify(rows.map(r => ({ page: r.page, key: r.key || "", label: r.label, group: r.group || "" })));
    }

    // ------------------------------------------------------------------ reset
    function hasPreferences(id) { return Schema.fields.some(f => f.page === (id || page)); }
    function resetPage(id) {
        const target = id || page;
        if (target === "bar") Config.resetBar();
        else Schema.fields.filter(f => f.page === target).forEach(f => Config.set(f.key, f.defaultValue));
        if (target === "core") Config.set("coreMonitor", "");
    }

    // ------------------------------------------------------------ persistence
    // ~/.local/state/cedar/settings-window.json: the window's last size and the
    // pages visited most recently. Preferences stay in settings.json; this is
    // session furniture, never a preference.
    QtObject {
        id: store
        property var window: ({ width: 1280, height: 840 })
        property var recent: []
        function save() { file.setText(JSON.stringify({ window: window, recent: recent }) + "\n"); }
    }
    FileView {
        id: file; path: Config.stateDir + "/settings-window.json"; atomicWrites: true; printErrors: false; blockLoading: true
        onLoaded: {
            try {
                const saved = JSON.parse(text() || "{}");
                if (saved && typeof saved === "object") {
                    const w = saved.window || {};
                    if (isFinite(w.width) && isFinite(w.height) && Number(w.width) >= root.minimumWidth && Number(w.height) >= root.minimumHeight) store.window = { width: Math.round(w.width), height: Math.round(w.height) };
                    if (Array.isArray(saved.recent)) store.recent = saved.recent.filter(r => r && root.pageIds.includes(r.page)).slice(0, 6);
                }
            } catch (_) {}
        }
    }
    readonly property var windowSize: store.window
    function rememberWindow(width, height) {
        if (!(isFinite(width) && isFinite(height) && width >= minimumWidth && height >= minimumHeight)) return false;
        if (store.window.width === Math.round(width) && store.window.height === Math.round(height)) return true;
        store.window = { width: Math.round(width), height: Math.round(height) }; store.save();
        return true;
    }
    readonly property var recent: store.recent
    function remember(id) {
        if (id === "overview") return;
        store.recent = [{ page: id, at: Date.now() }].concat(store.recent.filter(r => r.page !== id)).slice(0, 6);
        store.save();
    }

    function status() {
        return JSON.stringify({ open: open, windowOpen: windowOpen, page: page, anchor: anchor, level: level, blocked: blocked, pending: pendingPage, history: history.length, recent: recent.map(r => r.page), window: windowSize });
    }
}
