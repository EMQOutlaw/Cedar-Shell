#!/usr/bin/env python3
"""Surface policy over the test services, offscreen, with isolated preferences.

Core under both bar placements, state retention across placement switches,
one interactive surface (Core hub, Canopy incl. pinned, Understory, Settings),
lock cleanup without reopen, and the dictation presenter. No compositor: layer
placement and focus grabs remain live checks.
"""
from pathlib import Path
import json, os, re, shutil, subprocess, tempfile
ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='cedar-surface-policy-') as tmp:
    p = Path(tmp); source = p / 'shell'; shutil.copytree(ROOT, source, ignore=shutil.ignore_patterns('__pycache__', '.git', '.ui-*'))
    runtime = p / 'runtime'; runtime.mkdir(mode=0o700)
    config = p / 'config/cedar'; config.mkdir(parents=True)
    (config / 'settings.json').write_text(json.dumps({'barPlacement': 'top', 'coreEnabled': True, 'coreWarnings': True, 'coreDictation': True, 'canopyEnabled': True}))
    screens = p / 'screens.json'; screens.write_text(json.dumps({'screens': [{'name': 'DP-1', 'width': 1920, 'height': 1080}]}))
    # Offscreen has no layer-shell backend. Keep CoreWindow's production
    # bindings (covered, pillShown, emberDot, inputRegionEmpty, visible); swap
    # only its native host and the attached layer/mask properties in this copy.
    core = source / 'modules/CoreWindow.qml'
    qml = core.read_text().replace('PanelWindow {', 'FloatingWindow {')
    qml = re.sub(r'\n[ \t]*mask: [^\n]*\n.*?Region \{ id: dotMask \}', '', qml, flags=re.S)
    qml = '\n'.join(line for line in qml.splitlines() if not any(token in line for token in ('WlrLayershell.', 'exclusionMode:', 'anchors.top:', 'anchors.left:', 'margins.top:', 'margins.left:')))
    assert not re.search(r'\bRegion \{', qml) and 'mask:' not in qml, 'CoreWindow mask block not rewritten for offscreen'
    core.write_text(qml)
    env = {**os.environ, 'CEDAR_TEST': '1', 'QT_QPA_PLATFORM': 'offscreen:configfile=' + str(screens), 'QT_QPA_PLATFORMTHEME': 'basic', 'QT_QUICK_CONTROLS_STYLE': 'Basic', 'QSG_RHI_BACKEND': 'software', 'XDG_RUNTIME_DIR': str(runtime), 'XDG_CONFIG_HOME': str(p / 'config'), 'XDG_STATE_HOME': str(p / 'state')}
    env.pop('WAYLAND_DISPLAY', None)
    for name, marker in (('SurfacePolicyHarness', 'PASS: surface policy'), ('CoveredCoreHarness', 'PASS: covered core')):
        # Each harness gets fresh preferences and state: nothing one run saved leaks into the next.
        home = p / name; (home / 'config/cedar').mkdir(parents=True); (home / 'state').mkdir()
        (home / 'config/cedar/settings.json').write_text(json.dumps({'barPlacement': 'top', 'coreEnabled': True, 'coreWarnings': True, 'coreDictation': True, 'canopyEnabled': True}))
        env.update({'XDG_CONFIG_HOME': str(home / 'config'), 'XDG_STATE_HOME': str(home / 'state')})
        harness = (ROOT / 'tests/core' / (name + '.qml')).read_text().replace('"../.."', '"."').replace('"../../', '"')
        (source / 'preview.qml').write_text(harness)
        try:
            result = subprocess.run(['qs', '-p', str(source / 'preview.qml')], env=env, capture_output=True, text=True, timeout=40)
        except subprocess.TimeoutExpired as e:
            print((e.stdout or b'').decode(errors='replace') if isinstance(e.stdout, bytes) else (e.stdout or ''))
            print((e.stderr or b'').decode(errors='replace') if isinstance(e.stderr, bytes) else (e.stderr or ''))
            raise SystemExit(name + ' did not exit (hung)')
        output = result.stdout + result.stderr
        if result.returncode or marker not in output or re.search(r'Failed to load configuration|ReferenceError|TypeError|Binding loop|Cannot assign|is not defined|Unable to assign|FAIL:', output):
            print(output); raise SystemExit(1)
    print('PASS: surface policy (Core in both placements, retained state, single surface incl. pinned Canopy and Settings, lock, dictation presenter) and covered Core (dot only, no input, levels only with a live filament)')
