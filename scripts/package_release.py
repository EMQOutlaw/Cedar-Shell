#!/usr/bin/env python3
"""Deterministic complete private candidate; public release requires separate gates."""
from pathlib import Path
import argparse,gzip,hashlib,io,json,os,sys,tarfile
from distribution import ROOT,files,Refused

def package(root,destination):
    entries=files(root)
    if any(p==destination for p,_ in entries):raise Refused('Archive must be outside its input source tree.')
    inventory={str(rel):{'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'bytes':p.stat().st_size} for p,rel in entries}
    destination.parent.mkdir(parents=True,exist_ok=True)
    with destination.open('wb') as output,gzip.GzipFile(filename='',mode='wb',fileobj=output,mtime=0) as compressed,tarfile.open(mode='w',fileobj=compressed,format=tarfile.PAX_FORMAT) as tar:
        for p,rel in entries:
            data=p.read_bytes();entry=tarfile.TarInfo('cedar-shell/'+str(rel));entry.size=len(data);entry.mode=0o755 if os.access(p,os.X_OK) else 0o644
            entry.uid=entry.gid=0;entry.uname=entry.gname='';entry.mtime=0;tar.addfile(entry,io.BytesIO(data))
        data=(json.dumps(inventory,sort_keys=True,indent=2)+'\n').encode();entry=tarfile.TarInfo('cedar-shell/ARTIFACT-CONTENTS.json');entry.size=len(data);entry.mode=0o644;tar.addfile(entry,io.BytesIO(data))
    checksum=hashlib.sha256(destination.read_bytes()).hexdigest();destination.with_suffix(destination.suffix+'.sha256').write_text(checksum+'  '+destination.name+'\n')
    print('Private development candidate: '+destination.name+'; '+str(len(entries))+' files; SHA-256 '+checksum)
    return inventory

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('output',type=Path);p.add_argument('--source',type=Path,default=ROOT);a=p.parse_args();package(a.source.resolve(),a.output.resolve())
