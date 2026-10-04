#!/usr/bin/env python3
"""Offscreen visual and behavioral checks. No PAM, network, or real lock."""
from pathlib import Path
import os,re,shutil,subprocess,sys,tempfile
ROOT=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='cedar-trailwatch-') as tmp:
    base=Path(tmp);source=base/'shell'
    shutil.copytree(ROOT,source,ignore=shutil.ignore_patterns('__pycache__','.git','*.log','*.png'))
    (base/'runtime').mkdir(mode=0o700)
    shots=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else base/'shots';shots.mkdir(parents=True,exist_ok=True)
    harness=(ROOT/'tests/qml/TrailwatchHarness.qml').read_text().replace('../../modules','modules').replace('../../services','services').replace('../../components','components').replace('import "../.."','import "."')
    (source/'preview.qml').write_text(harness)
    env={**os.environ,'CEDAR_TEST':'1','QT_QPA_PLATFORM':'offscreen','QT_QPA_PLATFORMTHEME':'basic','QT_QUICK_CONTROLS_STYLE':'Basic','QSG_RHI_BACKEND':'software','XDG_RUNTIME_DIR':str(base/'runtime'),'XDG_CONFIG_HOME':str(base/'config'),'CEDAR_SCREENSHOT_DIR':str(shots)}
    result=subprocess.run(['qs','-p',str(source/'preview.qml')],env=env,capture_output=True,text=True,timeout=25)
    output=result.stdout+result.stderr
    if result.returncode or 'PASS: Trailwatch' not in output or re.search(r'FAIL:|Failed to load configuration|ReferenceError|TypeError|Binding loop|Cannot assign|Unable to assign|recursive rearrange|is not defined',output):
        print(output);raise SystemExit(1)
    print('PASS: Trailwatch at 1920×1080, 3440×1440, 1366×768, 800×900 and 480×800; privacy, auth UI, reduced motion, sun and readiness checks')
