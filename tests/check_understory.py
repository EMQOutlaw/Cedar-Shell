#!/usr/bin/env python3
"""Render the Understory rail offscreen over the test services and check its routing."""
from pathlib import Path
import os, re, shutil, subprocess, sys, tempfile
ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='understory-') as tmp, tempfile.TemporaryDirectory(prefix='.ui-', dir=ROOT) as rt:
    p = Path(tmp); source = p / 'shell'; shutil.copytree(ROOT, source, ignore=shutil.ignore_patterns('__pycache__', '.git', '.ui-*', '.diag-*'))
    runtime = Path(rt)
    # Offscreen has no layer-shell backend. Keep production geometry/lifecycle,
    # replace ONLY its native host and attached layer properties in this copy.
    for name in ('UnderstoryWindow', 'UnderstoryBar', 'UnderstoryDictation'):
        path = source / 'modules' / (name + '.qml')
        qml = path.read_text().replace('PanelWindow {', 'FloatingWindow {')
        qml = '\n'.join(line for line in qml.splitlines() if not any(token in line for token in ('WlrLayershell.', 'exclusionMode:', 'mask: Region', 'anchors { top:', 'margins.top:', 'margins.left:')))
        if name == 'UnderstoryWindow':
            qml = qml.replace('screen: modelData', 'screen: modelData\n    implicitHeight: 640')
        elif name == 'UnderstoryBar':
            qml = qml.replace('screen: output', 'screen: output\n    implicitHeight: 480')
            qml = re.sub(r'readonly property var localWorkspaces:.*', 'readonly property var localWorkspaces: Array.from({length:40}, (_,i) => ({id:i+1,name:String(i+1),urgent:false,activate:function(){}}))', qml)
        if name == 'UnderstoryDictation':
            # Exercise only the visual transition in test mode; service safety
            # gates remain intact, so no recorder or hardware is started.
            qml = qml.replace('VisualQuality.functionalMotion && !Config.testMode', 'VisualQuality.functionalMotion')
        qml = '\n'.join(line for line in qml.splitlines() if 'exclusiveZone:' not in line)
        path.write_text(qml)
    # Separate stage-disabled load proves privacy fallback respects stage gates.
    dictation_source = (ROOT / 'modules/UnderstoryDictation.qml').read_text()
    assert 'mask: Region {}' in dictation_source
    assert 'WlrLayershell.keyboardFocus: WlrKeyboardFocus.None' in dictation_source
    assert 'HyprlandFocusGrab' not in dictation_source
    shots = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else p / 'shots'; shots.mkdir(parents=True, exist_ok=True)
    harness = (ROOT / 'tests/core/UnderstoryHarness.qml').read_text().replace('"../.."', '"."').replace('"../../', '"')
    (source / 'preview.qml').write_text(harness)
    env = {**os.environ, 'CEDAR_TEST': '1', 'QT_QPA_PLATFORM': 'offscreen', 'QT_QPA_PLATFORMTHEME': 'basic', 'QT_IM_MODULE': 'compose', 'QSG_RENDER_LOOP': 'basic', 'QT_QUICK_CONTROLS_STYLE': 'Basic', 'QSG_RHI_BACKEND': 'software', 'XDG_RUNTIME_DIR': str(runtime), 'XDG_CONFIG_HOME': str(p / 'config'), 'XDG_STATE_HOME': str(p / 'state'), 'CEDAR_SCREENSHOT_DIR': str(shots)}
    env.pop('WAYLAND_DISPLAY', None)
    result = subprocess.run(['qs', '-p', str(source / 'preview.qml')], env=env, capture_output=True, text=True, timeout=40)
    output = result.stdout + result.stderr
    if result.returncode or 'PASS: Understory rail' not in output or re.search(r'Failed to load configuration|ReferenceError|TypeError|Binding loop|Cannot assign|is not defined|Unable to assign|setRunning\(\)|FAIL:', output):
        print(output); raise SystemExit(1)
    if not (shots / 'understory.png').exists(): raise SystemExit('Missing render: understory.png')
    (source / 'stage-check.qml').write_text('import QtQuick\nimport Quickshell\nimport "."\nimport "modules"\nimport "services"\nShellRoot { UnderstoryDictation { id: dot; modelData: Quickshell.screens[0] } Timer { interval: 300; running:true; onTriggered: { Config.saved.barPlacement="understory"; Config.saved.coreEnabled=false; Dictation.installed=true; Dictation.daemon=true; Dictation.state="recording"; Config.fullscreenFocused=true; Config.fullscreenScreen=Quickshell.screens[0].name; if (dot.visible || dot.dotOnly || dot.contentLoaded || Dictation.levelsWanted) console.log("FAIL: stage-disabled dot"); else console.log("PASS stage-disabled dot"); Qt.quit(); } } }')
    stage = subprocess.run(['qs', '-p', str(source / 'stage-check.qml')], env={**env, 'CEDAR_STAGE':'1'}, capture_output=True, text=True, timeout=10)
    stage_output = stage.stdout + stage.stderr
    if stage.returncode or 'PASS stage-disabled dot' not in stage_output or 'FAIL:' in stage_output:
        print(stage_output); raise SystemExit(1)
    print(output)
    print(stage_output)
    print('PASS', shots / 'understory.png')
