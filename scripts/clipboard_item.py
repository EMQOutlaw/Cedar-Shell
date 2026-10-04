#!/usr/bin/env python3
"""Optional session clipboard capture. Never log clipboard payloads."""
import base64,json,os,subprocess,sys

def capture():
    if os.environ.get('CLIPBOARD_STATE') in ('sensitive','clear','nil'): return
    types=subprocess.run(['wl-paste','--list-types'],capture_output=True,text=True,timeout=2)
    if 'x-kde-passwordManagerHint' in types.stdout: return
    data=sys.stdin.buffer.read(1048577)
    if not data or len(data)>1048576:return
    if data.startswith(b'\x89PNG\r\n\x1a\n'):
        item={'kind':'image','mime':'image/png','payload':base64.b64encode(data).decode(),'label':'Image'}
    else:
        if len(data)>32768:return
        try:text=data.decode('utf-8')
        except UnicodeError:return
        item={'kind':'text','mime':'text/plain;charset=utf-8','payload':text,'label':'Text'}
    print(json.dumps(item),flush=True)

def copy():
    req=json.loads(sys.stdin.readline())
    if req.get('kind')=='image':data=base64.b64decode(req['payload'],validate=True);mime='image/png'
    elif req.get('kind')=='text':data=req['payload'].encode();mime='text/plain;charset=utf-8'
    else:raise ValueError('Unsupported clipboard item')
    if len(data)>1048576:raise ValueError('Clipboard item too large')
    r=subprocess.run(['wl-copy','--type',mime],input=data,capture_output=True,timeout=4)
    if r.returncode:raise RuntimeError('Clipboard copy failed')
    return {}

if __name__=='__main__':
    if '--capture' in sys.argv:
        try:capture()
        except Exception:pass
    else:
        try:print(json.dumps({'ok':True,'data':copy()}))
        except Exception as e:print(json.dumps({'ok':False,'error':str(e)}))
