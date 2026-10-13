#!/usr/bin/env python3
"""Offscreen: the Applications drop carries the menu and a script's prompts.

Routes open the drop on a trail, a trail's rows come from the menu service,
Backspace climbs out, a select prompt takes the drop over and cancels back to
the catalog, an input prompt carries its answer, and the bar button's toggle
closes what it opened. Offscreen only; no action runs and no script waits."""
from pathlib import Path
import os, re, shutil, subprocess, sys, tempfile
ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='cedar-applications-') as tmp:
    p = Path(tmp); source = p / 'shell'; shutil.copytree(ROOT, source, ignore=shutil.ignore_patterns('__pycache__', '.git'))
    runtime = p / 'runtime'; runtime.mkdir(mode=0o700)
    (source / 'preview.qml').write_text('''
import QtQuick
import Quickshell
import "."
import "modules"
import "services"
ShellRoot {
    FloatingWindow {
        id: window
        visible: true
        implicitWidth: 960
        implicitHeight: 800
        color: Theme.background
        CanopyPanel { id: panel; width: 480; height: parent.height; active: true }
        function check(ok, msg) { if (!ok) { console.error("FAIL: " + msg); Qt.exit(1); } }
        function field() {
            let found = null;
            function walk(item) { if (!item) return; if (item.objectName === "goSearch") { found = item; return; } for (const c of item.children) { walk(c); if (found) return; } }
            walk(panel); return found;
        }
        function drop() { let root = field(); while (root && root.catalog === undefined) root = root.parent; return root; }
        property int step: 0
        property int waited: 0
        Timer {
            interval: 400; running: true; repeat: true
            onTriggered: {
                if (window.step === 0) { Go.refresh(); Go.toggle("root"); window.step++; return; }
                if (!Go.rowsLoaded) { if (++window.waited > 25) window.check(false, "menu never loaded"); return; }
                const root = window.drop(), field = window.field();
                window.check(!!root && !!field, "Applications drop and its field are reachable");
                if (window.step === 1) {
                    window.check(Canopy.shown && Canopy.topic === "go" && Canopy.standalone, "The bar toggle opens the Applications drop standalone");
                    window.check(root.catalog && Go.activeMenu === "root", "It opens on the catalog at the menu root");
                    window.check(root.menuRows.length >= 2 && root.menuRows.every(r => r.itemId !== "apps" && r.kind !== "app"), "The menu's other trails sit under the grid without the apps entry (" + JSON.stringify(root.menuRows.map(r => r.itemId)) + ")");
                    window.check(root.shown.length === root.matches.length + root.menuRows.length, "Chips are on the keyboard list");
                    root.selected = root.matches.length;
                    root.activate(root.shown[root.selected]);
                    window.check(root.onTrail && Go.activeMenu === root.menuRows[0]?.itemId || Go.activeMenu !== "root", "Enter on a chip opens its trail in place (" + Go.activeMenu + ")");
                    window.check(Go.breadcrumb.length > 0 && Go.rows.length > 0, "A trail has a breadcrumb and rows (" + Go.breadcrumb + ")");
                    Go.goBack();
                    window.check(root.catalog, "Back climbs out to the catalog");
                } else if (window.step === 2) {
                    Go.toggle("system");
                    window.check(Canopy.shown && root.onTrail && Go.activeMenu === "system", "menu toggle system moves the open drop to that trail");
                    window.check(Go.rows.some(r => r.itemId === "system.lock"), "System lists Lock (" + JSON.stringify(Go.rows.map(r => r.itemId)) + ")");
                    field.text = "loc";
                    window.check(Go.filterText === "loc" && Go.rows.some(r => r.itemId === "system.lock") && !Go.rows.some(r => r.itemId === "system.power"), "Typing on a trail searches it (" + JSON.stringify(Go.rows.map(r => r.itemId)) + ")");
                    field.text = "";
                    Go.toggle("system");
                    window.check(!Canopy.shown, "Toggling the shown route closes the drop");
                    window.check(Go.activeMenu === "root" && Go.filterText === "", "Closing returns the service to the root");
                } else if (window.step === 3) {
                    Go.toggle("apps");
                    window.check(Canopy.shown && root.catalog, "menu toggle apps is the catalog");
                    field.text = "lock";
                    window.check(root.menuRows.some(r => r.itemId === "system.lock") && root.shown.length >= root.menuRows.length + 1, "A query finds menu entries anywhere and keeps the web search last (" + JSON.stringify(root.menuRows.map(r => r.itemId)) + ")");
                    window.check(root.shown[root.shown.length - 1].kind === "web", "Web search trails the menu rows");
                    Go.summon(JSON.stringify({ mode: "select", prompt: "Pick one", options: ["\\u2713\\tOne\\tfirst", "Two"], width: 900 }));
                    window.check(root.prompting && !root.inputPrompt && Go.rows.length === 2 && Go.rows[0].label === "One" && Go.rows[0].detail === "first", "A select prompt takes the drop over (" + JSON.stringify(Go.rows) + ")");
                    window.check(field.text === "" && root.menuRows.length === 0, "The prompt starts with a clear field and no catalog rows");
                    field.text = "tw";
                    window.check(Go.rows.length === 1 && Go.rows[0].label === "Two", "Typing filters the choices");
                    Go.cancel();
                    window.check(!Canopy.shown && !Go.dmenuActive, "Cancelling a prompt closes the drop and ends the prompt");
                } else if (window.step === 4) {
                    Go.summon(JSON.stringify({ mode: "input", prompt: "Name it" }));
                    window.check(Canopy.shown && root.inputPrompt && Go.rows.length === 0, "An input prompt opens the drop with no rows");
                    field.text = "an answer";
                    window.check(Go.filterText === "an answer", "The field carries the answer");
                    Go.activateIndex(Go.selectedIndex);
                    window.check(!Canopy.shown && Go.mode === "menu", "Enter answers and closes");
                    Config.set("canopyEnabled", false);
                    Go.toggle("root");
                    window.check(Canopy.shown && Canopy.topic === "go", "Applications drops with Canopy turned off");
                    Go.hide();
                    Config.set("canopyEnabled", true);
                    console.log("PASS: Applications carries the menu and prompts");
                    Qt.quit();
                }
                window.step++;
            }
        }
    }
}
''')
    # The standalone menu (menus/default.jsonc + menus/cedar-menu.jsonc), whatever desktop runs this.
    env = {**os.environ, 'CEDAR_TEST': '1', 'CEDAR_ADAPTER': 'hyprland', 'CEDAR_OMARCHY_SESSION': '', 'OMARCHY_PATH': str(p / 'absent'), 'QT_QPA_PLATFORM': 'offscreen', 'QT_QPA_PLATFORMTHEME': 'basic', 'QT_QUICK_CONTROLS_STYLE': 'Basic', 'QSG_RHI_BACKEND': 'software', 'XDG_RUNTIME_DIR': str(runtime), 'XDG_CONFIG_HOME': str(p / 'config'), 'XDG_STATE_HOME': str(p / 'state')}
    result = subprocess.run(['qs', '-p', str(source / 'preview.qml')], env=env, capture_output=True, text=True, timeout=40)
    output = result.stdout + result.stderr
    bad = re.search(r'Failed to load configuration|ReferenceError|TypeError|Binding loop|Cannot assign|is not defined|Unable to assign|FAIL:', output)
    if result.returncode or 'PASS: Applications' not in output or bad:
        print(output[-8000:]); raise SystemExit(1)
    print('PASS: Applications carries the menu and prompts')
    warnings = [l for l in output.splitlines() if 'GoCanopy' in l or 'Go.qml' in l or 'Canopy' in l]
    print('\n'.join(warnings) or '(no warnings mention the changed files)')
