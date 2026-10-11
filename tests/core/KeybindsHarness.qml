import QtQuick
import Quickshell
import "../.."
import "../../modules"
import "../../services"

ShellRoot {
    FloatingWindow {
        id: window
        visible: true
        implicitWidth: 700
        implicitHeight: 800
        KeybindsCanopy { id: panel; width: parent.width }
        function check(ok, message) {
            if (!ok) { console.error("FAIL: " + message); Qt.exit(1); throw new Error(message); }
        }
        Timer {
            interval: 100
            running: true
            onTriggered: {
                window.check(panel.sections.length === 7, "all reference groups load from the shared definition");
                const bindings = [];
                for (const group of panel.definition.groups)
                    for (const entry of group.entries)
                        for (const item of panel.expand(entry))
                            bindings.push({ keys: item.combo, description: item.description, submap: "" });
                DesktopSettings.data = { bindings: bindings, owned: { bindings: [] } };
                window.check(panel.sections.every(s => s.rows.every(r => r.state === "live")), "every default matches the runtime fixture");
                panel.query = "Super+Shift+V";
                window.check(panel.shown === 1, "compact key combination search");
                panel.query = "scratchpad";
                window.check(panel.shown === 2, "action search");
                panel.query = "left drag";
                window.check(panel.shown === 1, "mouse gesture search");
                panel.query = "not-a-shortcut";
                window.check(panel.shown === 0, "no matches");
                panel.query = "";
                const custom = bindings.map(b => Object.assign({}, b));
                custom.find(b => b.keys === "SUPER + C").description = "Custom editor";
                custom.push({ keys: "SUPER + Y", description: "Personal shortcut", submap: "" });
                DesktopSettings.data = { bindings: custom, owned: { bindings: [] } };
                window.check(panel.sections[0].rows.some(r => r.state === "changed" && r.detail.includes("Custom editor")), "manual override description");
                panel.query = "custom editor";
                window.check(panel.shown === 1, "search overridden action");
                panel.query = "";
                window.check(panel.sections.some(s => s.id === "other"), "other effective keys listed");
                DesktopSettings.data = { bindings: custom.concat([custom[0]]), owned: { bindings: [] } };
                window.check(panel.sections[0].rows[0].state === "conflict", "duplicate press/release bindings flagged");
                DesktopSettings.data = { bindings: [], owned: { bindings: [] } };
                DesktopSettings.refreshed();
                window.check(panel.sections.every(s => s.rows.every(r => r.state === "off")), "successful empty snapshot marks defaults off");
                console.log("PASS: keybind reference search, runtime overrides, conflicts and empty bindings");
                Qt.quit();
            }
        }
    }
}
