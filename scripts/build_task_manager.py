#!/usr/bin/env python3
"""Build the release-local C++20 Task Manager, without downloading dependencies."""
from pathlib import Path
import hashlib,json,os,shlex,shutil,subprocess,sys,tempfile
ROOT=Path(__file__).resolve().parents[1]
PACKAGES=['Qt6Core','Qt6Network','Qt6Gui','Qt6Qml','Qt6Quick','Qt6QuickControls2','Qt6DBus']
def build(root=ROOT, output=None):
    root=Path(root).resolve();output=Path(output or root/'.local/task-manager').resolve()
    sources=sorted((root/'native/taskmanager').glob('*'))+sorted((root/'taskmanager').glob('*'))+[root/'components/core/Kinetic.js',root/'components/core/StrataGeometry.js']+[root/'scripts/build_task_manager.py']
    sources=[p for p in sources if p.is_file()]
    build_id=hashlib.sha256(b''.join(p.name.encode()+p.read_bytes() for p in sources)).hexdigest()[:16]
    tools={k:shutil.which(k) for k in ('g++','pkg-config')}
    if not all(tools.values()):raise RuntimeError('Task Manager needs g++ and pkg-config (Arch: gcc, pkgconf).')
    flags=shlex.split(subprocess.check_output(['pkg-config','--cflags','--libs',*PACKAGES],text=True))
    backend_flags=shlex.split(subprocess.check_output(['pkg-config','--cflags','--libs','Qt6Core','Qt6Network'],text=True))
    moc=Path(subprocess.check_output(['pkg-config','--variable=libexecdir','Qt6Core'],text=True).strip())/'moc'
    if not moc.exists():raise RuntimeError('Qt development tools missing (Arch: qt6-base, qt6-declarative).')
    output.mkdir(parents=True,exist_ok=True)
    fingerprint=build_id+'\n'+subprocess.check_output(['g++','-dumpfullversion'],text=True)+subprocess.check_output(['pkg-config','--modversion',*PACKAGES],text=True)
    stamp=output/'build.json'
    previous={}
    try: previous=json.loads(stamp.read_text())
    except (OSError,ValueError): pass
    names=('cedar-taskd','cedar-task-manager')
    if previous.get('fingerprint')==fingerprint and all((output/n).is_file() and hashlib.sha256((output/n).read_bytes()).hexdigest()==previous.get('binaries',{}).get(n) for n in names):return output
    with tempfile.TemporaryDirectory(prefix='cedar-task-build-',dir=output) as temp:
        temp=Path(temp);native=root/'native/taskmanager'
        common=['g++','-std=c++20','-O2','-g','-fPIC','-Wall','-Wextra','-Wpedantic','-Wno-misleading-indentation','-DQT_NO_KEYWORDS',f'-DCEDAR_BUILD_ID="{build_id}"','-I'+str(native)]
        for header in ('frontend.h',):subprocess.run([str(moc),'-DQT_NO_KEYWORDS',str(native/header),'-o',str(temp/('moc_'+header+'.cpp'))],check=True)
        objects={}
        units={'collector':'collector.cpp','backend':'backend.cpp','frontend':'frontend.cpp','moc':str(temp/'moc_frontend.h.cpp')}
        for name,unit in units.items():
            objects[name]=str(temp/(name+'.o'))
            source=str(native/unit) if not unit.startswith('/') else unit
            subprocess.run([*common,'-c',source,*flags,'-o',objects[name]],check=True)
        for target,names_ in {'cedar-taskd':['collector','backend'],'cedar-task-manager':['collector','frontend','moc']}.items():
            link_flags=backend_flags if target=='cedar-taskd' else flags
            subprocess.run(['g++',*[objects[n] for n in names_],*link_flags,'-o',str(temp/target)],check=True)
        for name in ('cedar-taskd','cedar-task-manager'):os.replace(temp/name,output/name)
        stamp.write_text(json.dumps({'build':build_id,'fingerprint':fingerprint,'binaries':{n:hashlib.sha256((output/n).read_bytes()).hexdigest() for n in names}})+'\n')
    return output
if __name__=='__main__':
    print(build(output=sys.argv[1] if len(sys.argv)>1 else None))
