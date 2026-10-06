import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import ".."
import "../components"
import "../services"

// Applications, as a bar drop: a search filament, favourites pinned above the
// rest, the apps you launched last, and an icon grid that answers the
// keyboard. Launching goes through DefaultApps like the Go menu does; the Go
// menu itself is unchanged.
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
    // One flat list for the keyboard: favourites first while there is no query.
    readonly property var pinned: root.query ? [] : root.favourites
    readonly property var shown: root.pinned.concat(root.matches)
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
    function isFavourite(app) { return !!app && root.favouriteIds.includes(app.id); }
    function toggleFavourite(app) {
        if (!app)
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
    function move(delta) {
        root.browsing = true;
        if (!root.shown.length)
            return;
        root.selected = Math.max(0, Math.min(root.shown.length - 1, root.selected + delta));
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
        const inGrid = root.selected - root.pinned.length;
        if (inGrid < 0) { flick.contentY = 0; return; }
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
            placeholderText: "Type to find an app"
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
                case Qt.Key_Return: case Qt.Key_Enter: root.launch(root.shown[root.selected]); break;
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
                color: root.query ? (root.matches.length ? Theme.green : Theme.amber) : Theme.teal
                opacity: root.query ? .85 : .5
                Behavior on width { enabled: !Theme.reducedMotion; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                Rectangle { anchors.right: parent.right; width: 24; height: parent.height; color: Theme.green; opacity: root.query ? 0 : .8 * (1 - root.beat(.5, .4)) }
            }
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
                AppTile { required property var modelData; required property int index; app: modelData; flat: index; order: index }
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
                AppTile { required property var modelData; required property int index; app: modelData; flat: root.pinned.length + index; order: root.pinned.length + index }
            }
        }
    }
    Column {
        Layout.fillWidth: true
        visible: root.shown.length === 0
        spacing: 6
        GlowText { anchors.horizontalCenter: parent.horizontalCenter; text: "󰈉"; color: Theme.teal; font.pixelSize: 28 }
        GlowText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.query ? "No app named “" + root.query + "”" : DefaultApps.error ? DefaultApps.error : "Reading the application catalog…"
            color: Theme.muted
        }
    }
    GlowText {
        Layout.fillWidth: true
        text: DefaultApps.launchError ? DefaultApps.launchError
            : root.browsing ? "ENTER launch   /   F favourite   /   arrows move   /   ESC " + (root.query ? "clear" : "close")
            : "ENTER launch   /   arrows move   /   ESC " + (root.query ? "clear" : "close")
        color: DefaultApps.launchError ? Theme.amber : Theme.muted
        font.pixelSize: 10
        elide: Text.ElideRight
        opacity: root.beat(5)
    }
}
