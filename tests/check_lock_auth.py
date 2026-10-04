#!/usr/bin/env python3
"""Offscreen check; never calls PAM or locks the desktop."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
ROOT=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='cedar-auth-check-') as tmp:
    p=Path(tmp); (p/'components').mkdir(); (p/'runtime').mkdir(mode=0o700)
    shutil.copy2(ROOT/'components/LockAuth.qml',p/'components/LockAuth.qml')
    (p/'shell.qml').write_text((ROOT/'tests/qml/LockAuthHarness.qml').read_text().replace('../../components','components'))
    env={**os.environ,'QT_QPA_PLATFORM':'offscreen','QT_QPA_PLATFORMTHEME':'basic','QT_QUICK_CONTROLS_STYLE':'Basic','XDG_RUNTIME_DIR':str(p/'runtime')}
    result=subprocess.run(['qs','-p',str(p)],env=env,capture_output=True,text=True,timeout=10)
    output=result.stdout+result.stderr
    if result.returncode or 'PASS: lock authentication state machine' not in output or 'FAIL:' in output:
        print(output); raise SystemExit(1)
    print('PASS: lock authentication state machine (no password or session lock used)')
