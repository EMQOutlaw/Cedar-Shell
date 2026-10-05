#!/usr/bin/env python3
"""Private, read-only /proc samples. Never launch or stop a desktop provider.

CPU is percent of ONE logical CPU, not divided by machine CPU count. PSS is
proportional resident memory; summed RSS double-counts shared pages. Descendant
helper starts observed between samples are a lower bound, not spawn tracing.
"""
import argparse
import json
import os
from pathlib import Path
import statistics
import time
import distribution as d


def stat_fields(raw):
    head,tail=raw.rsplit(')',1);fields=tail.split()
    return {'pid':int(head.split('(',1)[0]),'parent':int(fields[1]),'start':int(fields[19]),
            'ticks':int(fields[11])+int(fields[12]),'rss':int(fields[21])*os.sysconf('SC_PAGE_SIZE')}


def snapshot(roots,proc=Path('/proc')):
    all_rows={}
    for path in proc.glob('[0-9]*/stat'):
        try:
            row=stat_fields(path.read_text());all_rows[row['pid']]=row
        except (OSError,ValueError,IndexError):continue
    selected={pid for pid,start in roots.items() if pid in all_rows and all_rows[pid]['start']==start}
    changed=True
    while changed:
        children={pid for pid,row in all_rows.items() if row['parent'] in selected}
        changed=not children<=selected;selected|=children
    result={}
    for pid in selected:
        row=all_rows[pid];row['pss']=None
        try:
            for line in (proc/str(pid)/'smaps_rollup').read_text().splitlines():
                if line.startswith('Pss:'):row['pss']=int(line.split()[1])*1024
            current=stat_fields((proc/str(pid)/'stat').read_text())
            if current['start']!=row['start']:continue
        except OSError:pass
        result[(pid,row['start'])]=row
    return result


def compare(previous,current,elapsed,ticks):
    common=previous.keys()&current.keys()
    cpu=sum(max(0,current[k]['ticks']-previous[k]['ticks']) for k in common)/ticks/elapsed*100
    return {'cpuOneCorePercent':cpu,'rssSumBytes':sum(r['rss'] for r in current.values()),
            'pssBytes':sum(r['pss'] for r in current.values()) if all(r['pss'] is not None for r in current.values()) else None,
            'processes':len(current),'newIdentities':len(current.keys()-previous.keys())}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pid',type=int,action='append',required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--warmup',type=int,default=120)
    parser.add_argument('--seconds',type=int,default=180)
    parser.add_argument('--runs',type=int,default=3)
    args=parser.parse_args()
    if not 1<=args.runs<=10 or not 1<=args.seconds<=3600 or not 0<=args.warmup<=600:parser.error('Invalid bounded sampling duration')
    d.private_directory(args.output.parent)
    roots={pid:stat_fields((Path('/proc')/str(pid)/'stat').read_text())['start'] for pid in args.pid}
    report={'format':1,'cpuNormalization':'100% = one logical CPU','rssMeaning':'Sum; shared pages may be counted repeatedly',
            'scope':'Explicit root PIDs and observable descendants only; detached user services must be supplied separately',
            'spawnMeaning':'Sampled new identities, a lower bound; sub-second helpers can be missed',
            'nativeCompatibility':'Not established by resource measurements','runs':[]}
    ticks=os.sysconf('SC_CLK_TCK')
    for run in range(args.runs):
        time.sleep(args.warmup)
        previous=snapshot(roots);last=time.monotonic();samples=[]
        for _ in range(args.seconds):
            time.sleep(max(0,1-(time.monotonic()-last)))
            current=snapshot(roots);now=time.monotonic()
            if any((pid,start) not in current for pid,start in roots.items()):raise d.Refused('A sampled root exited or changed identity. No comparable run was recorded.')
            samples.append(compare(previous,current,now-last,ticks));previous=current;last=now
        report['runs'].append({'warmupSeconds':args.warmup,'sampleCount':len(samples),'samples':samples,
                               'medianCpuOneCorePercent':statistics.median(s['cpuOneCorePercent'] for s in samples)})
        d.write_json(args.output,report)
    print('Private measurement report written. Compare only equivalent workloads and session conditions.')


if __name__=='__main__':main()
