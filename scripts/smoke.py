#!/usr/bin/env python3
"""Short live preview. Does not acquire notification ownership or lock the session."""
from pathlib import Path
import os
import subprocess
import sys
import time

from distribution import ensure_unlocked
from portable_providers import qs_instances
ensure_unlocked()
root = Path(__file__).resolve().parents[1]
if any(Path(row.get('config_path', '/unavailable')).resolve() == root/'shell.qml' for row in qs_instances()):
    raise SystemExit('This source is already running. Use a disposable checkout for smoke testing.')
log_path = root/'tests/runtime.log'
CALLS = [['hud', 'toggle'], ['menu', 'toggle', 'root'], ['launcher', 'toggle'], ['menu', 'toggle', 'apps'], ['menu', 'toggle', 'setup.plugin'],
         ['menu', 'summon', '{"mode":"select","prompt":"Smoke","options":["✓\tOne\tfirst","Two"]}'],
         ['settings', 'toggle'], ['notifications', 'toggle'], ['power', 'toggle'], ['themes', 'toggle'], ['wallpapers', 'toggle']]
with log_path.open('w') as log:
    proc = subprocess.Popen(['qs','-p',str(root),'--no-color'], stdout=log, stderr=log, env={**os.environ,'CEDAR_TEST':'1'})
    try:
        time.sleep(2)
        if proc.poll() is not None: raise RuntimeError(log_path.read_text())
        for call in CALLS:
            r = subprocess.run(['qs','-p',str(root),'ipc','call',*call], capture_output=True,text=True)
            if r.returncode or 'not found' in r.stdout.lower(): raise RuntimeError(' '.join(call)+'\n'+r.stdout+r.stderr)
            time.sleep(.8)
            if call[0] == 'hud' and '--capture' in sys.argv:
                subprocess.run(['grim',str(root/'tests/hud-preview.png')],check=True)
        subprocess.run(['qs','-p',str(root),'ipc','call','shell','close'],check=True)
        subprocess.run(['qs','-p',str(root),'ipc','call','osd','showVolume'],check=True)
        time.sleep(.5)
    finally:
        proc.terminate()
        try: proc.wait(timeout=5)
        except subprocess.TimeoutExpired: proc.kill()
text = log_path.read_text()
print(text)
if any(s in text for s in ['ERROR','WARN scene','TypeError','ReferenceError','Binding loop']): raise SystemExit(1)
print('HUD, Go menu, prompt, settings, history, power, pickers and volume OSD smoke test passed.')
