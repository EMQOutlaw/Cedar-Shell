#!/usr/bin/env python3
"""Offscreen: Compass answers (calculator, address, web search) in the Applications drop and the Go menu.

Optional argv[1]: a directory for the two renders. Offscreen only; it opens no browser and copies nothing."""
from pathlib import Path
import os, re, shutil, subprocess, sys, tempfile
ROOT = Path(__file__).resolve().parents[1]
SHOTS = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else None
with tempfile.TemporaryDirectory(prefix='cedar-compass-') as tmp:
    p = Path(tmp); source = p / 'shell'; shutil.copytree(ROOT, source, ignore=shutil.ignore_patterns('__pycache__', '.git'))
    runtime = p / 'runtime'; runtime.mkdir(mode=0o700)
    shots = SHOTS or (p / 'shots'); shots.mkdir(parents=True, exist_ok=True)
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
        CanopyPanel { id: panel; width: 760; height: parent.height; active: true }
        function check(ok, msg) { if (!ok) { console.error("FAIL: " + msg); Qt.exit(1); } }
        function drop() {
            let found = null;
            function walk(item) { if (!item) return; if (item.objectName === "goSearch") { found = item; return; } for (const c of item.children) { walk(c); if (found) return; } }
            walk(panel); return found;
        }
        property int step: 0
        property int waited: 0
        Timer {
            interval: 500; running: true; repeat: true
            onTriggered: {
                if (window.step === 0) {
                    Go.refresh(); // start reading the menu files now so the Go step finds a loaded tree
                    Canopy.open("go");
                    window.step++; return;
                }
                const field = window.drop();
                window.check(!!field, "Applications search field present");
                const go = field.parent.parent.parent; // StationField > ColumnLayout > ColumnLayout(root)
                let root = field; while (root && root.objectName !== "" && root.answers === undefined) root = root.parent;
                root = field; while (root && root.answers === undefined) root = root.parent;
                window.check(!!root, "GoCanopy root reachable");
                if (window.step === 1) {
                    field.text = "2+2";
                    window.check(root.answers.length === 1 && root.answers[0].label === "= 4", "2+2 answers = 4 (" + JSON.stringify(root.answers) + ")");
                    window.check(root.shown[0].kind === "calc", "Calculator answer leads the keyboard list");
                    window.check(root.trailing.length === 1 && root.trailing[0].kind === "web" && root.trailing[0].label.indexOf("Brave Search") >= 0, "Web search trails (" + JSON.stringify(root.trailing) + ")");
                    window.check(root.trailing[0].url === "https://search.brave.com/search?q=2%2B2", "Brave URL encodes the query");
                    root.move(root.columns);
                    window.check(root.selected === (root.matches.length ? 1 : 1), "Down from the answer moves one row");
                    panel.grabToImage(r => r.saveToFile(Quickshell.env("CEDAR_SCREENSHOT_DIR") + "/compass-sum.png"));
                } else if (window.step === 2) {
                    field.text = "docs.rs/serde";
                    window.check(root.answers.length === 0, "An address is not arithmetic");
                    window.check(root.trailing.length === 2 && root.trailing[0].kind === "url" && root.trailing[0].url === "https://docs.rs/serde", "Address row precedes the web search (" + JSON.stringify(root.trailing) + ")");
                    const last = root.shown.length - 1;
                    root.selected = last;
                    window.check(root.shown[last].kind === "web", "Web search is last");
                    root.move(-root.columns);
                    window.check(root.shown[root.selected].kind === "url", "Up from the web search reaches the address row");
                    Config.set("searchEngine", "duckduckgo");
                    window.check(root.trailing[1].label.indexOf("DuckDuckGo") >= 0 && root.trailing[1].url.startsWith("https://duckduckgo.com/?q="), "Engine setting changes the search (" + root.trailing[1].url + ")");
                    Config.set("searchEngine", "bogus");
                    window.check(Config.searchEngine === "brave", "Unknown engine falls back to Brave");
                    Config.set("searchEngine", "brave");
                    panel.grabToImage(r => r.saveToFile(Quickshell.env("CEDAR_SCREENSHOT_DIR") + "/compass-address.png"));
                } else if (window.step === 3) {
                    if (!Go.rowsLoaded) { if (++window.waited > 20) window.check(false, "Go menu never loaded"); return; }
                    field.text = "kitty";
                    window.check(root.answers.length === 0 && root.trailing.length === 1, "A word gets only a web search");
                    window.check(root.isFavourite(root.trailing[0]) === false, "Answers are never favourites");
                    field.text = "";
                    window.check(root.trailing.length === 0 && root.answers.length === 0, "Empty query has no answers");
                    panel.grabToImage(r => r.saveToFile(Quickshell.env("CEDAR_SCREENSHOT_DIR") + "/compass-empty.png"));
                } else if (window.step === 4) {
                    Canopy.close();
                    // The Go menu: calculator first, web search last, divider between.
                    Go.openRoute("root");
                    Go.setFilter("sqrt(16)*3");
                    window.check(Go.rows.length >= 2 && Go.rows[0].kind === "calc" && Go.rows[0].label === "= 12", "Go menu leads with the answer (" + JSON.stringify(Go.rows[0]) + ")");
                    const tail = Go.rows[Go.rows.length - 1];
                    window.check(tail.kind === "web" && tail.action.startsWith("https://search.brave.com/search?q="), "Go menu trails with Brave (" + JSON.stringify(tail) + ")");
                    window.check(tail.section === (Go.rows.length > 2 ? "compass" : ""), "Divider only when something was found");
                    Go.setFilter("firef");
                    window.check(Go.rows[0].kind !== "calc" && Go.rows[Go.rows.length - 1].kind === "web", "A word in Go gets only the web search");
                    Go.hide();
                    console.log("PASS: Compass answers in Applications and Go");
                    Qt.quit();
                }
                window.step++;
            }
        }
    }
}
''')
    env = {**os.environ, 'CEDAR_TEST': '1', 'QT_QPA_PLATFORM': 'offscreen', 'QT_QPA_PLATFORMTHEME': 'basic', 'QT_QUICK_CONTROLS_STYLE': 'Basic', 'QSG_RHI_BACKEND': 'software', 'XDG_RUNTIME_DIR': str(runtime), 'XDG_CONFIG_HOME': str(p / 'config'), 'XDG_STATE_HOME': str(p / 'state'), 'CEDAR_SCREENSHOT_DIR': str(shots)}
    result = subprocess.run(['qs', '-p', str(source / 'preview.qml')], env=env, capture_output=True, text=True, timeout=40)
    output = result.stdout + result.stderr
    bad = re.search(r'Failed to load configuration|ReferenceError|TypeError|Binding loop|Cannot assign|is not defined|Unable to assign|FAIL:', output)
    if result.returncode or 'PASS: Compass' not in output or bad:
        print(output[-6000:]); raise SystemExit(1)
    print('PASS: Compass answers in Applications and Go')
    warnings = [l for l in output.splitlines() if 'Compass' in l or 'GoCanopy' in l or 'Go.qml' in l or 'MenuContent' in l]
    print('\n'.join(warnings) or '(no warnings mention the changed files)')
