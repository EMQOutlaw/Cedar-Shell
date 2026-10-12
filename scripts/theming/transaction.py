"""Journaled, crash-recoverable user-file and GSettings changes."""
import base64
import contextlib
import fcntl
import hashlib
import json
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import time
import uuid

class Conflict(RuntimeError): pass

def digest(data):return hashlib.sha256(data).hexdigest()
def encode(data):return base64.b64encode(data).decode() if data is not None else None
def decode(data):return base64.b64decode(data,validate=True) if data is not None else None

def run(args):
    p=subprocess.run(args,capture_output=True,text=True,timeout=8)
    if p.returncode:raise RuntimeError(p.stderr.strip() or 'Command failed: '+args[0])
    return p.stdout.strip()

class Store:
    def __init__(self, home=None, config=None, data=None, state=None):
        self.home=Path(home or Path.home()).absolute()
        self.config=Path(config or os.environ.get('XDG_CONFIG_HOME',self.home/'.config')).absolute()
        self.data=Path(data or os.environ.get('XDG_DATA_HOME',self.home/'.local/share')).absolute()
        self.state=Path(state or os.environ.get('XDG_STATE_HOME',self.home/'.local/state')).absolute()/'cedar/theming'
        self.roots=(self.config,self.data,self.state,self.home/'.var/app',self.home)
    def check(self,path,write=False):
        path=Path(path).absolute()
        if any(ord(c)<32 for c in str(path)):raise Conflict('Control characters are not supported in configuration paths.')
        if '..' in path.parts or not any(path.is_relative_to(r) for r in self.roots):raise Conflict('Path is outside the user theme locations: '+str(path))
        for node in [path,*path.parents]:
            if node.is_symlink():raise Conflict('Symlink left untouched: '+str(node))
        if path.exists():
            st=path.stat()
            if not stat.S_ISREG(st.st_mode):raise Conflict('Not a regular file: '+str(path))
            if st.st_uid!=os.getuid():raise Conflict('Not owned by this user: '+str(path))
            if st.st_size>4*1024*1024:raise Conflict('Configuration exceeds 4 MiB: '+str(path))
            if write and not st.st_mode & 0o222:raise Conflict('Read-only file: '+str(path))
        if write:
            parent=path.parent
            while not parent.exists():parent=parent.parent
            if not parent.stat().st_mode & 0o222:raise Conflict('Read-only directory: '+str(parent))
        return path
    def snapshot(self,path):
        path=self.check(path)
        return {'data':encode(path.read_bytes()),'mode':stat.S_IMODE(path.stat().st_mode)} if path.exists() else {'data':None,'mode':0o600}
    def write(self,path,data,mode=0o600):
        path=self.check(path,True)
        path.parent.mkdir(parents=True,exist_ok=True,mode=0o700)
        if data is None:
            if path.exists():path.unlink()
        else:
            fd,tmp=tempfile.mkstemp(prefix='.'+path.name+'.cedar-',dir=path.parent)
            try:
                with os.fdopen(fd,'wb') as f:
                    os.fchmod(f.fileno(),mode);f.write(data);f.flush();os.fsync(f.fileno())
                self.check(path,True);os.replace(tmp,path)
            finally:
                if os.path.exists(tmp):os.unlink(tmp)
        fd=os.open(path.parent,os.O_RDONLY|os.O_DIRECTORY)
        try:os.fsync(fd)
        finally:os.close(fd)
    def json(self,path,default):
        self.check(path)
        return json.loads(path.read_text()) if path.exists() else default
    def save(self,path,value):self.write(path,(json.dumps(value,indent=2)+'\n').encode())
    @contextlib.contextmanager
    def lock(self):
        target=self.state/'engine.lock';self.check(target,True);target.parent.mkdir(parents=True,exist_ok=True,mode=0o700)
        with target.open('a') as f:
            fcntl.flock(f,fcntl.LOCK_EX)
            yield
    def read_op(self,op):
        if op['kind']=='file':return self.snapshot(op['path'])
        return {'data':run(['dconf','read',op['path']]),'mode':0}
    def write_op(self,op,snapshot):
        if op['kind']=='file':self.write(op['path'],decode(snapshot['data']),snapshot['mode'])
        elif snapshot['data']:run(['dconf','write',op['path'],snapshot['data']])
        else:run(['dconf','reset',op['path']])
    def recover(self):
        journal=self.json(self.state/'pending.json',None)
        if not journal:return
        # Roll back only values this transaction could have written; never erase later edits.
        for op in journal['operations']:
            current=self.read_op(op)
            if current not in (op['before'],op['after']):raise Conflict('Interrupted transaction conflicts with a later edit: '+op['path'])
        for op in reversed(journal['operations']):
            if self.read_op(op)!=op['before']:self.write_op(op,op['before'])
        self.save(self.state/'ownership.json',journal['ownersBefore'])
        last=self.json(self.state/'last.json',{})
        if last.get('id')==journal['id']:
            if journal.get('lastBefore'):self.save(self.state/'last.json',journal['lastBefore'])
            else:self.write(self.state/'last.json',None)
        self.write(self.state/'pending.json',None)
    def apply(self,operations):
        with self.lock():
            self.recover()
            owners=self.json(self.state/'ownership.json',{})
            changed=[]
            for op in operations:
                current=self.read_op(op)
                if current!=op['before']:raise Conflict('Configuration changed after preview: '+op['path'])
                old=owners.get(op['kind']+':'+op['path'])
                if old and current!=old['after']:raise Conflict('User edit preserved; CEDAR ownership conflicts: '+op['path'])
                if current!=op['after']:
                    if op['kind']=='file':self.check(op['path'],True)
                    changed.append(op)
            if not changed:return {'changed':0,'transaction':None}
            journal={'id':uuid.uuid4().hex,'created':time.time(),'operations':changed,'ownersBefore':owners,'lastBefore':self.json(self.state/'last.json',None)}
            self.save(self.state/'pending.json',journal)
            try:
                for op in changed:
                    if self.read_op(op)!=op['before']:raise Conflict('Configuration changed during apply: '+op['path'])
                    self.write_op(op,op['after'])
                    if self.read_op(op)!=op['after']:raise Conflict('Write verification failed: '+op['path'])
                next_owners=dict(owners)
                for op in changed:
                    key=op['kind']+':'+op['path']
                    next_owners[key]={'before':owners.get(key,op)['before'],'after':op['after'],'app':op['app'],'kind':op['kind'],'path':op['path']}
                self.save(self.state/'ownership.json',next_owners)
                self.save(self.state/'history'/ (journal['id']+'.json'),journal)
                self.save(self.state/'last.json',journal)
                self.write(self.state/'pending.json',None)
            except BaseException:
                self.recover();raise
            return {'changed':len(changed),'transaction':journal['id']}
    def restore(self,reset=False):
        with self.lock():
            self.recover()
            owners=self.json(self.state/'ownership.json',{})
            last=self.json(self.state/'last.json',None)
            if not reset and not last:return {'changed':0}
            ops=list(owners.values()) if reset else last['operations']
            for op in ops:
                if self.read_op(op)!=op['after']:raise Conflict('Later user edit preserved: '+op['path'])
            inverse=[dict(op,before=op['after'],after=op['before']) for op in ops]
            journal={'id':uuid.uuid4().hex,'created':time.time(),'operations':inverse,'ownersBefore':owners,'lastBefore':self.json(self.state/'last.json',None)}
            self.save(self.state/'pending.json',journal)
            try:
                for op in reversed(inverse):self.write_op(op,op['after'])
                self.save(self.state/'ownership.json',{} if reset else last['ownersBefore'])
                self.write(self.state/'last.json',None)
                self.write(self.state/'pending.json',None)
            except BaseException:
                self.recover();raise
            return {'changed':len(ops)}

def file_op(store,path,text,app):
    before=store.snapshot(path)
    return {'kind':'file','path':str(path),'before':before,'after':{'data':encode(text.encode()),'mode':before['mode']},'app':app}
