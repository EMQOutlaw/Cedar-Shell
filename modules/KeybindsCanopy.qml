import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."
import "../components"
import "../services"

// The keybind reference (Super+K): every CEDAR shortcut from the shared
// definition in data/keybinds.json, read against what Hyprland has bound
// right now, then the shortcuts added in Settings and anything else that is
// live. One definition feeds the files the installer ships and this view, so
// they cannot drift apart; a key that Hyprland reports differently (your
// override in user.lua or Settings) is marked as changed, and one Hyprland
// does not report is marked off. Search matches actions, keys and groups.
ColumnLayout {
    id: root
    spacing: 12
    property string query: ""
    property var definition: ({ groups: [], notes: [] })
    FileView { id: source; path: Quickshell.shellPath("data/keybinds.json"); blockLoading: true; printErrors: false }
    Component.onCompleted: {
        try { root.definition = JSON.parse(source.text()) || ({ groups: [], notes: [] }); } catch (error) { root.definition = ({ groups: [], notes: [] }); }
        DesktopSettings.refresh();   // read Hyprland once, while this is shown
        search.forceActiveFocus();
    }
    readonly property var live: DesktopSettings.data.bindings || []
    readonly property var owned: DesktopSettings.data.owned?.bindings || []
    property bool snapshotRead: false
    readonly property bool read: snapshotRead || live.length > 0
    Connections { target: DesktopSettings; function onRefreshed() { root.snapshotRead = true; } }

    function normalize(keys) {
        const parts = String(keys || "").split("+").map(p => p.trim().toUpperCase()).filter(Boolean);
        if (!parts.length) return "";
        const mods = ["SUPER", "CTRL", "ALT", "SHIFT"].filter(m => parts.slice(0, -1).includes(m));
        return mods.concat(parts.slice(-1)).join(" + ");
    }
    function fill(text, vars) { let out = String(text || ""); for (const name in vars) out = out.split("{" + name + "}").join(vars[name]); return out; }
    // Every concrete combination of an entry with the description it should carry.
    function expand(entry) {
        const out = [];
        for (const vars of (entry.vars || [{}]))
            for (const keys of (entry.keys || []))
                out.push({ combo: normalize(fill(keys, vars)), description: fill(entry.each || entry.description, vars) });
        return out;
    }
    function liveFor(combo) { return live.find(b => !b.submap && normalize(b.keys) === combo) || null; }
    function actionText(bind) { return bind.description || ((bind.dispatcher || "") + " " + (bind.arg || "")).trim(); }
    function sameDescription(a, b) { return String(a || "").replace(/,/g, " ").replace(/\s+/g, " ").trim() === String(b || "").replace(/,/g, " ").replace(/\s+/g, " ").trim(); }
    function spoken(combo) {   // for search: "super shift v", "left drag"
        return combo.toLowerCase().replace(/mouse:272/g, "left drag").replace(/mouse:273/g, "right drag").replace(/xf86/g, "").replace(/\+/g, " ");
    }
    // The reference, one row per entry, then the shortcuts added in Settings and the rest of what is live.
    readonly property var sections: {
        const claimed = {};
        const out = [];
        for (const group of (definition.groups || [])) {
            const rows = [];
            for (const entry of (group.entries || [])) {
                const combos = expand(entry);
                combos.forEach(c => claimed[c.combo] = true);
                const found = combos.map(c => ({ bind: liveFor(c.combo), expected: c.description }));
                const active = found.filter(f => f.bind).length;
                const changed = found.filter(f => f.bind && !sameDescription(f.bind.description, f.expected) && !(f.bind.mouse && !f.bind.description));
                const conflicts = combos.filter(c => live.filter(b => !b.submap && normalize(b.keys) === c.combo).length > 1);
                const state = !read ? "" : conflicts.length ? "conflict" : changed.length ? "changed" : active === combos.length ? "live" : active === 0 ? "off" : "partial";
                const caps = entry.display ? [normalize(entry.display)] : entry.keys.map(k => normalize(k));
                const detail = conflicts.length ? "Multiple actions on " + conflicts.map(c => c.combo).join(", ") : changed.length ? changed.map(f => f.bind.keys + ": " + actionText(f.bind)).join("; ") : "";
                rows.push({ caps: caps, combinations: combos.map(c => c.combo), description: entry.description, state: state,
                            detail: detail,
                            search: (group.title + " " + entry.description + " " + detail + " " + caps.join(" ") + " " + combos.map(c => c.combo + " " + spoken(c.combo) + " " + c.description).join(" ")).toLowerCase() });
            }
            out.push({ id: group.id, title: group.title, note: group.note || "", rows: rows });
        }
        const yours = [];
        for (const b of owned) {
            const combo = normalize(b.keys); claimed[combo] = true;
            const bind = liveFor(combo);
            yours.push({ caps: [combo], combinations: [combo], description: b.description || "Custom shortcut", state: !read ? "" : bind ? "live" : "off", detail: b.command || "",
                         search: ("yours " + (b.description || "") + " " + combo + " " + spoken(combo) + " " + (b.command || "")).toLowerCase() });
        }
        if (yours.length) out.push({ id: "yours", title: "Yours", note: "Added in Settings › Keybinds; they load after CEDAR's set.", rows: yours });
        const others = [];
        for (const b of live) {
            const combo = normalize(b.keys);
            if (b.submap || claimed[combo]) continue;
            claimed[combo] = true;
            const what = b.description || ((b.dispatcher || "") + " " + (b.arg || "")).trim();
            others.push({ caps: [combo], combinations: [combo], description: what, state: "live", detail: b.submap ? "submap " + b.submap : "",
                          search: ("other " + what + " " + combo + " " + spoken(combo)).toLowerCase() });
        }
        if (others.length) out.push({ id: "other", title: "Other active shortcuts", note: "Bound in your Hyprland configuration outside CEDAR's set.", rows: others });
        return out;
    }
    readonly property string needle: query.replace(/\+/g, " ").trim().toLowerCase()
    function matches(row) {
        if (query.includes("+")) return row.combinations.concat(row.caps).includes(normalize(query));
        return !needle || needle.split(/\s+/).every(word => row.search.indexOf(word) >= 0);
    }
    readonly property int total: sections.reduce((n, s) => n + s.rows.length, 0)
    readonly property int shown: sections.reduce((n, s) => n + s.rows.filter(r => root.matches(r)).length, 0)
    function stateWord(state) { return ({ live: "LIVE", changed: "CHANGED", conflict: "CONFLICT", off: "OFF", partial: "PARTLY" })[state] || ""; }
    function stateTone(state) { return state === "live" ? Theme.green : ["changed", "conflict"].includes(state) ? Theme.amber : state === "off" ? Theme.muted : Theme.teal; }

    RowLayout {
        Layout.fillWidth: true; spacing: 10
        StationField {
            id: search
            Layout.fillWidth: true
            placeholderText: "Search by action or keys"
            Accessible.name: "Search shortcuts"
            onTextChanged: root.query = text
            Keys.onEscapePressed: event => { Canopy.close(); event.accepted = true; }
        }
        GlowText {
            text: DesktopSettings.busy && !root.read ? "Reading Hyprland…" : root.read ? root.shown + " of " + root.total + (root.total === 1 ? " shortcut" : " shortcuts") : "Hyprland not read"
            color: Theme.muted; font.pixelSize: Theme.small
        }
    }
    GlowText {
        visible: root.needle !== "" && root.shown === 0
        text: "Nothing matches “" + root.query.trim() + "”."; color: Theme.muted; font.pixelSize: Theme.small
    }
    Repeater {
        model: root.sections
        ColumnLayout {
            id: section
            required property var modelData
            readonly property var rows: modelData.rows.filter(r => root.matches(r))
            visible: rows.length > 0
            Layout.fillWidth: true; spacing: 6
            SectionMark { Layout.topMargin: 4; text: section.modelData.title.toUpperCase(); tone: section.modelData.id === "yours" ? Theme.green : Theme.teal }
            GlowText { visible: section.modelData.note !== "" && root.needle === ""; Layout.fillWidth: true; wrapMode: Text.WordWrap; text: section.modelData.note; color: Theme.muted; font.pixelSize: Theme.small }
            Repeater {
                model: section.rows
                RowLayout {
                    id: row
                    required property var modelData
                    Layout.fillWidth: true; spacing: 12
                    Accessible.role: Accessible.ListItem
                    Accessible.name: row.modelData.caps.join(" or ") + ": " + row.modelData.description
                    Flow {
                        Layout.preferredWidth: 236; Layout.alignment: Qt.AlignTop; spacing: 6
                        Repeater {
                            model: row.modelData.caps
                            Row {
                                required property string modelData
                                required property int index
                                spacing: 6
                                GlowText { visible: parent.index > 0; text: "or"; color: Theme.muted; font.pixelSize: Theme.small - 1; anchors.verticalCenter: parent.verticalCenter }
                                Keycap { keys: parent.modelData; accent: row.modelData.state === "changed" ? Theme.amber : Theme.teal; opacity: row.modelData.state === "off" ? .55 : 1 }
                            }
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true; Layout.alignment: Qt.AlignTop; spacing: 1
                        GlowText { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: row.modelData.description; font.pixelSize: Theme.small + 1; color: row.modelData.state === "off" ? Theme.muted : Theme.text }
                        GlowText { visible: row.modelData.detail !== ""; Layout.fillWidth: true; wrapMode: Text.WordWrap; elide: Text.ElideRight; maximumLineCount: 2; text: row.modelData.detail; color: Theme.muted; font.pixelSize: Theme.small - 1 }
                    }
                    GlowText { visible: row.modelData.state !== "" && row.modelData.state !== "live"; Layout.alignment: Qt.AlignTop; text: root.stateWord(row.modelData.state); color: root.stateTone(row.modelData.state); font.pixelSize: 9; font.letterSpacing: 1.2 }
                }
            }
        }
    }
    Repeater {
        model: root.needle === "" ? (root.definition.notes || []) : []
        GlowText { required property string modelData; Layout.fillWidth: true; wrapMode: Text.WordWrap; text: modelData; color: Theme.muted; font.pixelSize: Theme.small }
    }
    GlowText {
        visible: root.needle === ""
        Layout.fillWidth: true; wrapMode: Text.WordWrap; color: Theme.muted; font.pixelSize: Theme.small
        text: "Esc closes this. Change a key in Settings › Keybinds, or in ~/.config/cedar/hypr/user.lua (user.conf on older Hyprland), which loads last."
    }
}
