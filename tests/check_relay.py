#!/usr/bin/env python3
"""Offscreen: the Relay service's state from fixture events and the CEDAR AI window's pages at two widths.

Optional argv[1]: a directory for the renders. Test mode never starts
cedar_ai.py; the events below stand in for a running session.
"""
from pathlib import Path
import os, re, shutil, subprocess, sys, tempfile
ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='cedar-relay-') as tmp:
    p = Path(tmp); source = p / 'shell'; shutil.copytree(ROOT, source, ignore=shutil.ignore_patterns('__pycache__', '.git'))
    runtime = p / 'runtime'; runtime.mkdir(mode=0o700)
    shots = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else p / 'shots'; shots.mkdir(parents=True, exist_ok=True)
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
        implicitWidth: 1180
        implicitHeight: 820
        color: Theme.background
        property int step: 0
        function check(ok, msg) { if (!ok) { console.error("FAIL: " + msg); Qt.exit(1); } }
        function shot(name) { pages.grabToImage(r => r.saveToFile(Quickshell.env("CEDAR_SCREENSHOT_DIR") + "/" + name + ".png")); }
        function feed(event) { Relay.accept(JSON.stringify(event)); }
        property int pagesWidth: 1180
        RelayPages { id: pages; width: window.pagesWidth; height: window.height }
        Timer {
            interval: 500; running: true; repeat: true
            onTriggered: {
                switch (window.step++) {
                case 0:
                    window.check(!Relay.running && Relay.turns.length === 0 && Relay.finished === "", "Idle at start");
                    window.check(Relay.preferredMode === "edit" && Relay.rounds === 0 && Relay.first === "claude" && Relay.preferredAgents === "both" && !Relay.solo, "Defaults: both agents, edit, until done, Claude opens");
                    Relay.tools = { claude: "/usr/bin/claude", codex: "/usr/bin/codex" }; Relay.ready = true;
                    Relay.claudeModels = [{ id: "fable", label: "Fable" }, { id: "opus", label: "Opus" }];
                    Relay.codexModels = [{ id: "gpt-x", label: "GPT-X", efforts: ["low", "high"], defaultEffort: "low" }];
                    Relay.codexDefault = { model: "gpt-x", effort: "high" };
                    window.check(Relay.available && Relay.missing === "", "Both tools found reads as available");
                    window.check(Relay.claudeModel === "" && Relay.codexEffort === "" && Relay.modelLabel("claude") === "default", "Models default to the tools' own");
                    Config.set("relayClaudeModel", "opus"); Config.set("relayClaudeEffort", "max"); Config.set("relayCodexEffort", "nonsense");
                    window.check(Relay.claudeModel === "opus" && Relay.claudeEffort === "max" && Relay.codexEffort === "", "Model and effort preferences read back; an unknown effort is ignored");
                    window.shot("relay-idle");
                    break;
                case 1:
                    window.feed({ type: "session", dir: "/tmp/sessions/20261010-120000-goal", name: "20261010-120000-goal", goal: "Add a Capture submenu that screenshots with grim", repo: "/tmp/repo", mode: "edit", models: { claude: { model: "opus", effort: "max" }, codex: { model: "", effort: "" } } });
                    window.check(Relay.goal.indexOf("Capture") === 0 + 6 && Relay.sessionName === "20261010-120000-goal", "The session event names the goal and the folder");
                    window.check(Relay.modelLabel("claude") === "opus · max" && Relay.modelLabel("codex") === "default", "The session carries its models (" + Relay.modelLabel("claude") + ")");
                    window.feed({ type: "turn.started", agent: "claude", round: 1 });
                    window.feed({ type: "activity", agent: "claude", text: "Read menus/cedar-menu.jsonc" });
                    window.feed({ type: "activity", agent: "nobody", text: "ignored" });
                    window.check(Relay.currentAgent === "claude" && Relay.activity.length === 1, "Activity from an unknown agent is dropped (" + Relay.activity.length + ")");
                    window.feed({ type: "turn.completed", agent: "claude", round: 1, text: "First turn.\\nAdded cedar.capture.\\n[NEXT] codex: wire the runtime.", done: false });
                    window.feed({ type: "usage", agent: "claude", turn: { input: 1200, cached: 30000, output: 400, cost: 0.41 }, total: { input: 1200, cached: 30000, output: 400, cost: 0.41, turns: 1 } });
                    window.feed({ type: "limits", agent: "claude", fiveHour: 0.08, sevenDay: 0.35, fiveHourResets: 1791678000, sevenDayResets: 1791946800, at: "2026-10-10T17:10:00" });
                    window.check(Relay.usageLine("claude") === "31k in · 400 out · $0.41 · 1 turn" && Relay.usageLine("codex") === "", "Usage reads as the tool reported it (" + Relay.usageLine("claude") + ")");
                    window.check(Relay.limitLine("claude") === "5-hour 8% · week 35%" && !Relay.limits.codex, "Claude's plan windows read back; Codex has none (" + Relay.limitLine("claude") + ")");
                    window.feed({ type: "relay", sender: "claude", receiver: "codex", round: 1 });
                    window.feed({ type: "turn.started", agent: "codex", round: 1 });
                    window.feed({ type: "activity", agent: "codex", text: "$ python3 -m unittest tests.test_update_checkout" });
                    window.check(Relay.turns.length === 1 && !Relay.turns[0].done && Relay.currentAgent === "codex" && Relay.activity.length === 1, "A new turn clears the activity trail");
                    window.check(Relay.relays.length === 1 && Relay.relays[0].receiver === "codex", "The hand-off is recorded");
                    window.check(pages.entries.length === 2 && pages.entries[0].kind === "turn" && pages.entries[1].kind === "relay", "The conversation lists the turn, then the hand-off to Codex (" + pages.entries.map(e => e.kind).join(",") + ")");
                    break;
                case 2:
                    window.shot("relay-live");
                    window.feed({ type: "turn.completed", agent: "codex", round: 1, text: "Got it, claude: the entry is in.\\nWired it; tests pass.\\n[DONE]", done: true });
                    window.feed({ type: "error", message: "" });
                    window.feed({ type: "finished", reason: "done" });
                    window.check(Relay.turns.length === 2 && Relay.turns[1].done && Relay.finished === "done" && Relay.currentAgent === "", "Finished done after codex's DONE");
                    window.check(pages.stateWord === "Done", "The rail says Done (" + pages.stateWord + ")");
                    break;
                case 3:
                    window.shot("relay-done");
                    pages.navigate("sessions");
                    Relay.sessions = [{ dir: "/tmp/sessions/a", name: "20261010-120000-goal", goal: "Add a Capture submenu", repo: "/tmp/repo", mode: "edit", started: "20261010-120000", rounds: 1, turns: 2, finished: "done" },
                                      { dir: "/tmp/sessions/b", name: "20261010-130000-review", goal: "Review the bar", repo: "/tmp/repo", mode: "read", started: "20261010-130000", rounds: 2, turns: 4, finished: "rounds" }];
                    break;
                case 4:
                    window.shot("relay-sessions");
                    pages.navigate("settings");
                    break;
                case 5:
                    window.shot("relay-settings");
                    window.pagesWidth = 640; pages.navigate("session");
                    break;
                case 6:
                    window.check(!pages.sidebar, "Narrow windows use the tab strip");
                    Relay.clear();
                    window.check(Relay.turns.length === 0 && Relay.goal === "" && Relay.finished === "" && Relay.relays.length === 0, "New goal clears the view");
                    window.shot("relay-narrow");
                    break;
                case 7:
                    // One agent alone: the rail shows it, Codex is not required, and a session carries its agents.
                    Config.set("relayAgents", "claude");
                    window.check(Relay.solo && Relay.preferredAgents === "claude" && pages.pairLabel === "CLAUDE ALONE", "Claude alone is a preference (" + pages.pairLabel + ")");
                    Relay.tools = { claude: "/usr/bin/claude", codex: "" };
                    window.check(Relay.available && Relay.missing === "", "A Claude-only session does not need Codex");
                    window.feed({ type: "session", dir: "/tmp/sessions/20261010-140000-solo", name: "20261010-140000-solo", goal: "Solo goal", repo: "/tmp/repo", mode: "edit", agents: "claude" });
                    window.check(Relay.agentsUsed === "claude" && Relay.soloSession && pages.unitWord === "TURN", "The session event sets the agents (" + Relay.agentsUsed + ")");
                    window.pagesWidth = 1180;
                    window.shot("relay-solo");
                    Config.set("relayAgents", "both");
                    break;
                case 8:
                    console.log("PASS: Relay session events, the rail state and the CEDAR AI pages");
                    Qt.quit();
                }
            }
        }
    }
}
''')
    env = {**os.environ, 'CEDAR_TEST': '1', 'QT_QPA_PLATFORM': 'offscreen', 'QT_QPA_PLATFORMTHEME': 'basic', 'QT_QUICK_CONTROLS_STYLE': 'Basic', 'QSG_RHI_BACKEND': 'software', 'XDG_RUNTIME_DIR': str(runtime), 'XDG_CONFIG_HOME': str(p / 'config'), 'XDG_STATE_HOME': str(p / 'state'), 'CEDAR_SCREENSHOT_DIR': str(shots)}
    result = subprocess.run(['qs', '-p', str(source / 'preview.qml')], env=env, capture_output=True, text=True, timeout=60)
    output = result.stdout + result.stderr
    if result.returncode or 'PASS: Relay' not in output or re.search(r'Failed to load configuration|ReferenceError|TypeError|Binding loop|Cannot assign|is not defined|Unable to assign|FAIL:', output):
        print(output[-6000:]); raise SystemExit(1)
    print('PASS: Relay session events, the rail state and the CEDAR AI pages')
