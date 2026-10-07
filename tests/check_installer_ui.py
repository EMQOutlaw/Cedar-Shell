#!/usr/bin/env python3
"""Offscreen: the CEDAR Installer window through every stage, from fixture state.

The model runs in fixture mode (no engine process); the harness feeds it the
records the engine would send and captures each stage. It also starts the
real installer.qml once in fixture mode to prove the program loads
without CEDAR installed.
"""
from pathlib import Path
import json, os, re, shutil, subprocess, sys, tempfile
ROOT = Path(__file__).resolve().parents[1]
FACTS = {'distro': {'name': 'CachyOS', 'id': 'cachyos'}, 'architecture': 'x86_64', 'gpu': {'vendor': 'NVIDIA', 'driver': 'nvidia'}, 'compositor': {'name': 'hyprland', 'running': True},
         'hyprlandVersion': '0.56.2', 'quickshellVersion': '0.3.1', 'disk': {'total': 2 * 1024 ** 4, 'free': 620 * 1024 ** 3}, 'cedarVersion': '0.1.0-dev.15',
         'wallpapers': [{'path': '/users/station/Pictures/Wallpapers', 'images': 12}],
         'environment': {'id': 'hyde', 'name': 'HyDE', 'stack': 'Hyprland + Waybar', 'summary': 'HyDE dotfiles: Waybar, Rofi, swww and the hyde theme tooling.', 'adapter': 'hyprland', 'handoff': 'experimental',
                         'evidence': ['~/.config/hyde', 'hyde.conf', 'Waybar running'],
                         'keep': ['Monitor configuration', 'Keyboard layout', 'Existing applications', 'Wallpaper library', 'Hyprland device rules'],
                         'replace': ['Waybar', 'Dunst', 'swww']},
         'technical': [{'label': 'Distribution', 'value': 'CachyOS'}, {'label': 'GPU', 'value': 'NVIDIA (nvidia)'}, {'label': 'Config source', 'value': '~/.config/hypr/hyprland.conf'}]}
PLAN = {'system': [{'text': 'Hyprland 0.56.2 already installed', 'state': 'ok'}, {'text': 'NVIDIA graphics · nvidia driver', 'state': 'ok'}, {'text': 'NetworkManager configured', 'state': 'ok'}],
        'migration': ['Back up the Hyprland configuration CEDAR may touch', 'Import 2 monitors (mode, position, scale, rotation)', 'Import keyboard layout', 'Pause Waybar while CEDAR runs', 'Pause Dunst while CEDAR runs'],
        'cedar': ['Install dependencies: quickshell, hypridle', 'Install CEDAR 0.1.0-dev.15 as a versioned copy with the cedar command and offline recovery', 'Check that the CEDAR shell loads with this Quickshell and Qt', 'Start CEDAR in this session, keep it after a health check, and enable it at login', 'Verify the installation'],
        'packages': ['quickshell', 'hypridle'], 'packageNotes': ['Uses your configured pacman repositories.'], 'attention': [{'id': 'nvidia', 'title': 'NVIDIA with Secure Boot', 'detail': 'Secure Boot can keep an unsigned module from loading.', 'severity': 'warn', 'learn': 'https://example.invalid'}],
        'backupDestination': '~/.local/state/cedar/installations/<timestamp>', 'digest': 'abc123', 'blocked': False, 'options': {'session': True, 'launcher': False, 'trailwatch': False, 'fonts': False, 'wallpapers': True, 'migrate': True}, 'imports': ['2 monitors', 'Keyboard layout', 'Existing wallpaper library']}
OPS = [('backup', 'System backup'), ('dependencies', 'Dependencies'), ('runtime', 'CEDAR runtime'), ('shell', 'CEDAR shell'), ('migrate', 'Configuration'), ('session', 'Session'), ('verify', 'Verification')]
def ops(states):
    return [{'id': i, 'title': t, 'description': '', 'state': states.get(i, 'pending'), 'progress': 1 if states.get(i) == 'complete' else 0, 'detail': 'Installing quickshell…' if states.get(i) == 'running' else '', 'error': ''} for i, t in OPS]
