import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import ".."
import "../components"
import "../services"
import "../components/Compass.js" as Compass

// Applications, as a bar drop: a search filament, favourites pinned above the
// rest, the apps you launched last, and an icon grid that answers the
// keyboard. Arithmetic typed into the search answers above the grid and a web
// search (or a bare address) waits below it, so every query has somewhere to
// go. Launching goes through DefaultApps like the Go menu does.
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
    spacing: 12
    function beat(order, span = .4) { return Canopy.ease(.06 * order, span); }

    readonly property var all: (DefaultApps.data.apps || []).filter(a => a && a.visible !== false && a.id)
    readonly property var favouriteIds: Config.saved.goFavorites || []
    // Favourites keep the order they were marked in.
    readonly property var favourites: favouriteIds.map(id => root.all.find(a => a.id === id)).filter(Boolean)
    readonly property var matches: {
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
    readonly property var calc: root.query.trim() ? Compass.evaluate(root.query) : null
    readonly property string address: Compass.urlFor(root.query)
    readonly property var answers: root.calc ? [{ kind: "calc", id: "compass.calc", label: "= " + root.calc.display, detail: root.calc.expression, value: root.calc.display }] : []
    readonly property var trailing: {
        const q = root.query.trim();
        if (!q)
            return [];
        const out = [];
        if (root.address)
            out.push({ kind: "url", id: "compass.url", label: "Open " + root.address.replace(/^https?:\/\//i, ""), detail: root.address, url: root.address });
        out.push({ kind: "web", id: "compass.web", label: "Search " + Compass.engine(Config.searchEngine).label + " for \u201c" + q + "\u201d",
                   detail: "Opens in your default browser", url: Compass.searchUrl(Config.searchEngine, q) });
        return out;
    }
    // One flat list for the keyboard: answers, favourites (while there is no
    // query), matches, then the web search.
    readonly property var pinned: root.query ? [] : root.favourites
    readonly property var shown: root.answers.concat(root.pinned, root.matches, root.trailing)
    // The last four apps launched from Go.
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
        Forest.record("go", "Go / " + app.label, "apps." + app.id);
        DefaultApps.launch(app.id);
        Canopy.close();
    }
    // Answers stack one per row above and below the grid, so a vertical step
    // (±columns) moves one answer at a time and crosses into the grid's edge.
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
                next = root.trailing.length ? head + grid : i;
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
        } else
            root.launch(item);
    }
    // The default browser gets the URL in its own scope so it outlives the shell.
    function openUrl(url) {
        if (/^https?:\/\//i.test(String(url)))
            Quickshell.execDetached(["systemd-run", "--user", "--scope", "--quiet", "--collect", "--", "xdg-open", String(url)]);
    }
    onActiveChanged: {
        if (active) {
            field.text = "";
            root.query = "";
            root.selected = 0;
            root.browsing = false;
            Qt.callLater(() => field.forceActiveFocus());
        }
    }
    onQueryChanged: { root.selected = 0; flick.contentY = 0; }
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
            cut: 7
            fill: tile.current ? Qt.alpha(Theme.green, .07) : hover.containsMouse ? Qt.alpha(Theme.teal, .05) : Qt.alpha(Theme.background, .5)
            stroke: tile.current ? Qt.alpha(Theme.green, .55) : tile.favourite ? Qt.alpha(Theme.amber, .3) : hover.containsMouse ? Qt.alpha(Theme.teal, .35) : Qt.alpha(Theme.teal, .13)
            line: tile.current; lineColor: Theme.green; lineFraction: .55
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
                color: tile.current ? Theme.green : Theme.text
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
            color: tile.favourite ? Theme.amber : Theme.muted
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
            cut: 7
            fill: answer.current ? Qt.alpha(Theme.green, .07) : answerHover.containsMouse ? Qt.alpha(Theme.teal, .05) : Qt.alpha(Theme.background, .5)
            stroke: answer.current ? Qt.alpha(Theme.green, .55) : answerHover.containsMouse ? Qt.alpha(Theme.teal, .35) : Qt.alpha(Theme.teal, .13)
            line: answer.current; lineColor: Theme.green; lineFraction: .55
        }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14; anchors.rightMargin: 14
            spacing: 12
            Text {
                text: answer.isCalc ? "\udb80\udcec" : answer.item?.kind === "url" ? "\udb80\udf37" : "\udb81\udd9f"
                textFormat: Text.PlainText
                font.family: Theme.dataFont; font.pixelSize: 18
                color: answer.current ? Theme.green : Theme.teal
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
                    color: answer.current ? Theme.white : Theme.text
                }
                Text {
                    Layout.fillWidth: true
                    text: answer.item?.detail || ""
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    font.family: Theme.dataFont; font.pixelSize: 10
                    color: Theme.muted
                }
            }
            Text {
                visible: answer.current
                text: answer.isCalc ? "ENTER COPIES" : "ENTER OPENS"
                textFormat: Text.PlainText
                font.family: Theme.dataFont; font.pixelSize: 9; font.letterSpacing: 1
                color: Theme.muted
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

    RowLayout {
        Layout.fillWidth: true
        opacity: root.beat(0)
        transform: Translate { y: 6 * (1 - root.beat(0)) }
        SectionMark { text: "APPLICATIONS" }
        Item { Layout.fillWidth: true }
        StatusPill { visible: root.favourites.length > 0; text: root.favourites.length + (root.favourites.length === 1 ? " favourite" : " favourites"); tone: Theme.amber }
        StatusPill { text: DefaultApps.error ? "Catalog offline" : root.all.length + " apps"; tone: DefaultApps.error ? Theme.amber : Theme.teal }
    }

    // Search: a filament lights under the field as the panel enters, turns
    // green while the query finds something and amber when it finds nothing.
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 6
        opacity: root.beat(1)
        transform: Translate { y: 6 * (1 - root.beat(1)) }
        StationField {
            id: field
            objectName: "goSearch"
            Layout.fillWidth: true
            placeholderText: "Type an app, a sum, an address or a web search"
            Accessible.name: "Search applications"
            onTextChanged: { root.query = text; root.browsing = false; }
            Keys.onPressed: event => {
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
            Rectangle { width: parent.width; height: 1; y: 1; color: Qt.alpha(Theme.teal, .12) }
            Rectangle {
                width: parent.width * (root.query ? 1 : .55 * root.beat(1, .6))
                height: root.query ? 2 : 1
                color: root.query ? (root.matches.length || root.answers.length ? Theme.green : Theme.amber) : Theme.teal
                opacity: root.query ? .85 : .5
                Behavior on width { enabled: !Theme.reducedMotion; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                Rectangle { anchors.right: parent.right; width: 24; height: parent.height; color: Theme.green; opacity: root.query ? 0 : .8 * (1 - root.beat(.5, .4)) }
            }
        }
        // What the field answers, shown until something is typed so nobody has
        // to find the calculator or the web search by accident.
        Flow {
            Layout.fillWidth: true
            visible: !root.query
            spacing: 18
            opacity: root.beat(1.6, .4) * .9
            Repeater {
                model: [
                    { glyph: "\udb80\udcec", example: "2+2", does: "answers, ENTER copies" },
                    { glyph: "\udb80\udf37", example: "docs.rs", does: "opens the address" },
                    { glyph: "\udb81\udd9f", example: "anything else", does: "searches " + Compass.engine(Config.searchEngine).label }
                ]
                Row {
                    required property var modelData
                    spacing: 6
                    Text { anchors.verticalCenter: parent.verticalCenter; text: parent.modelData.glyph; textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: 12; color: Theme.teal }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: parent.modelData.example; textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: 10; color: Theme.text }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: parent.modelData.does; textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: 10; color: Theme.muted }
                }
            }
        }
    }

    // The arithmetic answer, when the query is a sum.
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 8
        visible: root.answers.length > 0
        SectionMark { text: "ANSWER"; size: 9; tone: Theme.green }
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
            Text { text: "F while browsing marks or clears one"; textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: 9; font.letterSpacing: 1; color: Theme.muted }
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
        visible: !root.query && root.recents.length > 0
        opacity: root.beat(2)
        transform: Translate { y: 6 * (1 - root.beat(2)) }
        SectionMark { text: "RECENT"; size: 9; tone: Theme.muted }
        Flow {
            Layout.fillWidth: true
            spacing: 8
            Repeater {
                model: root.recents
                StationButton {
                    id: chip
                    required property var modelData
                    implicitHeight: 32
                    text: modelData.label
                    hint: "Launch " + modelData.label
                    onClicked: root.launch(modelData)
                    contentItem: Row {
                        spacing: 8
                        Image { anchors.verticalCenter: parent.verticalCenter; width: 16; height: 16; sourceSize.width: 32; sourceSize.height: 32; fillMode: Image.PreserveAspectFit; asynchronous: true; source: root.iconSource(chip.modelData) }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: chip.text; textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: Theme.small; color: Theme.text }
                    }
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        opacity: root.beat(3)
        SectionMark { text: root.query ? "MATCHES" : "ALL APPS"; size: 9; tone: Theme.muted }
        Item { Layout.fillWidth: true }
        Text {
            visible: root.query !== "" && root.matches.length > 0
            text: root.matches.length + (root.matches.length === 1 ? " match" : " matches")
            textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: 9; font.letterSpacing: 1; color: Theme.muted
        }
    }
    // The grid scrolls under the fixed search field; five rows show at once.
    Flickable {
        id: flick
        Layout.fillWidth: true
        implicitHeight: Math.min(grid.implicitHeight, root.visibleRows * root.tileHeight + (root.visibleRows - 1) * root.tileGap)
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
        visible: root.pinned.length + root.matches.length === 0
        spacing: 6
        GlowText { anchors.horizontalCenter: parent.horizontalCenter; text: "󰈉"; color: Theme.teal; font.pixelSize: 28 }
        GlowText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.query ? "No app named “" + root.query + "”" : DefaultApps.error ? DefaultApps.error : "Reading the application catalog…"
            color: Theme.muted
        }
    }
    // The web search (and a bare address) under everything the query found.
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 8
        visible: root.trailing.length > 0
        SectionMark { text: "ELSEWHERE"; size: 9; tone: Theme.muted }
        Repeater {
            model: root.trailing
            AnswerRow { required property var modelData; required property int index; item: modelData; flat: root.answers.length + root.pinned.length + root.matches.length + index; order: 4 }
        }
    }
    GlowText {
        Layout.fillWidth: true
        readonly property string selectedKind: root.shown[root.selected]?.kind || ""
        text: DefaultApps.launchError ? DefaultApps.launchError
            : selectedKind === "calc" ? "ENTER copy the answer   /   arrows move   /   ESC clear"
            : selectedKind ? "ENTER open in browser   /   arrows move   /   ESC clear"
            : root.browsing ? "ENTER launch   /   F favourite   /   arrows move   /   ESC " + (root.query ? "clear" : "close")
            : "ENTER launch   /   arrows move   /   ESC " + (root.query ? "clear" : "close")
        color: DefaultApps.launchError ? Theme.amber : Theme.muted
        font.pixelSize: 10
        elide: Text.ElideRight
        opacity: root.beat(5)
    }
}
