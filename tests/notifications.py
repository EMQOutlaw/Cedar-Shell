#!/usr/bin/env python3
"""Run under dbus-run-session; never acquire the real desktop notification name."""
import os
from pathlib import Path
import subprocess
import time
ROOT=Path(__file__).resolve().parent
path=ROOT.parent/'notification-test.qml'
log=(ROOT/'notifications.log').open('w')
proc=subprocess.Popen(['qs','-p',str(path),'--no-color'], stdout=log,stderr=log)
def ipc(method):
    return subprocess.check_output(['qs','-p',str(path),'ipc','call','test',method],text=True).strip()
try:
    time.sleep(1)
    subprocess.run(['notify-send','-t','0','CEDAR test','A signal from the ridge.'],check=True)
    time.sleep(.4)
    assert ipc('count')=='1'
    assert ipc('live')=='1'
    assert ipc('body')=='A signal from the ridge.'
    ipc('dismiss'); time.sleep(.2)
    assert ipc('live')=='0'
    assert ipc('count')=='1'
    subprocess.run(['notify-send','-t','200','Short signal','Expires but remains in history'],check=True)
    time.sleep(.5)
    assert ipc('live')=='0'
    assert ipc('count')=='2'
    ipc('quit')
    print('Notification delivery, dismissal, expiry and retained history passed.')
finally:
    proc.terminate(); proc.wait(timeout=4); log.close()
print((ROOT/'notifications.log').read_text())
