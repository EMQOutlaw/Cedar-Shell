#!/usr/bin/env python3
"""Reproducible standalone design validation; never changes installed CEDAR.

--native maps a short-lived test window in the current Wayland session.
--baseline compares two real collector workloads using the selected renderer.
All settings, captures, and sockets belong to isolated test directories.
"""
import argparse
import json
import os
from pathlib import Path
import re
import statistics
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]

def environment(base, native=False):
    for name in ('runtime', 'config', 'state', 'cache'):
        (base/name).mkdir(mode=0o700)
    env = dict(os.environ)
    env.update(QT_FORCE_STDERR_LOGGING='1', QT_QUICK_CONTROLS_STYLE='Basic', QT_QPA_PLATFORMTHEME='basic',
               XDG_RUNTIME_DIR=str(base/'runtime'), XDG_CONFIG_HOME=str(base/'config'),
               XDG_STATE_HOME=str(base/'state'), XDG_CACHE_HOME=str(base/'cache'))
    env.pop('CEDAR_TASK_TEST_LOCAL_COLLECTOR', None)
    if native:
        display = os.environ.get('WAYLAND_DISPLAY', 'wayland-0')
        env['WAYLAND_DISPLAY'] = display if display.startswith('/') else str(Path(os.environ['XDG_RUNTIME_DIR'])/display)
        env['QT_QPA_PLATFORM'] = 'wayland'
        env.pop('QT_QUICK_BACKEND', None)
    else:
        env.update(QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software', QSG_RENDER_LOOP='basic', HYPRLAND_INSTANCE_SIGNATURE='')
    return env

def usage(pid):
    raw = Path(f'/proc/{pid}/stat').read_text().rsplit(')', 1)[1].split()
    result = {'cpuSeconds': (int(raw[11])+int(raw[12]))/os.sysconf('SC_CLK_TCK'),
              'rssMiB': int(raw[21])*os.sysconf('SC_PAGESIZE')/1048576}
    try:
        fields = dict(re.findall(r'^(\w+):\s+(\d+)', Path(f'/proc/{pid}/smaps_rollup').read_text(), re.M))
        result['pssMiB'] = int(fields['Pss'])/1024
    except (OSError, KeyError):
        result['pssMiB'] = None
    return result

def benchmark(source, output, seconds=12, native=False):
    with tempfile.TemporaryDirectory(prefix='cedar-design-bench-') as tmp:
        base=Path(tmp); env=environment(base,native)
        with output.with_suffix('.log').open('w') as log:
            app=subprocess.Popen([str(source/'.local/task-manager/cedar-task-manager'),'--source',str(source)],env=env,stdout=log,stderr=log)
            try:
                time.sleep(4)
                children=Path(f'/proc/{app.pid}/task/{app.pid}/children').read_text().split()
                assert len(children)==1, 'Expected one dedicated collector'
                pids={'frontend':app.pid,'backend':int(children[0])}
                rows=[]
                for _ in range(seconds+1):
                    rows.append({'time':time.monotonic(),**{name:usage(pid) for name,pid in pids.items()}})
                    if len(rows)<=seconds: time.sleep(1)
                elapsed=rows[-1]['time']-rows[0]['time']
                result={name:{'cpuPercentOneCore':100*(rows[-1][name]['cpuSeconds']-rows[0][name]['cpuSeconds'])/elapsed,
                    'meanRssMiB':statistics.mean(row[name]['rssMiB'] for row in rows),
                    'rssGrowthMiB':rows[-1][name]['rssMiB']-rows[0][name]['rssMiB'],
                    'meanPssMiB':statistics.mean(row[name]['pssMiB'] for row in rows) if all(row[name]['pssMiB'] is not None for row in rows) else None} for name in pids}
                result.update(source=str(source),seconds=elapsed,renderer='Wayland/native' if native else 'software/offscreen',samples=rows)
                if native:
                    clients=json.loads(subprocess.check_output(['hyprctl','-j','clients']))
                    client=next((c for c in clients if c.get('pid')==app.pid),{})
                    result['windowLogicalSize']=client.get('size')
            finally:
                app.terminate(); app.wait(timeout=5)
            result['socketsCleaned']=not list((base/'runtime').rglob('*.sock'))
        output.write_text(json.dumps(result,indent=2)+'\n')
        print(json.dumps({k:v for k,v in result.items() if k!='samples'}),flush=True)

def visual(source, output, native=False, scale=1):
    with tempfile.TemporaryDirectory(prefix='cedar-design-visual-') as tmp:
        base=Path(tmp);env=environment(base,native)
        config=base/'config/cedar';config.mkdir()
        (config/'settings.json').write_text(json.dumps({'fontScale':scale,'reducedMotion':scale>1}))
        env['CEDAR_TASK_CAPTURE_DIR']=str(output)
        output.mkdir(parents=True,exist_ok=True)
        with (output/'runtime.log').open('w') as log:
            app=subprocess.Popen([str(source/'.local/task-manager/cedar-task-manager'),'--source',str(source),'--self-test'],env=env,stdout=log,stderr=log)
            try:
                if native:
                    # Float only this isolated fixture; no persistent window rule.
                    for _ in range(80):
                        clients=json.loads(subprocess.check_output(['hyprctl','-j','clients']))
                        match=next((c for c in clients if c.get('pid')==app.pid),None)
                        if match:
                            subprocess.run(['hyprctl','eval',f'local w=hl.get_active_window(); if w and w.pid=={app.pid} and not w.floating then hl.dispatch(hl.dsp.window.float({{window=w}})) end'],check=True,stdout=subprocess.DEVNULL)
                            break
                        if app.poll() is not None:break
                        time.sleep(.05)
                app.wait(timeout=35)
            finally:
                if app.poll() is None:app.terminate();app.wait(timeout=5)
        log=(output/'runtime.log').read_text()
        assert app.returncode==0,log
        assert 'PASS: Standalone' in log,log
        assert not re.search(r'ReferenceError|TypeError|Binding loop|Cannot assign|Unable to assign|failed to load|Detected anchors',log,re.I),log
        assert not list((base/'runtime').rglob('*.sock')),'Fixture sockets survived close'
        print(f'PASS: {"Wayland" if native else "offscreen"}, font scale {scale}; captures {output}',flush=True)

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source',type=Path,default=ROOT)
    parser.add_argument('--baseline',type=Path)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--native',action='store_true')
    parser.add_argument('--measure',action='store_true')
    parser.add_argument('--measure-only',action='store_true')
    args=parser.parse_args();args.output.mkdir(parents=True,exist_ok=True)
    if args.baseline:benchmark(args.baseline,args.output/('native-baseline.json' if args.native else 'baseline.json'),native=args.native)
    if args.measure:benchmark(args.source,args.output/('native-redesign.json' if args.native else 'redesign.json'),native=args.native)
    if args.measure_only:raise SystemExit(0)
    visual(args.source,args.output/('native' if args.native else 'offscreen'),args.native)
    visual(args.source,args.output/'accessible',False,1.5)