with tempfile.TemporaryDirectory(prefix='cedar-installer-ui-') as tmp:
    p = Path(tmp); source = p / 'shell'; shutil.copytree(ROOT, source, ignore=shutil.ignore_patterns('__pycache__', '.git'))
    runtime = p / 'runtime'; runtime.mkdir(mode=0o700)
    shots = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else p / 'shots'; shots.mkdir(parents=True, exist_ok=True)
    (source / 'installer-preview.qml').write_text('''
import QtQuick
import Quickshell
import "installer/ui"
ShellRoot {
    settings.watchFiles: false
    InstallerModel { id: model }
    FloatingWindow {
        id: window
        visible: true; implicitWidth: 1120; implicitHeight: 720; color: Theme.background
        function check(ok, msg) { if (!ok) { console.error("FAIL: " + msg); Qt.exit(1); } }
        function shot(name) { body.grabToImage(r => r.saveToFile(Quickshell.env("CEDAR_SCREENSHOT_DIR") + "/installer-" + name + ".png")); }
        property int step: 0
        property var facts: ''' + json.dumps(FACTS) + '''
        property var plan: ''' + json.dumps(PLAN) + '''
        property var running: ''' + json.dumps(ops({'backup': 'complete', 'dependencies': 'running'})) + '''
        property var done: ''' + json.dumps(ops({'backup': 'complete', 'dependencies': 'complete', 'runtime': 'complete', 'shell': 'complete', 'migrate': 'warning', 'session': 'complete', 'verify': 'complete'})) + '''
        Item {
            id: body; anchors.fill: parent
            Rectangle { anchors.fill: parent; color: Theme.background }
            SystemVisual { id: visual; model: model; visible: model.stage !== "welcome"; width: Math.round(parent.width * .44); anchors { left: parent.left; top: parent.top; bottom: parent.bottom } }
            StagePane { id: pane; model: model; anchors { left: visual.visible ? visual.right : parent.left; right: parent.right; top: parent.top; bottom: parent.bottom } }
        }
        Timer {
            interval: 500; running: true; repeat: true
            onTriggered: {
                switch (window.step++) {
                case 0: window.check(model.fixture && model.stage === "welcome", "Fixture model starts at welcome"); model.version = "0.1.0-dev.15"; break;
                case 1: window.shot("welcome"); break;
                case 2: model.stage = "scan"; model.busy = true; break;
                case 3: window.shot("scan"); break;
                case 4: model.facts = window.facts; model.plan = window.plan; model.options = window.plan.options; model.busy = false; model.stage = "environment"; break;
                case 5: window.check(model.environment.name === "HyDE", "Environment from facts"); window.shot("environment"); break;
                case 6: model.stage = "plan"; break;
                case 7: window.shot("plan"); break;
                case 8: model.plan = Object.assign({}, window.plan, { blocked: true, attention: [{ id: "unsupported", title: "Dependencies are missing on an unsupported distribution", detail: "Install these with your package manager, then run the installer again: quickshell.", severity: "stop", learn: "" }] }); model.stage = "attention"; break;
                case 9: window.shot("attention"); break;
                case 10: model.plan = window.plan; model.previous = { completed: 4, total: 7, interruptedAt: "shell", operations: window.running.map((o, i) => Object.assign({}, o, { state: i < 4 ? "complete" : i === 4 ? "running" : "pending" })) }; model.stage = "interrupted"; break;
                case 11: window.shot("interrupted"); break;
                case 12: model.stage = "install"; model.operations = window.running; model.password = "The terminal that started the installer will ask for your password."; model.append("dependencies", "resolving dependencies..."); model.append("dependencies", "installing quickshell..."); break;
                case 13: window.check(Math.abs(model.progress - 1 / 7) < .001 && model.current.id === "dependencies", "Progress counts finished operations (" + model.progress + ")"); window.shot("install"); break;
                case 14: model.showDetails = true; break;
                case 15: window.shot("install-details"); break;
                case 16: model.showDetails = false; model.error = { operation: "runtime", title: "CEDAR runtime", message: "Insufficient space for staging and recovery.", changedBefore: ["System backup", "Dependencies"], rolledBack: true, resumable: true, log: "~/.local/state/cedar/installer/logs/run.jsonl", preserved: "Your original configuration is still backed up. No existing desktop files were deleted." }; model.stage = "error"; break;
                case 17: window.shot("error"); break;
                case 18: model.operations = window.done; model.result = { ok: true, imports: window.plan.imports, backup: "~/.local/state/cedar/installations/2026-10-07T120000", sessionState: "kept" }; model.stage = "finish"; break;
                case 19: window.check(model.cedarRunning && model.progress === 1, "Finish with a kept session"); window.shot("finish"); model.operations = window.done.map(o => o.id === "session" ? Object.assign({}, o, { state: "warning", detail: "CEDAR is installed but was not started: Authentication test did not succeed. Existing desktop preserved; no session lock was requested." }) : o); model.result = Object.assign({}, model.result, { sessionState: "not active" }); break;
                case 20: window.check(!model.cedarRunning, "Not-started finish"); window.shot("finish-not-started"); break;
                case 21: model.restoreReport = { session: "restored", program: "program entry points restored", files: ["/users/station/.config/hypr/hyprland.conf"], conflicts: [] }; model.stage = "restored"; break;
                case 22: window.shot("restored"); break;
                case 23: console.log("PASS: CEDAR Installer stages"); Qt.quit();
                }
            }
        }
    }
}
''')
    env = {**os.environ, 'CEDAR_TEST': '1', 'CEDAR_INSTALLER_FIXTURE': '1', 'CEDAR_INSTALLER_SOURCE': str(source), 'QT_QPA_PLATFORM': 'offscreen', 'QT_QPA_PLATFORMTHEME': 'basic', 'QT_QUICK_CONTROLS_STYLE': 'Basic', 'QSG_RHI_BACKEND': 'software', 'XDG_RUNTIME_DIR': str(runtime), 'XDG_CONFIG_HOME': str(p / 'config'), 'XDG_STATE_HOME': str(p / 'state'), 'CEDAR_SCREENSHOT_DIR': str(shots), 'QS_DISABLE_FILE_WATCHER': '1'}
    result = subprocess.run(['qs', '-p', str(source / 'installer-preview.qml')], env=env, capture_output=True, text=True, timeout=60)
    output = result.stdout + result.stderr
    if result.returncode or 'PASS: CEDAR Installer stages' not in output or re.search(r'Failed to load configuration|ReferenceError|TypeError|Binding loop|Cannot assign|is not defined|Unable to assign|FAIL:', output):
        print(output[-6000:]); raise SystemExit(1)
    # The real program root loads in fixture mode and stays open until killed.
    try:
        app = subprocess.run(['qs', '-p', str(source / 'installer.qml')], env=env, capture_output=True, text=True, timeout=6)
        app_output = app.stdout + app.stderr
    except subprocess.TimeoutExpired as timeout:
        app_output = (timeout.stdout or b'').decode() + (timeout.stderr or b'').decode()
    if re.search(r'Failed to load configuration|ReferenceError|TypeError|Cannot assign|is not defined|Unable to assign', app_output):
        print(app_output[-4000:]); raise SystemExit(1)
    print('PASS: CEDAR Installer stages (' + ', '.join(sorted(f.name for f in shots.glob('installer-*.png'))) + ')')
