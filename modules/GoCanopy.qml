import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import ".."
import "../components"
import "../services"
import "../components/Compass.js" as Compass

// Applications, as a bar drop, and the whole menu with it. At the root: a
// search filament, favourites pinned above the rest, the apps you launched
// last, an icon grid that answers the keyboard, and the menu's other trails
// (System, CEDAR's own panels and, on Omarchy, its menu) as chips under the
// grid. A trail opens in place with a breadcrumb and Backspace on an empty
// search climbs back out. A script's select or input prompt (`menu summon`)
// takes the drop over until it is answered or cancelled. Arithmetic typed into
// the search answers above the grid and a web search (or a bare address)
// waits below it, so every query has somewhere to go. The Go service keeps
// the menu tree, the prompts and the actions; launching goes through DefaultApps.
ColumnLayout {
    id: root
    property bool active: false
    property string query: ""
    property int selected: 0
    // After an arrow key the keyboard is on the tiles: F then marks a favourite.
    // Typing anything returns the keys to the search field.
    property bool browsing: false
    readonly property int columns: width < 380 ? 3 : 4
    readonly property int tileHeight: 92
    readonly property int tileGap: 8
    readonly property int visibleRows: 5
    readonly property int rowHeight: 44
    readonly property int rowGap: 3
    readonly property int visibleMenuRows: 10
    spacing: 12
    function beat(order, span = .4) { return Canopy.ease(.06 * order, span); }
    function focusSearch() { field.forceActiveFocus(); }

    // The drop's three faces: the catalog at the menu's root, a trail into the
    // menu, and a script's select or input prompt.
    readonly property bool prompting: Go.dmenuActive
    readonly property bool onTrail: !prompting && Go.activeMenu !== "root"
    readonly property bool catalog: !prompting && !onTrail
    readonly property bool inputPrompt: prompting && Go.mode === "input"

    readonly property var all: (DefaultApps.data.apps || []).filter(a => a && a.visible !== false && a.id)
    readonly property var favouriteIds: Config.saved.goFavorites || []
    // Favourites keep the order they were marked in.
    readonly property var favourites: favouriteIds.map(id => root.all.find(a => a.id === id)).filter(Boolean)
    readonly property var matches: {
        if (!root.catalog)
            return [];
        const q = root.query.toLowerCase().trim();
        if (!q)
            return root.all.filter(a => !root.favouriteIds.includes(a.id));
        const terms = q.split(/\s+/), scored = [];
        for (const a of root.all) {
            const label = String(a.label || "").toLowerCase();
            const text = label + " " + String(a.description || "").toLowerCase() + " " + (Array.isArray(a.keywords) ? a.keywords.join(" ").toLowerCase() : "");
            if (!terms.every(t => text.includes(t)))
                continue;
            const tier = label === q ? 0 : label.startsWith(q) ? 1 : label.split(/\s+/).some(w => w.startsWith(q)) ? 2 : label.includes(q) ? 3 : 4;
            scored.push({ app: a, tier: tier });
        }
        scored.sort((x, y) => x.tier - y.tier || String(x.app.label).localeCompare(String(y.app.label)));
        return scored.map(s => s.app);
    }
    // Compass answers: arithmetic leads, a web search or address trails. Each
    // answers the keyboard like a tile; apps carry no `kind`.
    readonly property var calc: root.catalog && root.query.trim() ? Compass.evaluate(root.query) : null
    readonly property string address: root.catalog ? Compass.urlFor(root.query) : ""
    readonly property var answers: root.calc ? [{ kind: "calc", id: "compass.calc", label: "= " + root.calc.display, detail: root.calc.expression, value: root.calc.display }] : []
    readonly property var trailing: {
        const q = root.query.trim();
        if (!q || !root.catalog)
            return [];
        const out = [];
        if (root.address)
            out.push({ kind: "url", id: "compass.url", label: "Open " + root.address.replace(/^https?:\/\//i, ""), detail: root.address, url: root.address });
        out.push({ kind: "web", id: "compass.web", label: "Search " + Compass.engine(Config.searchEngine).label + " for “" + q + "”",
                   detail: "Opens in your default browser", url: Compass.searchUrl(Config.searchEngine, q) });
        return out;
    }
    // The menu at the root: its other trails while nothing is typed, or what
    // the query finds anywhere in the tree. The Go service lists them; apps
    // (the grid has them) and Compass rows (the drop has its own) are left out.
    // A search shows the eight best.
    readonly property var menuRows: {
        if (!root.catalog)
            return [];
        const out = [];
        for (const row of Go.rows) {
            if (["app", "calc", "web", "url", "dmenu"].includes(row.kind) || row.itemId === "apps" || row.target === "apps")
                continue;
            out.push(row);
            if (root.query && out.length >= 8)
                break;
        }
        return out;
    }
    // One flat list for the keyboard: answers, favourites (while there is no
    // query), matches, the menu, then the web search.
    readonly property var pinned: root.query || !root.catalog ? [] : root.favourites
    readonly property var tail: root.menuRows.concat(root.trailing)
    readonly property var shown: root.answers.concat(root.pinned, root.matches, root.tail)
    // The last four apps launched from the drop.
    readonly property var recents: {
        const seen = {}, out = [];
        for (const t of Forest.trails) {
            if (t.kind !== "go" || !String(t.target).startsWith("apps."))
                continue;
            const id = String(t.target).slice(5);
            if (seen[id])
                continue;
            const app = root.all.find(a => a.id === id);
            if (app) { seen[id] = true; out.push(app); }
            if (out.length >= 4)
                break;
        }
        return out;
    }
    function isFavourite(app) { return !!app && !app.kind && root.favouriteIds.includes(app.id); }
    function toggleFavourite(app) {
        if (!app || app.kind)
            return;
        const ids = root.favouriteIds.slice();
        Config.set("goFavorites", ids.includes(app.id) ? ids.filter(id => id !== app.id) : ids.concat([app.id]));
    }
    function iconSource(app) { return Config.imageSource(Quickshell.iconPath(app.icon || "application-x-executable", true)); }
    function launch(app) {
        if (!app)
            return;
        Forest.record("go", "Applications / " + app.label, "apps." + app.id);
        DefaultApps.launch(app.id);
        Canopy.close();
    }
    // Answers and menu rows stack one per row above and below the grid, so a
    // vertical step (±columns) moves one row at a time and crosses into the
    // grid's edge.
    function move(delta) {
        root.browsing = true;
        if (!root.shown.length)
            return;
        const head = root.answers.length, grid = root.pinned.length + root.matches.length, i = root.selected;
        let next = i + delta;
        if (Math.abs(delta) === root.columns && root.columns > 1) {
            if (i < head || i >= head + grid)
                next = i + (delta > 0 ? 1 : -1);
            else if (next >= head + grid)
                next = root.tail.length ? head + grid : i;
            else if (next < head)
                next = head ? head - 1 : i;
        }
        root.selected = Math.max(0, Math.min(root.shown.length - 1, next));
    }
    function activate(item) {
        if (!item)
            return;
        if (item.kind === "calc") {
            Quickshell.execDetached(["wl-copy", "--", String(item.value)]);
            Canopy.close();
        } else if (item.kind === "web" || item.kind === "url") {
            root.openUrl(item.url);
            Canopy.close();
        } else if (item.kind)
            Go.activateRow(item);
        else
            root.launch(item);
    }
    // The default browser gets the URL in its own scope so it outlives the shell.
    function openUrl(url) {
        if (/^https?:\/\//i.test(String(url)))
            Quickshell.execDetached(["systemd-run", "--user", "--scope", "--quiet", "--collect", "--", "xdg-open", String(url)]);
    }
    // Keys on a trail or in a prompt drive the Go service's own selection.
    function menuKeys(event) {
        const row = Go.rows[Go.selectedIndex];
        switch (event.key) {
        case Qt.Key_Down: case Qt.Key_Tab: Go.select(1); break;
        case Qt.Key_Up: case Qt.Key_Backtab: Go.select(-1); break;
        case Qt.Key_PageDown: Go.select(6); break;
        case Qt.Key_PageUp: Go.select(-6); break;
        case Qt.Key_Return: case Qt.Key_Enter: Go.activateIndex(Go.selectedIndex); break;
        case Qt.Key_Right:
            if (root.prompting || !row || (row.kind !== "menu" && row.kind !== "link"))
                return;
            Go.activateIndex(Go.selectedIndex);
            break;
        case Qt.Key_Left: case Qt.Key_Backspace:
            if (root.prompting || field.text)
                return;
            Go.goBack();
            break;
        case Qt.Key_Escape:
            if (field.text) field.text = ""; else Go.cancel();
            break;
        default: return;
        }
        event.accepted = true;
    }
    function rearm() {
        root.selected = 0;
        root.browsing = false;
        flick.contentY = 0;
        Qt.callLater(() => field.forceActiveFocus());
    }
    onActiveChanged: {
        if (active) {
            field.text = "";
            root.query = "";
            root.rearm();
        }
    }
    onQueryChanged: { root.selected = 0; flick.contentY = 0; }
    // The service clears its filter when a trail opens or a prompt arrives;
    // the field follows it, and the keyboard returns to the field.
    Connections {
        target: Go
        function onFilterTextChanged() { if (field.text !== Go.filterText) field.text = Go.filterText; }
        function onModeChanged() { root.rearm(); }
        function onActiveMenuChanged() { root.rearm(); }
    }
    // Keep the selected tile in view when the keyboard moves it through the grid.
    onSelectedChanged: {
        const inGrid = root.selected - root.answers.length - root.pinned.length;
        if (inGrid < 0) { flick.contentY = 0; return; }
        if (inGrid >= root.matches.length)
            return;
        const row = Math.floor(inGrid / root.columns), step = root.tileHeight + root.tileGap;
        const top = row * step, bottom = top + root.tileHeight;
        if (top < flick.contentY)
            flick.contentY = top;
        else if (bottom > flick.contentY + flick.height)
            flick.contentY = Math.max(0, bottom - flick.height);
    }

    // One tile, used by the favourites row and the grid. `flat` is its index
    // in the keyboard's list; `order` sets its entrance beat.
    component AppTile: Item {
        id: tile
        property var app: null
        property int flat: 0
        property int order: 0
        readonly property bool current: flat === root.selected
        readonly property bool favourite: root.isFavourite(app)
        readonly property real sweep: root.beat(3 + Math.min(order, 11) * .6, .35)
        Layout.fillWidth: true; Layout.preferredWidth: 1
        implicitHeight: root.tileHeight
        opacity: sweep
        scale: .92 + .08 * sweep
        Accessible.role: Accessible.Button
        Accessible.name: "Launch " + (app?.label || "") + (favourite ? ", favourite" : "")
        ChamferFrame {
            anchors.fill: parent
            cut: Theme.strataCut
            fill: tile.current ? Qt.alpha(Theme.strataAccent, .07) : hover.containsMouse ? Qt.alpha(Theme.strataAccent, .05) : Qt.alpha(Theme.strataFoundation, .5)
            stroke: tile.current ? Qt.alpha(Theme.strataAccent, .55) : tile.favourite ? Qt.alpha(Theme.amber, .3) : hover.containsMouse ? Qt.alpha(Theme.strataAccent, .35) : Qt.alpha(Theme.strataAccent, .13)
            line: tile.current; lineColor: Theme.strataAccent; lineFraction: .55
        }
        Column {
            anchors.centerIn: parent
            width: parent.width - 12
            spacing: 8
            Image {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 34; height: 34
                sourceSize.width: 68; sourceSize.height: 68
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                source: tile.app ? root.iconSource(tile.app) : ""
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: tile.app?.label || ""
                textFormat: Text.PlainText
                elide: Text.ElideRight
                font.family: Theme.dataFont
                font.pixelSize: 11
                color: tile.current ? Theme.strataAccent : Theme.strataText
            }
        }
        MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPositionChanged: root.selected = tile.flat
            onClicked: root.launch(tile.app)
        }
        // The favourite mark: amber when set, faint while hovering, click to toggle.
        Text {
            id: star
            anchors.top: parent.top; anchors.right: parent.right
            anchors.topMargin: 6; anchors.rightMargin: 8
            text: tile.favourite ? "★" : "☆"
            textFormat: Text.PlainText
            font.pixelSize: 12
            color: tile.favourite ? Theme.amber : Theme.strataMuted
            opacity: tile.favourite ? .95 : hover.containsMouse || starHover.containsMouse ? .55 : 0
            Behavior on opacity { enabled: !Theme.reducedMotion; NumberAnimation { duration: 120 } }
            MouseArea {
                id: starHover
                anchors.fill: parent; anchors.margins: -6
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleFavourite(tile.app)
            }
        }
    }

    // One answer: a glyph, the answer, what it came from, and what Enter does.
    component AnswerRow: Item {
        id: answer
        property var item: null
        property int flat: 0
        property real order: 0
        readonly property bool current: flat === root.selected
        readonly property bool isCalc: item?.kind === "calc"
        readonly property real sweep: root.beat(order, .35)
        Layout.fillWidth: true
        implicitHeight: 46
        opacity: sweep
        transform: Translate { y: 6 * (1 - answer.sweep) }
        Accessible.role: Accessible.Button
        Accessible.name: item?.label || ""
        ChamferFrame {
            anchors.fill: parent
            cut: Theme.strataCut
            fill: answer.current ? Qt.alpha(Theme.strataAccent, .07) : answerHover.containsMouse ? Qt.alpha(Theme.strataAccent, .05) : Qt.alpha(Theme.strataFoundation, .5)
            stroke: answer.current ? Qt.alpha(Theme.strataAccent, .55) : answerHover.containsMouse ? Qt.alpha(Theme.strataAccent, .35) : Qt.alpha(Theme.strataAccent, .13)
            line: answer.current; lineColor: Theme.strataAccent; lineFraction: .55
        }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14; anchors.rightMargin: 14
            spacing: 12
            Text {
                text: answer.isCalc ? "󰃬" : answer.item?.kind === "url" ? "󰌷" : "󰖟"
                textFormat: Text.PlainText
                font.family: Theme.dataFont; font.pixelSize: 18
                color: answer.current ? Theme.strataAccent : Theme.strataAccent
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Text {
                    Layout.fillWidth: true
                    text: answer.item?.label || ""
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    font.family: answer.isCalc ? Theme.dataFont : Theme.labelFont
                    font.pixelSize: answer.isCalc ? 17 : 14
                    font.weight: Font.DemiBold
                    color: answer.current ? Theme.white : Theme.strataText
                }
                Text {
                    Layout.fillWidth: true
                    text: answer.item?.detail || ""
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    font.family: Theme.dataFont; font.pixelSize: 10
                    color: Theme.strataMuted
                }
            }
            Text {
                visible: answer.current
                text: answer.isCalc ? "ENTER COPIES" : "ENTER OPENS"
                textFormat: Text.PlainText
                font.family: Theme.dataFont; font.pixelSize: 9; font.letterSpacing: 1
                color: Theme.strataMuted
            }
        }
        MouseArea {
            id: answerHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPositionChanged: root.selected = answer.flat
            onClicked: root.activate(answer.item)
        }
    }

    // One menu row, as the Go service lists it: a glyph or app icon, the
    // label, its detail, and a trail mark when it opens a submenu. Whoever
    // places it decides what "current" means and what a click does.
    component MenuRow: Item {
        id: entry
        property var row: null
        property bool current: false
        signal hovered()
        signal picked()
        readonly property bool submenu: !!entry.row && (entry.row.kind === "menu" || entry.row.kind === "link")
        readonly property bool isApp: !!entry.row && entry.row.kind === "app"
        readonly property string appIconSource: isApp ? Quickshell.iconPath(entry.row.appIcon || "application-x-executable", true) : ""
        readonly property string detail: entry.row ? String(entry.row.detail || "") : ""
        Layout.fillWidth: true
        implicitHeight: root.rowHeight
        Accessible.role: Accessible.Button
        Accessible.name: (entry.row ? String(entry.row.label || "") : "") + (submenu ? ", opens a trail" : "")
        ChamferFrame {
            anchors.fill: parent
            cut: 7
            fill: entry.current ? Qt.alpha(Theme.strataAccent, .07) : rowHover.containsMouse ? Qt.alpha(Theme.strataAccent, .05) : Qt.alpha(Theme.strataFoundation, .5)
            stroke: entry.current ? Qt.alpha(Theme.strataAccent, .55) : rowHover.containsMouse ? Qt.alpha(Theme.strataAccent, .35) : Qt.alpha(Theme.strataAccent, .13)
            line: entry.current; lineColor: Theme.strataAccent; lineFraction: .55
        }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12; anchors.rightMargin: 12
            spacing: 10
            Item {
                Layout.preferredWidth: 24; Layout.preferredHeight: 24
                Text {
                    anchors.centerIn: parent
                    visible: !entry.isApp
                    text: entry.row && entry.row.icon ? String(entry.row.icon) : (entry.submenu ? "▸" : "◦")
                    textFormat: Text.PlainText
                    font.family: entry.row && entry.row.iconFont ? String(entry.row.iconFont) : Theme.dataFont
                    font.pixelSize: 16
                    color: entry.current ? Theme.strataAccent : Theme.strataAccent
                }
                Image {
                    anchors.centerIn: parent
                    visible: entry.isApp && entry.appIconSource !== ""
                    source: entry.appIconSource ? Config.imageSource(entry.appIconSource) : ""
                    width: 20; height: 20
                    sourceSize.width: 40; sourceSize.height: 40
                    fillMode: Image.PreserveAspectFit; asynchronous: true
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Text {
                    Layout.fillWidth: true
                    text: entry.row ? String(entry.row.label || "") : ""
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    font.family: Theme.labelFont; font.pixelSize: 14; font.weight: Font.DemiBold
                    color: entry.current ? Theme.white : Theme.strataText
                }
                Text {
                    Layout.fillWidth: true
                    visible: entry.detail !== ""
                    text: entry.detail
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    font.family: Theme.dataFont; font.pixelSize: 10
                    color: Theme.strataMuted
                }
            }
            Text {
                visible: entry.submenu
                text: entry.row && entry.row.childCount > 0 ? entry.row.childCount + " ›" : "›"
                textFormat: Text.PlainText
                font.family: Theme.dataFont; font.pixelSize: 12
                color: entry.current ? Theme.strataAccent : Theme.strataMuted
            }
        }
        MouseArea {
            id: rowHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPositionChanged: entry.hovered()
            onClicked: entry.picked()
        }
    }

    // The heading: the catalog's counts, a trail's breadcrumb with its way
    // back, or the prompt's name.
    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        opacity: root.beat(0)
        transform: Translate { y: 6 * (1 - root.beat(0)) }
        StrataButton {
            visible: root.onTrail
            iconOnly: true
            implicitWidth: 28; implicitHeight: 24
            text: "‹"
            hint: "Back (Backspace)"
            onClicked: Go.goBack()
        }
        SectionMark {
            Layout.fillWidth: true
            elide: Text.ElideRight
            text: root.prompting ? "PROMPT" : root.onTrail ? "MENU › " + Go.breadcrumb.toUpperCase() : "APPLICATIONS"
            tone: root.prompting ? Theme.amber : Theme.strataAccent
        }
        StatusPill { visible: root.catalog && root.favourites.length > 0; text: root.favourites.length + (root.favourites.length === 1 ? " favourite" : " favourites"); tone: Theme.amber }
        StatusPill { visible: root.catalog; text: DefaultApps.error ? "Catalog offline" : root.all.length + " apps"; tone: DefaultApps.error ? Theme.amber : Theme.strataAccent }
        StatusPill { visible: root.onTrail && Go.rows.length > 0 && !field.text; text: Go.rows.length + (Go.rows.length === 1 ? " entry" : " entries"); tone: Theme.strataAccent }
        StatusPill { visible: root.prompting; text: root.inputPrompt ? "Script asks for text" : "Script asks for a choice"; tone: Theme.amber }
    }
    GlowText {
        visible: root.prompting
        Layout.fillWidth: true
        text: Go.dmenuPrompt
        color: Theme.strataAccent
        font.family: Theme.labelFont; font.pixelSize: 20; font.weight: Font.DemiBold
        elide: Text.ElideRight
    }

    // Search: a filament lights under the field as the panel enters, turns
    // green while the query finds something and amber when it finds nothing.
    // On a trail it searches that trail; in a prompt it filters the choices
    // or carries the answer.
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 6
        opacity: root.beat(1)
        transform: Translate { y: 6 * (1 - root.beat(1)) }
        StrataField {
            id: field
            objectName: "goSearch"
            Layout.fillWidth: true
            placeholderText: root.inputPrompt ? "Type your answer, then ENTER" : root.prompting ? "Type to filter the choices" : root.onTrail ? "Type to search this trail" : "Type an app, a sum, an address or a web search"
            Accessible.name: root.inputPrompt ? "Answer" : root.prompting ? "Filter choices" : root.onTrail ? "Search this trail" : "Search applications"
            onTextChanged: {
                root.query = root.catalog ? text : "";
                root.browsing = false;
                if (Go.filterText !== text)
                    Go.setFilter(text);
            }
            Keys.onPressed: event => {
                if (!root.catalog) { root.menuKeys(event); return; }
                switch (event.key) {
                case Qt.Key_Down: root.move(root.columns); break;
                case Qt.Key_Up: root.move(-root.columns); break;
                case Qt.Key_Right: root.move(1); break;
                case Qt.Key_Left: root.move(-1); break;
                case Qt.Key_Tab: root.move(1); break;
                case Qt.Key_Backtab: root.move(-1); break;
                case Qt.Key_Return: case Qt.Key_Enter: root.activate(root.shown[root.selected]); break;
                case Qt.Key_Escape: if (text) text = ""; else Canopy.close(); break;
                case Qt.Key_F:
                    if (!root.browsing || event.modifiers & (Qt.ControlModifier | Qt.AltModifier))
                        return;
                    root.toggleFavourite(root.shown[root.selected]);
                    break;
                default: return;
                }
                event.accepted = true;
            }
        }
        Item {
            Layout.fillWidth: true
            implicitHeight: 2
            readonly property bool found: root.catalog ? (root.matches.length || root.answers.length || root.menuRows.length) : Go.rows.length > 0
            Rectangle { width: parent.width; height: 1; y: 1; color: Qt.alpha(Theme.strataAccent, .12) }
            Rectangle {
                width: parent.width * (field.text ? 1 : .55 * root.beat(1, .6))
                height: field.text ? 2 : 1
                color: field.text ? (parent.found || root.inputPrompt ? Theme.strataAccent : Theme.amber) : Theme.strataAccent
                opacity: field.text ? .85 : .5
                Behavior on width { enabled: !Theme.reducedMotion; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                Rectangle { anchors.right: parent.right; width: 24; height: parent.height; color: Theme.strataAccent; opacity: field.text ? 0 : .8 * (1 - root.beat(.5, .4)) }
            }
        }
        // What the field answers, shown until something is typed so nobody has
        // to find the calculator or the web search by accident.
        Flow {
            Layout.fillWidth: true
            visible: root.catalog && !root.query
            spacing: 18
            opacity: root.beat(1.6, .4) * .9
            Repeater {
                model: [
                    { glyph: "󰃬", example: "2+2", does: "answers, ENTER copies" },
                    { glyph: "󰌷", example: "docs.rs", does: "opens the address" },
                    { glyph: "󰖟", example: "anything else", does: "searches " + Compass.engine(Config.searchEngine).label }
                ]
                Row {
                    required property var modelData
                    spacing: 6
                    Text { anchors.verticalCenter: parent.verticalCenter; text: parent.modelData.glyph; textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: 12; color: Theme.strataAccent }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: parent.modelData.example; textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: 10; color: Theme.strataText }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: parent.modelData.does; textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: 10; color: Theme.strataMuted }
                }
            }
        }
    }

    // The arithmetic answer, when the query is a sum.
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 8
        visible: root.answers.length > 0
        SectionMark { text: "ANSWER"; size: 9; tone: Theme.strataAccent }
        Repeater {
            model: root.answers
            AnswerRow { required property var modelData; required property int index; item: modelData; flat: index; order: 1.5 }
        }
    }

    // Favourites: pinned above everything while there is no query.
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 8
        visible: root.pinned.length > 0
        opacity: root.beat(2)
        transform: Translate { y: 6 * (1 - root.beat(2)) }
        RowLayout {
            Layout.fillWidth: true
            SectionMark { text: "FAVOURITES"; size: 9; tone: Theme.amber }
            Item { Layout.fillWidth: true }
            Text { text: "F while browsing marks or clears one"; textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: 9; font.letterSpacing: 1; color: Theme.strataMuted }
        }
        GridLayout {
            Layout.fillWidth: true
            columns: root.columns
            columnSpacing: root.tileGap; rowSpacing: root.tileGap
            uniformCellWidths: true
            Repeater {
                model: root.pinned
                AppTile { required property var modelData; required property int index; app: modelData; flat: root.answers.length + index; order: index }
            }
        }
    }

    // Recent: the last apps launched, as chips.
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 8
        visible: root.catalog && !root.query && root.recents.length > 0
        opacity: root.beat(2)
        transform: Translate { y: 6 * (1 - root.beat(2)) }
        SectionMark { text: "RECENT"; size: 9; tone: Theme.strataMuted }
        Flow {
            Layout.fillWidth: true
            spacing: 8
            Repeater {
                model: root.recents
                StrataButton {
                    id: chip
                    required property var modelData
                    implicitHeight: 32
                    text: modelData.label
                    hint: "Launch " + modelData.label
                    onClicked: root.launch(modelData)
                    contentItem: Row {
                        spacing: 8
                        Image { anchors.verticalCenter: parent.verticalCenter; width: 16; height: 16; sourceSize.width: 32; sourceSize.height: 32; fillMode: Image.PreserveAspectFit; asynchronous: true; source: root.iconSource(chip.modelData) }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: chip.text; textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: Theme.small; color: Theme.strataText }
                    }
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        visible: root.catalog
        opacity: root.beat(3)
        SectionMark { text: root.query ? "MATCHES" : "ALL APPS"; size: 9; tone: Theme.strataMuted }
        Item { Layout.fillWidth: true }
        Text {
            visible: root.query !== "" && root.matches.length > 0
            text: root.matches.length + (root.matches.length === 1 ? " match" : " matches")
            textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: 9; font.letterSpacing: 1; color: Theme.strataMuted
        }
    }
    // The grid scrolls under the fixed search field; five rows show at once.
    Flickable {
        id: flick
        visible: root.catalog
        Layout.fillWidth: true
        implicitHeight: root.catalog ? Math.min(grid.implicitHeight, root.visibleRows * root.tileHeight + (root.visibleRows - 1) * root.tileGap) : 0
        contentWidth: width
        contentHeight: grid.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: flick.contentHeight > flick.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }
        GridLayout {
            id: grid
            width: flick.width - (flick.contentHeight > flick.height ? 10 : 0)
            columns: root.columns
            columnSpacing: root.tileGap; rowSpacing: root.tileGap
            uniformCellWidths: true
            Repeater {
                model: root.matches
                AppTile { required property var modelData; required property int index; app: modelData; flat: root.answers.length + root.pinned.length + index; order: root.pinned.length + index }
            }
        }
    }
    Column {
        Layout.fillWidth: true
        visible: root.catalog && root.pinned.length + root.matches.length === 0
        spacing: 6
        GlowText { anchors.horizontalCenter: parent.horizontalCenter; text: "󰈉"; color: Theme.strataAccent; font.pixelSize: 28 }
        GlowText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.query ? "No app named “" + root.query + "”" : DefaultApps.error ? DefaultApps.error : "Reading the application catalog…"
            color: Theme.strataMuted
        }
    }

    // The menu under the grid: its trails as chips while nothing is typed,
    // the entries a query finds anywhere in it as rows.
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 8
        visible: root.menuRows.length > 0
        opacity: root.beat(3.5)
        RowLayout {
            Layout.fillWidth: true
            SectionMark { text: root.query ? "IN THE MENU" : "MENU"; size: 9; tone: Theme.strataMuted }
            Item { Layout.fillWidth: true }
            Text { visible: !root.query; text: "Trails open here · BACKSPACE climbs back"; textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: 9; font.letterSpacing: 1; color: Theme.strataMuted }
        }
        Flow {
            Layout.fillWidth: true
            visible: !root.query
            spacing: 8
            Repeater {
                model: root.query ? [] : root.menuRows
                StrataButton {
                    id: trailChip
                    required property var modelData
                    required property int index
                    readonly property int flat: root.answers.length + root.pinned.length + root.matches.length + index
                    readonly property bool submenu: modelData.kind === "menu" || modelData.kind === "link"
                    implicitHeight: 32
                    checked: flat === root.selected
                    text: modelData.label
                    hint: submenu ? "Open " + modelData.label : modelData.label
                    onHoveredChanged: if (hovered) root.selected = flat
                    onClicked: root.activate(modelData)
                    contentItem: Row {
                        spacing: 8
                        Text { anchors.verticalCenter: parent.verticalCenter; visible: text !== ""; text: trailChip.modelData.icon ? String(trailChip.modelData.icon) : ""; textFormat: Text.PlainText; font.family: trailChip.modelData.iconFont ? String(trailChip.modelData.iconFont) : Theme.dataFont; font.pixelSize: 13; color: trailChip.checked ? Theme.strataAccent : Theme.strataAccent }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: trailChip.text + (trailChip.submenu ? "  ›" : ""); textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: Theme.small; color: trailChip.checked ? Theme.strataAccent : Theme.strataText }
                    }
                }
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            visible: root.query !== ""
            spacing: root.rowGap
            Repeater {
                model: root.query ? root.menuRows : []
                MenuRow {
                    required property var modelData
                    required property int index
                    readonly property int flat: root.answers.length + root.pinned.length + root.matches.length + index
                    row: modelData
                    current: flat === root.selected
                    onHovered: root.selected = flat
                    onPicked: root.activate(modelData)
                }
            }
        }
    }
    // The web search (and a bare address) under everything the query found.
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 8
        visible: root.trailing.length > 0
        SectionMark { text: "ELSEWHERE"; size: 9; tone: Theme.strataMuted }
        Repeater {
            model: root.trailing
            AnswerRow { required property var modelData; required property int index; item: modelData; flat: root.answers.length + root.pinned.length + root.matches.length + root.menuRows.length + index; order: 4 }
        }
    }

    // A trail or a prompt: the Go service's rows, ten at a time, following
    // its selection.
    ListView {
        id: list
        visible: !root.catalog && !root.inputPrompt && count > 0
        Layout.fillWidth: true
        implicitHeight: visible ? Math.min(count, root.visibleMenuRows) * (root.rowHeight + root.rowGap) - root.rowGap : 0
        clip: true
        spacing: root.rowGap
        boundsBehavior: Flickable.StopAtBounds
        model: Go.displayModel
        currentIndex: Go.selectedIndex
        highlightFollowsCurrentItem: false
        onCurrentIndexChanged: if (visible) positionViewAtIndex(currentIndex, ListView.Contain)
        ScrollBar.vertical: ScrollBar { policy: list.contentHeight > list.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }
        delegate: MenuRow {
            required property var model
            required property int index
            width: ListView.view.width
            row: model
            current: index === Go.selectedIndex
            onHovered: Go.selectedIndex = index
            onPicked: Go.activateIndex(index)
        }
    }
    Column {
        Layout.fillWidth: true
        visible: !root.catalog && !root.inputPrompt && Go.rows.length === 0
        spacing: 6
        GlowText { anchors.horizontalCenter: parent.horizontalCenter; text: "󰈉"; color: Theme.strataAccent; font.pixelSize: 28 }
        GlowText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: field.text ? "No entry named “" + field.text + "”" : root.prompting ? "Nothing to choose from" : Go.rowsLoaded ? "Nothing here yet" : "Reading the trail map…"
            color: Theme.strataMuted
        }
    }
    GlowText {
        Layout.fillWidth: true
        readonly property string selectedKind: root.catalog ? (root.shown[root.selected]?.kind || "") : ""
        readonly property bool selectedTrail: selectedKind === "menu" || selectedKind === "link"
        text: DefaultApps.launchError ? DefaultApps.launchError
            : root.inputPrompt ? "ENTER answer   /   ESC cancel"
            : root.prompting ? "Type to filter   /   ENTER choose   /   ESC cancel"
            : root.onTrail ? (field.text ? "ENTER open   /   arrows move   /   ESC clear" : "ENTER open   /   arrows move   /   BACKSPACE back   /   ESC close")
            : selectedKind === "calc" ? "ENTER copy the answer   /   arrows move   /   ESC clear"
            : selectedTrail ? "ENTER open the trail   /   arrows move   /   ESC " + (root.query ? "clear" : "close")
            : selectedKind === "action" ? "ENTER run   /   arrows move   /   ESC " + (root.query ? "clear" : "close")
            : selectedKind ? "ENTER open in browser   /   arrows move   /   ESC clear"
            : root.browsing ? "ENTER launch   /   F favourite   /   arrows move   /   ESC " + (root.query ? "clear" : "close")
            : "ENTER launch   /   arrows move   /   ESC " + (root.query ? "clear" : "close")
        color: DefaultApps.launchError ? Theme.amber : Theme.strataMuted
        font.pixelSize: 10
        elide: Text.ElideRight
        opacity: root.beat(5)
    }
}
