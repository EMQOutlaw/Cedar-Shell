#!/usr/bin/env python3
"""Explicit Core actions. Paths remain argv/data, never shell programs."""
import json,mimetypes,os,signal,stat,subprocess,sys
from pathlib import Path
from urllib.parse import unquote,urlparse
from core_probe import recording
from desktop_runtime import omarchy

RECORDING_FILE=Path('/tmp/omarchy-screenrecord-filename')

def local_file(value):
    if not isinstance(value,str) or '\x00' in value:raise ValueError('Invalid file path.')
    if value.startswith('file:'):
        uri=urlparse(value)
        if uri.netloc not in ('','localhost'):raise ValueError('Only local files can be used here.')
        value=unquote(uri.path)
    elif '://' in value:raise ValueError('Only local files can be used here.')
    path=Path(value).expanduser().resolve(strict=True)
    info=path.stat()
    if not stat.S_ISREG(info.st_mode) or info.st_uid!=os.getuid():raise ValueError('Choose a regular file owned by your user.')
    if not (path.is_relative_to(Path.home()) or path.is_relative_to(Path('/tmp'))):raise ValueError('Choose a file in your home or temporary folder.')
    return path

def run(args,timeout=15,stdin=None):
    p=subprocess.run(args,input=stdin,capture_output=True,timeout=timeout)
    if p.returncode:raise RuntimeError(p.stderr.decode(errors='replace').strip() or 'The action did not complete.')
    return p.stdout.decode(errors='replace').strip()

def action(req):
    name=req.get('action')
    if name=='check-updates':
        p=subprocess.run(['checkupdates','--nocolor'],capture_output=True,text=True,timeout=90)
        if p.returncode not in (0,2):raise RuntimeError(p.stderr.strip() or 'Package check failed.')
        packages=[line for line in p.stdout.splitlines() if line.strip()]
        return {'action':name,'packages':packages[:500],'count':len(packages),'message':'Repository package check complete. AUR and security classifications are not included.'}
    if name=='stop-recording':
        current=recording()
        selected=next((r for r in current if r['pid']==req.get('pid') and r['startTicks']==req.get('startTicks')),None)
        if selected is None:raise ValueError('That recorder has already stopped.')
        try:
            info=RECORDING_FILE.lstat()
            owned=stat.S_ISREG(info.st_mode) and info.st_uid==os.getuid() and RECORDING_FILE.read_text().strip()==selected.get('file','')
        except OSError:owned=False
        if omarchy() and len(current)==1 and owned:
            # Preserve Omarchy's webcam cleanup and postprocessing for its sole
            # recorder. This helper stops every recorder, so never use it when
            # another independently started recording is present.
            run(['omarchy','capture','screenrecording','--stop-recording'],timeout=120)
            return {'action':name,'message':'Stop request finished. The recording service reports the file result separately.'}
        # Pin the selected process before rechecking its start time. PID reuse
        # must never turn Stop into a signal to an unrelated process.
        fd=os.pidfd_open(selected['pid'])
        try:
            if not any(r['pid']==selected['pid'] and r['startTicks']==selected['startTicks'] for r in recording()):raise ValueError('That recorder has already stopped.')
            signal.pidfd_send_signal(fd,signal.SIGINT)
        finally:os.close(fd)
        return {'action':name,'message':'Stop requested for this recorder. Wait for it to finish saving; no file result has been assumed.'}
    path=local_file(req.get('path',''))
    if name=='inspect-file':return {'action':name,'path':str(path),'name':path.name,'mime':mimetypes.guess_type(path)[0] or 'application/octet-stream'}
    if name=='open-file':subprocess.Popen(['xdg-open',str(path)],stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,start_new_session=True)
    elif name=='reveal-file':subprocess.Popen(['xdg-open',str(path.parent)],stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,start_new_session=True)
    elif name=='copy-path':run(['wl-copy','--',str(path)])
    elif name=='copy-image':
        if path.stat().st_size>40*1024*1024:raise ValueError('Image is too large to copy from Core.')
        image=path.read_bytes()
        if not image.startswith(b'\x89PNG\r\n\x1a\n'):raise ValueError('Only PNG screenshots can be copied as images.')
        run(['wl-copy','--type','image/png'],stdin=image)
    elif name=='share-file':
        if not omarchy(): raise RuntimeError('No file-sharing provider configured. Use Open or Copy Path to share with your chosen application.')
        subprocess.Popen(['omarchy','share','file',str(path)],stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,start_new_session=True)
    elif name=='trash-file':run(['gio','trash','--',str(path)])
    else:raise ValueError('Unknown Core action.')
    return {'action':name,'message':{'copy-path':'Path copied.','copy-image':'Image copied.','trash-file':'Moved to Trash.'}.get(name,'Opened.'),'path':str(path)}
if __name__=='__main__':
    try:print(json.dumps({'ok':True,'data':action(json.loads(sys.stdin.readline()))}))
    except Exception as e:print(json.dumps({'ok':False,'error':str(e)}))
