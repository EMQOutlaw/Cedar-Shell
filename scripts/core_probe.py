#!/usr/bin/env python3
"""One bounded monitor for recorder processes and keyboard LED state.

No keyboard events, clipboard contents, camera frames, or audio are read.
Processes are inspected only for the current uid. JSON is emitted on changes.
"""
import glob,json,os
from pathlib import Path
import time

PROC=Path('/proc');LEDS=Path('/sys/class/leds')
def recording(proc=PROC):
    rows=[]
    try: boot=time.time()-float((proc/'uptime').read_text().split()[0])
    except (OSError,ValueError):return []
    hz=os.sysconf('SC_CLK_TCK')
    for p in proc.iterdir():
        if not p.name.isdigit():continue
        try:
            if p.stat().st_uid!=os.getuid() or (p/'comm').read_text().strip()!='gpu-screen-reco':continue
            executable=os.path.basename(os.readlink(p/'exe'))
            if executable!='gpu-screen-recorder':continue
            args=(p/'cmdline').read_bytes().decode(errors='replace').split('\0')
            stat=(p/'stat').read_text().rsplit(')',1)[1].split()
            started=int(stat[19]);output=args[args.index('-o')+1] if '-o' in args else ''
            audio=[arg for i,arg in enumerate(args) if i and args[i-1]=='-a']
            microphone=True if any('default_input' in arg for arg in audio) else False if not audio or audio==['default_output'] else None
            rows.append({'pid':int(p.name),'startTicks':started,'started':int((boot+started/hz)*1000),
                'file':output,'microphone':microphone})
        except (OSError,ValueError,IndexError):continue
    return rows

def keyboard(paths):
    result={}
    for kind in ('capslock','numlock'):
        values=[]
        for p in paths.get(kind,[]):
            try:values.append(int(p.read_text().strip())>0)
            except (OSError,ValueError):pass
        if values:result[kind]=any(values)
    return result

def watch():
    previous=None;tick=0;recordings=[];paths={}
    while True:
        if tick%20==0:paths={k:list(LEDS.glob('*::'+k+'/brightness')) for k in ('capslock','numlock')}
        if tick%4==0:
            # /proc uptime has limited precision; retain the first observed
            # wall-clock start so clock rounding cannot generate fake changes.
            starts={(r['pid'],r['startTicks']):r['started'] for r in recordings}
            recordings=recording()
            for r in recordings:r['started']=starts.get((r['pid'],r['startTicks']),r['started'])
        data={'recordings':recordings,'keyboard':keyboard(paths)}
        if data!=previous:
            print(json.dumps(data),flush=True);previous=data
        tick+=1;time.sleep(.5)
if __name__=='__main__':
    try:watch()
    except (BrokenPipeError,KeyboardInterrupt):pass
