pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import ".."
import "../components"
import "../components/MenuModel.js" as MenuModel
import "../components/StableRows.js" as StableRows
import "../components/Compass.js" as Compass

// CEDAR owns its menu. Omarchy menus are loaded only by its explicit adapter.
Singleton {
    id: root
    readonly property string omarchyPath: Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy"
    readonly property string defaultMenuPath: Config.omarchyIntegration ? omarchyPath + "/default/omarchy/omarchy-menu.jsonc" : Quickshell.shellPath("menus/default.jsonc")
    readonly property string userMenuPath: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + (Config.omarchyIntegration ? "/omarchy/extensions/omarchy-menu.jsonc" : "/cedar/menu.jsonc")
    readonly property string cedarMenuPath: Quickshell.shellPath(Config.omarchyIntegration ? "integrations/omarchy/menu-overlay.jsonc" : "menus/cedar-menu.jsonc")
    readonly property string shimDir: Quickshell.shellPath("scripts/shim")
    readonly property string pluginsScript: Quickshell.shellPath("scripts/plugins.py")
    readonly property bool visible: ShellState.panel === "menu"

    property var defaultItems: []
    property var userItems: []
    property var cedarItems: []
    property var items: ({})
    onItemsChanged: {
        // Source generations normalize once; typing reuses these descriptors.
        for (const entry of Object.values(items)) {
            entry._searchName = MenuModel.nameSearchText(entry);
            entry._searchDescription = String(entry.description || "").toLowerCase();
            entry._searchLabel = String(entry.label || "").toLowerCase();
        }
    }
    property var itemOrder: []
    property bool rowsLoaded: false

    // "menu" browses the tree; "select" and "input" serve a script's prompt.
    property string mode: "menu"
    readonly property bool dmenuActive: mode !== "menu"
    property string dmenuPrompt: ""
    property var dmenuOptions: []
    property int dmenuWidth: 0
    property int dmenuMaxHeight: 0
    property string selectionFile: ""
    property string doneFile: ""
    property bool requestActive: false

    property string activeMenu: "root"
    property string filterText: ""
    property int selectedIndex: 0
    property var navStack: []
    property var rows: []
    property bool resetSelection: false
    readonly property alias displayModel: displayModel
    ListModel { id: displayModel }
    onRowsChanged: StableRows.reconcile(displayModel, rows, "itemId")
    function setRows(next) {
        const selected = !resetSelection && rows[selectedIndex]?.itemId;
        rows = next;
        const at = selected ? next.findIndex(row => row.itemId === selected) : -1;
        if (at >= 0) selectedIndex = at;
        resetSelection = false;
        clampSelection();
    }
    property bool searchDivider: false
    readonly property string title: {
        if (dmenuActive) return dmenuPrompt;
        const entry = item(activeMenu);
        return entry && entry.id !== "root" ? (entry.title || entry.label) : "Go";
    }
    readonly property string breadcrumb: dmenuActive ? "" : MenuModel.pathFor(items, activeMenu)

    property var providersLoaded: ({})
    property var providerQueue: []
    property int providerRevision: 0
    property var whenResults: ({})
    property var checkedResults: ({})
    property bool guardsPending: false

    readonly property var providers: Config.omarchyIntegration ? ({
        "fonts": {
            script: "current=$(omarchy-font-current 2>/dev/null); omarchy-font-list 2>/dev/null | while read -r f; do [[ -z $f ]] && continue; printf '%s\\t%s\\t%s\\n' \"$f\" \"$f\" \"$current\"; done",
            icon: "", volatile: true,
            actionFor: value => "omarchy-font-set " + shellQuote(value)
        },
        "power-profiles": {
            script: "current=$(powerprofilesctl get 2>/dev/null); omarchy-powerprofiles-list 2>/dev/null | while read -r p; do [[ -z $p ]] && continue; printf '%s\\t%s\\t%s\\n' \"$p\" \"$p\" \"$current\"; done",
            icon: "󰐋",
            actionFor: value => "omarchy-powerprofiles-set autodetect " + shellQuote(value)
        },
        "plugins": {
            script: "python3 " + shellQuote(pluginsScript) + " rows menu",
            icon: "󰐱", volatile: true,
            actionFor: value => "omarchy-notification-send 'Omarchy plugins' \"$(python3 " + shellQuote(pluginsScript) + " toggle " + shellQuote(value) + " 2>&1)\""
        }
    }) : ({})

    function shellQuote(value) { return "'" + String(value ?? "").replace(/'/g, "'\\''") + "'"; }
    function item(id) { return root.items[id] || null; }

    // Actions run in their own systemd scope so they outlive the shell, with the
    // omarchy-shell stand-in first on PATH for helpers that prompt through it.
    function runAction(action) {
        let command = String(action || "");
        if (command.startsWith("cedar:")) {
            Quickshell.execDetached(["python3", Quickshell.shellPath("scripts/desktop_runtime.py"), ...command.slice(6).split(" ")]);
            return;
        }
        command = command.replace(/qs -c cedar ipc call/g, "qs ipc -p " + shellQuote(Quickshell.shellPath("shell.qml")) + " call");
        if (!command) return;
        const script = (Config.omarchyIntegration ? "export PATH=" + shellQuote(root.shimDir) + ':"$PATH"\n' : "") + command;
        Quickshell.execDetached(["systemd-run", "--user", "--scope", "--quiet", "--collect", "--", "bash", "-lc", script]);
    }
    Connections {
        target: DefaultApps
        function onLaunchErrorChanged() {
            if (DefaultApps.launchError && !ShellState.locked && ShellState.panel === "") ShellState.open("menu");
        }
    }
    function launchApp(appId) {
        if (!appId) return;
        DefaultApps.launch(appId);
    }

    // ---------------------------------------------------------------- sources
    function rebuildItemsFromSources() {
        const base = MenuModel.mergeMenuSources(root.defaultItems, root.userItems);
        const merged = MenuModel.mergeMenuSources(base.itemOrder.map(id => base.items[id]), root.cedarItems);
        root.providerRevision += 1;
        root.providersLoaded = ({});
        root.providerQueue = [];
        root.items = merged.items;
        root.itemOrder = merged.itemOrder;
        root.rowsLoaded = true;
        root.evaluateGuards();
        if (root.visible) {
            root.rebuildDisplay();
            if (!root.dmenuActive) {
                if (root.filterText.trim()) root.loadProvidersForSearch();
                else root.loadProviderForMenu(root.activeMenu);
            }
        }
    }
    function refresh() { defaultMenuFile.reload(); userMenuFile.reload(); cedarMenuFile.reload(); }

    FileView {
        id: defaultMenuFile
        path: root.defaultMenuPath; watchChanges: true; printErrors: false
        onLoaded: { root.defaultItems = MenuModel.parseMenuJsonc(text()); root.rebuildItemsFromSources(); }
        onLoadFailed: { root.defaultItems = []; root.rebuildItemsFromSources(); }
        onFileChanged: reload()
    }
    FileView {
        id: userMenuFile
        path: root.userMenuPath; watchChanges: true; printErrors: false
        onLoaded: { root.userItems = MenuModel.parseMenuJsonc(text()); root.rebuildItemsFromSources(); }
        onLoadFailed: { root.userItems = []; root.rebuildItemsFromSources(); }
        onFileChanged: reload()
    }
    FileView {
        id: cedarMenuFile
        path: root.cedarMenuPath; watchChanges: true; printErrors: false
        onLoaded: { root.cedarItems = MenuModel.parseMenuJsonc(text()); root.rebuildItemsFromSources(); }
        onLoadFailed: { root.cedarItems = []; root.rebuildItemsFromSources(); }
        onFileChanged: reload()
    }

    // ------------------------------------------------------------------ apps
    function mergeAppRows() {
        const appRows = [];
        for (const entry of DefaultApps.data.apps) {
            if (!entry || !entry.visible) continue;
            const appId = String(entry.id || "");
            if (!appId) continue;
            const subtext = String(entry.description || "");
            let aliases = subtext ? [subtext] : [];
            try { if (entry.keywords && typeof entry.keywords.join === "function") aliases = aliases.concat(entry.keywords); } catch (_) {}
            appRows.push({id: "apps." + appId, parent: "apps", kind: "app", icon: "", appIcon: String(entry.icon || ""), appId: appId,
                          label: String(entry.label || appId), title: "", target: "", description: subtext, action: "", provider: "",
                          aliases: aliases, when: "", checked: "", order: 0});
        }
        const merged = MenuModel.mergeAppRows(root.items, root.itemOrder, appRows);
        root.items = merged.items;
        root.itemOrder = merged.itemOrder;
        if (root.visible) root.rebuildDisplay();
    }
    Connections {
        target: DefaultApps
        function onDataChanged() { if (root.providersLoaded["apps"]) root.mergeAppRows(); }
    }

    // ------------------------------------------------------------- providers
    function startProviderForMenu(id) {
        const entry = root.item(id);
        if (!entry || !entry.provider || root.providersLoaded[id]) return;
        if (entry.provider === "apps") { root.providersLoaded[id] = true; root.mergeAppRows(); return; }
        const spec = root.providers[entry.provider];
        if (!spec) return;
        root.providersLoaded[id] = true;
        providerProc.menuId = id; providerProc.providerKey = entry.provider;
        providerProc.revision = root.providerRevision; providerProc.collected = "";
        providerProc.command = ["bash", "-lc", spec.script];
        providerProc.running = true;
    }
    function mergeProviderRows(text, menuId, providerKey) {
        const spec = root.providers[providerKey];
        if (!spec) return;
        const taken = ({}), providerRows = [];
        for (const raw of String(text || "").split("\n")) {
            const line = raw.trim();
            if (!line) continue;
            const parts = line.split("\t");
            const label = parts[0] || "", value = parts[1] || parts[0] || "", current = parts[2] || "";
            if (!label) continue;
            let rowId = menuId + "." + MenuModel.slugify(value);
            while (taken[rowId]) rowId += "-";
            taken[rowId] = true;
            providerRows.push({id: rowId, parent: menuId, kind: "action", icon: value === current ? "✓" : (spec.icon || ""), label: label, title: "",
                               target: "", description: "", action: spec.actionFor(value), provider: "", aliases: [], when: "", checked: "", order: 0});
        }
        const merged = MenuModel.swapProviderRows(root.items, root.itemOrder, menuId, providerRows);
        root.items = merged.items;
        root.itemOrder = merged.itemOrder;
        if (root.visible) root.rebuildDisplay();
    }
    function startNextProvider() {
        if (providerProc.running) return;
        while (root.providerQueue.length > 0) {
            const id = root.providerQueue.shift();
            const entry = root.item(id);
            if (!entry || !entry.provider || root.providersLoaded[id]) continue;
            root.startProviderForMenu(id);
            return;
        }
    }
    function invalidateVolatileProvider(id) {
        const entry = root.item(id);
        const spec = entry && entry.provider ? root.providers[entry.provider] : null;
        if (spec && spec.volatile) root.providersLoaded[id] = false;
    }
    function loadProviderForMenu(id) {
        const entry = root.item(id);
        if (!entry || !entry.provider || root.providersLoaded[id]) return;
        if (entry.provider === "apps") { root.startProviderForMenu(id); return; }
        if (providerProc.running) { if (root.providerQueue.indexOf(id) < 0) root.providerQueue = root.providerQueue.concat([id]); return; }
        root.startProviderForMenu(id);
    }
    function loadProvidersForSearch() {
        const active = root.item(root.activeMenu) ? root.activeMenu : "root";
        for (const id of root.itemOrder) {
            const entry = root.item(id);
            if (!entry || !entry.provider || root.providersLoaded[entry.id]) continue;
            if (active !== "root" && entry.id !== active && !MenuModel.isDescendantOf(root.items, entry.id, active)) continue;
            root.loadProviderForMenu(entry.id);
        }
    }
    Process {
        id: providerProc
        property string menuId: ""
        property string providerKey: ""
        property string collected: ""
        property int revision: 0
        stdout: SplitParser { onRead: data => providerProc.collected += data + "\n" }
        onExited: {
            if (providerProc.revision === root.providerRevision) {
                root.mergeProviderRows(providerProc.collected, providerProc.menuId, providerProc.providerKey);
                if (root.filterText.trim()) root.loadProvidersForSearch();
            }
            root.startNextProvider();
        }
    }

    // ---------------------------------------------------------------- guards
    // `when:` and `checked:` are bash expressions, evaluated in one batch so the
    // menu opens on the last answers instead of waiting.
    function evaluateGuards() {
        if (guardProc.running) { root.guardsPending = true; return; }
        root.guardsPending = false;
        const script = MenuModel.guardScript(root.items);
        if (!script) { root.whenResults = ({}); root.checkedResults = ({}); return; }
        guardProc.collected = "";
        guardProc.command = ["bash", "-lc", script];
        guardProc.running = true;
    }
    Process {
        id: guardProc
        property string collected: ""
        stdout: SplitParser { onRead: data => guardProc.collected += data + "\n" }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0 || exitStatus !== 0) {
                if (root.guardsPending) Qt.callLater(() => root.evaluateGuards());
                return;
            }
            const nextWhen = ({}), nextChecked = ({});
            for (const raw of guardProc.collected.split("\n")) {
                const line = raw.trim();
                const colon = line.lastIndexOf(":");
                if (!line || colon < 0) continue;
                const value = line.substring(colon + 1) === "1";
                const rest = line.substring(0, colon);
                const tagAt = rest.lastIndexOf(":");
                if (tagAt < 0) continue;
                const id = rest.substring(0, tagAt), tag = rest.substring(tagAt + 1);
                if (tag === "w") nextWhen[id] = value; else if (tag === "c") nextChecked[id] = value;
            }
            root.whenResults = nextWhen;
            root.checkedResults = nextChecked;
            if (root.visible) root.rebuildDisplay();
            if (root.guardsPending) Qt.callLater(() => root.evaluateGuards());
        }
    }

    // --------------------------------------------------------------- answers
    // Compass rows for a search: arithmetic leads it, a web search (and a bare
    // address) trails it. The value or URL rides in `action`.
    function answerRow(kind, icon, label, detail, action, section) {
        return {itemId: "compass." + kind, kind: kind, icon: icon, iconFont: "", appIcon: "", appId: "", label: label, target: "",
                detail: detail, path: "", childCount: 0, action: action, provider: "", score: 0, section: section || ""};
    }
    function leadingAnswers(query) {
        const calc = Compass.evaluate(query);
        return calc ? [root.answerRow("calc", "\udb80\udcec", "= " + calc.display, calc.expression + "   ·   ENTER copies", calc.display)] : [];
    }
    function trailingAnswers(query, section) {
        const out = [], address = Compass.urlFor(query);
        if (address) out.push(root.answerRow("url", "\udb80\udf37", "Open " + address.replace(/^https?:\/\//i, ""), address, address, section));
        out.push(root.answerRow("web", "\udb81\udd9f", "Search " + Compass.engine(Config.searchEngine).label + " for \u201c" + query + "\u201d",
                                "Opens in your default browser", Compass.searchUrl(Config.searchEngine, query), section));
        return out;
    }
    function openUrl(url) {
        if (/^https?:\/\//i.test(String(url)))
            Quickshell.execDetached(["systemd-run", "--user", "--scope", "--quiet", "--collect", "--", "xdg-open", String(url)]);
    }

    // --------------------------------------------------------------- display
    function isVisibleEntry(entry) { return MenuModel.isVisible(root.items, root.itemOrder, root.whenResults, entry); }
    function displayRow(entry, detail, score, section) {
        return MenuModel.displayRow(root.items, root.itemOrder, root.checkedResults, entry, detail, score, section);
    }
    function matches(entry, query, visible) {
        if (entry.kind !== "app") return MenuModel.matchesQuery(entry, query, visible);
        const text = entry._searchName + " " + entry._searchDescription;
        return visible && query.toLowerCase().trim().split(/\s+/).every(term => text.includes(term));
    }
    function rank(entry, query) {
        if (entry.kind !== "app") return MenuModel.searchScore(root.items, entry, query);
        const needle=query.toLowerCase().trim(), label=entry._searchLabel;
        const tier=label===needle ? 0 : label.startsWith(needle) ? 10 : label.split(/\s+/).some(word=>word.startsWith(needle)) ? 20 : label.includes(needle) ? 30 : 40;
        return tier*1000;
    }
    function rebuildDisplay() {
        if (root.dmenuActive) { root.rebuildDmenuDisplay(); return; }
        if (!root.rowsLoaded) { root.rows = []; return; }
        const active = root.item(root.activeMenu) ? root.activeMenu : "root";
        root.activeMenu = active;
        const query = root.filterText.trim();
        let next = [];
        root.searchDivider = false;
        if (query) {
            const currentRows = [], drilldownRows = [];
            for (const id of root.itemOrder) {
                const entry = root.item(id);
                if (!entry || entry.id === "root") continue;
                if (!MenuModel.isDescendantOf(root.items, entry.id, active)) continue;
                if (!root.matches(entry, query, root.isVisibleEntry(entry))) continue;
                const row = root.displayRow(entry, MenuModel.parentPathFor(root.items, entry.id), root.rank(entry, query));
                if (entry.parent === active) currentRows.push(row); else drilldownRows.push(row);
            }
            const bySearch = (a, b) => a.score !== b.score ? a.score - b.score : a.path.localeCompare(b.path);
            currentRows.sort(bySearch); drilldownRows.sort(bySearch);
            root.searchDivider = currentRows.length > 0 && drilldownRows.length > 0;
            if (root.searchDivider) for (const row of drilldownRows) row.section = "drilldown";
            const found = currentRows.concat(drilldownRows);
            next = root.leadingAnswers(query).concat(found, root.trailingAnswers(query, found.length ? "compass" : ""));
        } else {
            for (const id of root.itemOrder) {
                const child = root.item(id);
                if (!child || child.parent !== active || !root.isVisibleEntry(child)) continue;
                next.push(root.displayRow(child, child.description, child.order));
            }
            if (active === "apps") next.sort((a, b) => a.label.toLowerCase().localeCompare(b.label.toLowerCase()) || a.itemId.localeCompare(b.itemId));
        }
        root.setRows(query ? next.slice(0,256) : next);
    }
    function rebuildDmenuDisplay() {
        if (root.mode === "input") { root.rows = []; return; }
        const query = root.filterText.trim().toLowerCase();
        const next = [];
        for (let i = 0; i < root.dmenuOptions.length; i++) {
            // "<label>", "<glyph>\t<label>" or "<glyph>\t<label>\t<subtext>".
            const parts = String(root.dmenuOptions[i] || "").split("\t");
            const icon = parts.length > 1 ? parts.shift() : "";
            const label = parts.shift() || "";
            const detail = parts.join("\t");
            if (query && label.toLowerCase().indexOf(query) < 0 && detail.toLowerCase().indexOf(query) < 0) continue;
            next.push({itemId: "dmenu." + i, kind: "dmenu", icon: icon, iconFont: "", appIcon: "", appId: "", label: label, target: "",
                       detail: detail, path: "", childCount: 0, action: "", provider: "", score: i, section: ""});
        }
        root.setRows(query ? next.slice(0,256) : next);
    }
    function clampSelection() {
        if (root.rows.length === 0) root.selectedIndex = 0;
        else if (root.selectedIndex >= root.rows.length) root.selectedIndex = root.rows.length - 1;
        else if (root.selectedIndex < 0) root.selectedIndex = 0;
    }

    // ------------------------------------------------------------ navigation
    function select(delta) {
        if (root.rows.length === 0) return;
        root.selectedIndex = (root.selectedIndex + delta + root.rows.length) % root.rows.length;
    }
    function setFilter(next) {
        root.resetSelection = true;
        root.filterText = next;
        root.selectedIndex = 0;
        if (!root.dmenuActive && root.filterText.trim()) root.loadProvidersForSearch();
        root.rebuildDisplay();
    }
    function setActiveMenu(id, pushHistory) {
        if (!root.item(id)) id = "root";
        if (pushHistory && id !== root.activeMenu) root.navStack = root.navStack.concat([root.activeMenu]);
        root.activeMenu = id;
        root.filterText = "";
        root.selectedIndex = 0;
        root.rebuildDisplay();
        root.invalidateVolatileProvider(id);
        root.loadProviderForMenu(id);
    }
    function goBack() {
        if (root.dmenuActive || root.activeMenu === "root") return false;
        if (root.navStack.length > 0) {
            const previous = root.navStack[root.navStack.length - 1];
            root.navStack = root.navStack.slice(0, -1);
            root.setActiveMenu(previous, false);
            return true;
        }
        const active = root.item(root.activeMenu);
        root.setActiveMenu(active && active.parent ? active.parent : "root", false);
        return true;
    }
    function activateIndex(index) {
        if (root.dmenuActive) {
            if (root.mode === "input") { root.applyDmenuSelection(root.filterText); return; }
            if (index < 0 || index >= root.rows.length) return;
            const picked = root.rows[index];
            root.applyDmenuSelection(picked.detail ? picked.label + "\t" + picked.detail : picked.label);
            return;
        }
        if (index < 0 || index >= root.rows.length) return;
        const row = root.rows[index];
        if (row.kind === "calc") { root.hide(); Quickshell.execDetached(["wl-copy", "--", String(row.action)]); return; }
        if (row.kind === "web" || row.kind === "url") { root.hide(); root.openUrl(row.action); return; }
        Forest.record("go","Go / "+row.label,row.itemId || row.appId || row.label);
        if (row.kind === "menu" || row.kind === "link") root.setActiveMenu(row.target || row.itemId, true);
        else if (row.kind === "app") { root.hide(); root.launchApp(row.appId); }
        else { root.hide(); root.runAction(row.action); }
    }

    // -------------------------------------------------------------- requests
    function finishRequest(selection) {
        if (!root.requestActive || !root.doneFile) return;
        const selectionFile = root.selectionFile, doneFile = root.doneFile;
        root.requestActive = false; root.selectionFile = ""; root.doneFile = "";
        root.replyQueue = root.replyQueue.concat([{selectionFile: selectionFile, doneFile: doneFile, selection: selection === undefined ? null : selection}]);
        root.flushReplies();
    }
    // Replies are written one at a time, in order, by the validating helper.
    property var replyQueue: []
    function flushReplies() {
        if (replyProc.running || !root.replyQueue.length) return;
        const next = root.replyQueue[0];
        root.replyQueue = root.replyQueue.slice(1);
        replyProc.send(next);
    }
    ServiceRequest {
        id: replyProc; script: "scripts/menu_reply.py"; timeoutMs: 5000
        onRunningChanged: if (!running) Qt.callLater(root.flushReplies)
    }
    // Answer first: hiding the panel runs onHidden, which cancels any open request.
    function applyDmenuSelection(value) { root.finishRequest(value); root.hide(); }
    function hide() { if (root.visible) ShellState.close(); root.filterText = ""; }
    function cancel() { root.finishRequest(null); root.hide(); }
    function onHidden() { if (root.requestActive) root.finishRequest(null); root.mode = "menu"; root.filterText = ""; }
    Connections {
        target: ShellState
        function onPanelChanged() { if (!root.visible) root.onHidden(); }
    }

    // ------------------------------------------------------------- entrances
    function resolveRoute(input) { return MenuModel.resolveRoute(root.items, root.itemOrder, input); }
    function openRoute(initialMenu) {
        let id = root.resolveRoute(initialMenu);
        const entry = root.items[id];
        if (entry && entry.kind === "action" && entry.action) { root.hide(); root.runAction(entry.action); return; }
        if (entry && entry.kind === "link" && entry.target) id = entry.target;
        if (root.requestActive) root.finishRequest(null);
        root.mode = "menu";
        root.activeMenu = root.item(id) ? id : "root";
        root.navStack = [];
        root.filterText = "";
        root.selectedIndex = 0;
        root.evaluateGuards();
        ShellState.open("menu");
        root.rebuildDisplay();
        root.invalidateVolatileProvider(root.activeMenu);
        root.loadProviderForMenu(root.activeMenu);
    }
    function toggle(route) {
        if (root.visible && !root.dmenuActive) root.hide();
        else root.openRoute(route || "root");
    }
    function summon(payloadJson) {
        let payload = ({});
        if (String(payloadJson || "").length > 262144) return; // 256 KiB is far beyond any prompt.
        try { payload = JSON.parse(payloadJson || "{}") || ({}); } catch (_) { payload = ({}); }
        if (!payload || typeof payload !== "object") return;
        if (payload.mode === "select" || payload.mode === "input") root.openDmenu(payload);
        else root.openRoute(payload.initialMenu || payload.menu || "root");
    }
    // Reply paths must look like the mktemp names Omarchy's helpers create;
    // scripts/menu_reply.py enforces ownership and exclusivity when writing.
    function replyPath(value) {
        const path = String(value || "");
        return path.startsWith("/") && !/[\n\0]/.test(path) && path.length <= 4096 ? path : "";
    }
    function openDmenu(payload) {
        if (root.requestActive) root.finishRequest(null);
        root.mode = payload.mode === "input" ? "input" : "select";
        root.dmenuPrompt = String(payload.prompt || (root.mode === "input" ? "Input" : "Select")).slice(0, 200);
        root.dmenuOptions = (Array.isArray(payload.options) ? payload.options : []).slice(0, 2000).map(o => String(o).slice(0, 1000));
        root.selectionFile = root.replyPath(payload.selectionFile);
        root.doneFile = root.replyPath(payload.doneFile);
        root.requestActive = !!root.doneFile;
        root.dmenuWidth = Math.max(0, Number(payload.width || 0));
        root.dmenuMaxHeight = Math.max(0, Number(payload.maxHeight || 0));
        root.navStack = [];
        root.filterText = "";
        root.selectedIndex = 0;
        ShellState.open("menu");
        root.rebuildDisplay();
    }
}
