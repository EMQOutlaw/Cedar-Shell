#!/usr/bin/env python3
"""Read a real GPU where a supported telemetry source exists."""
import json,subprocess,shutil
from pathlib import Path
def snapshot():
    if shutil.which('nvidia-smi'):
        p=subprocess.run(['nvidia-smi','--query-gpu=name,utilization.gpu,temperature.gpu,memory.used,memory.total','--format=csv,noheader,nounits'],capture_output=True,text=True,timeout=3)
        if p.returncode==0:
            rows=[]
            for line in p.stdout.splitlines():
                v=[s.strip() for s in line.split(',')]
                if len(v)==5:
                    def num(s):
                        try:return float(s)
                        except ValueError:return None
                    rows.append(dict(name=v[0],load=num(v[1]),temperature=num(v[2]),used=num(v[3]),total=num(v[4])))
            return dict(gpus=rows)
    rows=[]
    for d in Path('/sys/class/drm').glob('card[0-9]*/device'):
        def read(name,factor=1):
            try:return int((d/name).read_text())/factor
            except (OSError,ValueError):return None
        if (d/'gpu_busy_percent').exists():rows.append(dict(name=d.parent.name,load=read('gpu_busy_percent'),temperature=None,used=read('mem_info_vram_used',1048576),total=read('mem_info_vram_total',1048576)))
    return dict(gpus=rows)
if __name__=='__main__':
    try:print(json.dumps(dict(ok=True,data=snapshot())))
    except Exception as e:print(json.dumps(dict(ok=False,error=str(e))))
