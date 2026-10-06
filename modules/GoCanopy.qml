import QtQuick
import QtQuick.Layouts
import Quickshell
import ".."
import "../components"
import "../services"

// Applications, as a bar drop: a search filament, the apps you launched
// last, and an icon grid that answers the keyboard. Launching goes through
// DefaultApps like the Go menu does; the Go menu itself is unchanged.
ColumnLayout {
    id: root
    property bool active: false
    property string query: ""
    property int selected: 0
    readonly property int columns: width < 380 ? 3 : 4
    readonly property int limit: 20
    spacing: 12
    function beat(order, span = .4) { return Canopy.ease(.06 * order, span); }

    readonly property var all: (DefaultApps.data.apps || []).filter(a => a && a.visible !== false && a.id)
    readonly property var matches: {
        const q = root.query.toLowerCase().trim();
        if (!q)
            return root.all;
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
    readonly property var shown: matches.slice(0, limit)
    // The last four apps launched from Go, oldest trail first after dedupe.
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
    function iconSource(app) { return Config.imageSource(Quickshell.iconPath(app.icon || "application-x-executable", true)); }
    function launch(app) {
        if (!app)
            return;
        Forest.record("go", "Go / " + app.label, "apps." + app.id);
        DefaultApps.launch(app.id);
        Canopy.close();
    }
    function move(delta) {
        if (!root.shown.length)
            return;
        root.selected = Math.max(0, Math.min(root.shown.length - 1, root.selected + delta));
    }
    onActiveChanged: {
        if (active) {
            field.text = "";
            root.query = "";
            root.selected = 0;
            Qt.callLater(() => field.forceActiveFocus());
        }
    }
    onQueryChanged: root.selected = 0

    RowLayout {
        Layout.fillWidth: true
        opacity: root.beat(0)
        transform: Translate { y: 6 * (1 - root.beat(0)) }
        SectionMark { text: "APPLICATIONS" }
        Item { Layout.fillWidth: true }
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
            onTextChanged: root.query = text
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
            visible: root.matches.length > root.limit
            text: "showing " + root.limit + " of " + root.matches.length + " · type to narrow"
            textFormat: Text.PlainText; font.family: Theme.dataFont; font.pixelSize: 9; font.letterSpacing: 1; color: Theme.muted
        }
    }
    GridLayout {
        id: grid
        Layout.fillWidth: true
        columns: root.columns
        columnSpacing: 8; rowSpacing: 8
        uniformCellWidths: true
        Repeater {
            model: root.shown
            Item {
                id: tile
                required property var modelData
                required property int index
                readonly property bool current: index === root.selected
                readonly property real sweep: root.beat(3 + Math.min(index, 11) * .6, .35)
                Layout.fillWidth: true; Layout.preferredWidth: 1
                implicitHeight: 92
                opacity: sweep
                scale: .92 + .08 * sweep
                Accessible.role: Accessible.Button
                Accessible.name: "Launch " + modelData.label
                ChamferFrame {
                    anchors.fill: parent
                    cut: 7
                    fill: tile.current ? Qt.alpha(Theme.green, .07) : hover.containsMouse ? Qt.alpha(Theme.teal, .05) : Qt.alpha(Theme.background, .5)
                    stroke: tile.current ? Qt.alpha(Theme.green, .55) : hover.containsMouse ? Qt.alpha(Theme.teal, .35) : Qt.alpha(Theme.teal, .13)
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
                        source: root.iconSource(tile.modelData)
                    }
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: tile.modelData.label
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
                    onPositionChanged: root.selected = tile.index
                    onClicked: root.launch(tile.modelData)
                }
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
        text: DefaultApps.launchError ? DefaultApps.launchError : "ENTER launch   /   arrows move   /   ESC " + (root.query ? "clear" : "close")
        color: DefaultApps.launchError ? Theme.amber : Theme.muted
        font.pixelSize: 10
        elide: Text.ElideRight
        opacity: root.beat(5)
    }
}
