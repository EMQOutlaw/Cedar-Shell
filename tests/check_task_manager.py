#!/usr/bin/env python3
"""Real native backend, secured IPC, disposable process actions and standalone QML."""
from pathlib import Path
import json,os,signal,socket,subprocess,sys,tempfile,time,shlex,re,ctypes
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
import build_task_manager
from unittest.mock import patch
import contextlib,io
import distribution as distribution

def main():
    binaries=build_task_manager.build()
    with tempfile.TemporaryDirectory(prefix='cedar-task-check-') as tmp:
        base=Path(tmp);runtime=base/'runtime';runtime.mkdir(mode=0o700)
        env={**os.environ,'XDG_RUNTIME_DIR':str(runtime),'XDG_CONFIG_HOME':str(base/'config'),'XDG_STATE_HOME':str(base/'state'),'QT_FORCE_STDERR_LOGGING':'1','QT_QPA_PLATFORM':'offscreen','QT_QUICK_BACKEND':'software','QT_QUICK_CONTROLS_STYLE':'Basic','QT_QPA_PLATFORMTHEME':'basic','HYPRLAND_INSTANCE_SIGNATURE':''}
        flags=shlex.split(subprocess.check_output(['pkg-config','--cflags','--libs','Qt6Core','Qt6Network'],text=True))
        subprocess.run(['g++','-std=c++20','-O1','-fPIC','-DQT_NO_KEYWORDS',str(ROOT/'native/taskmanager/collector.cpp'),str(ROOT/'native/taskmanager/collector_tests.cpp'),*flags,'-o',str(base/'unit')],check=True,capture_output=True)
        result=subprocess.run([str(base/'unit')],env=env,capture_output=True,text=True);assert result.returncode==0,result.stdout+result.stderr;print(result.stdout.strip())
        build=json.loads((binaries/'build.json').read_text())['build'];path=runtime/'cedar'/f'taskd-{build}.sock'
        probe,other=socket.socketpair()
        try:
            probe.getsockopt(socket.SOL_SOCKET,socket.SO_PEERCRED,12);peer_blocked=False
        except PermissionError:
            peer_blocked=True
            assert not os.environ.get("CEDAR_TASK_REQUIRE_IPC"),"CI must exercise real sockets"
            print('SKIP: socket integration and duplicate-focus tests: sandbox denies SO_PEERCRED; production authentication remains mandatory')
            env['CEDAR_TASK_TEST_LOCAL_COLLECTOR']='1'
        finally:probe.close();other.close()
        if not peer_blocked:
            daemon=subprocess.Popen([str(binaries/'cedar-taskd')],env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
            children=[];connections=[]
            try:
                for _ in range(100):
                    if path.exists():break
                    if daemon.poll() is not None:raise AssertionError('Backend failed: '+daemon.stderr.read())
                    time.sleep(.03)
                assert path.exists(),'Socket creation'
                assert path.stat().st_mode&0o077==0,'Socket permissions'
                assert path.parent.stat().st_mode&0o077==0,'Directory permissions'
                if os.environ.get('CEDAR_TASK_REQUIRE_IPC'):
                    # CI-only root test client can traverse private paths but must fail peer authentication.
                    code="import socket,sys; s=socket.socket(socket.AF_UNIX); s.settimeout(3); s.connect(sys.argv[1]); assert s.recv(1)==b''"
                    foreign=subprocess.run(['sudo','-n',sys.executable,'-c',code,str(path)],capture_output=True,text=True,timeout=6)
                    assert foreign.returncode==0,foreign.stdout+foreign.stderr
                    print('PASS: different-UID IPC client rejected despite filesystem access')
                def connect(hello=True):
                    s=socket.socket(socket.AF_UNIX);s.settimeout(7);s.connect(str(path));connections.append(s);f=s.makefile('rwb',buffering=0);connections.append(f)
                    if hello:
                        f.write((json.dumps({'protocol':1,'type':'hello','build':build})+'\n').encode());assert json.loads(f.readline())['type']=='hello'
                    return f
                def send(f,obj):f.write((json.dumps({'protocol':1,**obj})+'\n').encode())
                def response(f,type_,id_=None):
                    for _ in range(40):
                        line=f.readline();assert line,'Unexpected disconnect';row=json.loads(line)
                        if row['type']==type_ and (id_ is None or row.get('id')==id_):return row
                    raise AssertionError('Expected reply '+type_)
                f=connect();snapshot=response(f,'snapshot');assert snapshot['cpu']['percent'] is None
                snapshot=response(f,'snapshot');assert isinstance(snapshot['cpu']['percent'],(int,float));assert snapshot['memory']['total']>0
                rows=response(f,'processes')['rows'];assert any(p['pid']==os.getpid() for p in rows),'Real processes'
                for raw in (b'not json\n',b'x'*8193+b'\n',b'{"protocol":999,"type":"hello"}\n',b'{"protocol":1,"type":"shell","command":"false"}\n'):
                    invalid=connect(False);invalid.write(raw);assert json.loads(invalid.readline())['type']=='error';invalid.close()
                mismatch=connect(False);send(mismatch,{'type':'hello','build':'wrong'});assert json.loads(mismatch.readline())['type']=='error';mismatch.close()
                flood=connect();flood.write(b''.join((json.dumps({'protocol':1,'type':'visibility','visible':True})+'\n').encode() for _ in range(25)));assert response(flood,'error')['message']=='Request rate exceeded';flood.close()
                def start():
                    p=subprocess.Popen(['sleep','120'],preexec_fn=lambda:ctypes.CDLL(None).prctl(0x59616d61,ctypes.c_ulong(-1),0,0,0));children.append(p)
                    pid=p.pid
                    for _ in range(30):
                        stat=(Path('/proc')/str(pid)/'stat').read_text();fields=stat[stat.rfind(')')+2:].split()
                        if fields[0]!='R':break
                        time.sleep(.01)
                    return p,fields[19]
                seq=0
                def action(pid,start,op,**more):
                    nonlocal seq;seq+=1;id_=str(seq);send(f,{'type':'action','id':id_,'pid':pid,'start':start,'action':op,**more});return response(f,'action-result',id_)
                p,startTime=start();assert action(p.pid,str(int(startTime)+1),'kill',confirmed=True)['code']=='identity';assert p.poll() is None
                assert action(p.pid,startTime,'kill')['code']=='confirmation';assert p.poll() is None
                assert action(p.pid,startTime,'stop')['ok'];time.sleep(.05);assert ') T ' in Path(f'/proc/{p.pid}/stat').read_text()
                assert action(p.pid,startTime,'continue')['ok'];time.sleep(.05);assert ') T ' not in Path(f'/proc/{p.pid}/stat').read_text()
                assert action(p.pid,startTime,'nice',nice=10)['ok'];assert os.getpriority(os.PRIO_PROCESS,p.pid)==10
                denied=action(p.pid,startTime,'nice',nice=-20);assert not denied['ok'] and denied['code']=='denied',denied
                assert action(p.pid,startTime,'nice',nice=30)['code']=='invalid'
                assert action(p.pid,startTime,'term')['ok'];p.wait(timeout=3);assert action(p.pid,startTime,'term')['code']=='exited'
                p,startTime=start();assert action(p.pid,startTime,'kill',confirmed=True)['ok'];assert p.wait(timeout=3)==-signal.SIGKILL
                current=next(row for row in rows if row['pid']==os.getpid());assert action(os.getpid(),current['start'],'stop')['code']=='protected'
                send(f,{'type':'visibility','visible':False});slow=response(f,'snapshot');assert slow['sampleIntervalMs']==5000
                print('PASS: real telemetry, version/size/rate guards, SIGTERM/SIGKILL/SIGSTOP/SIGCONT, priority, identity and critical-process restrictions')
            finally:
                for connection in connections:
                    try:connection.close()
                    except OSError:pass
                for p in children:
                    if p.poll() is None:p.kill();p.wait()
                try:daemon.wait(timeout=8)
                except subprocess.TimeoutExpired:daemon.terminate();daemon.wait(timeout=3);raise AssertionError('Backend did not idle-exit')
            assert not path.exists(),'Socket cleanup'
        start=time.monotonic()
        gui=subprocess.Popen([str(binaries/'cedar-task-manager'),'--source',str(ROOT),'--self-test'],env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
        try:
            focus=runtime/'cedar/task-manager.sock'
            for _ in range(100):
                if focus.exists() or gui.poll() is not None:break
                time.sleep(.03)
            if not peer_blocked:
                second=subprocess.run([str(binaries/'cedar-task-manager'),'--source',str(ROOT)],env=env,capture_output=True,text=True,timeout=10);assert second.returncode==0,second.stderr
            output=gui.communicate(timeout=35)[0]
        finally:
            if gui.poll() is None:gui.kill();gui.wait()
        assert gui.returncode==0,output
        assert 'PASS: Standalone' in output,output
        assert not re.search(r'ReferenceError|TypeError|Binding loop|Cannot assign|Unable to assign|failed to load',output,re.I),output
        print(output.strip());print('Standalone test elapsed seconds:',round(time.monotonic()-start,2))
        assert not list((runtime/'cedar').glob('*.sock')),'Frontend/backend socket cleanup'
        # A second complete lifecycle also tests persisted shared accessibility settings.
        config=base/'config/cedar';config.mkdir(parents=True,exist_ok=True)
        (config/'settings.json').write_text(json.dumps({'fontScale':1.5,'reducedMotion':True}))
        again=subprocess.run([str(binaries/'cedar-task-manager'),'--source',str(ROOT),'--self-test'],env=env,capture_output=True,text=True,timeout=35)
        assert again.returncode==0,again.stdout+again.stderr
        assert 'PASS: Standalone' in again.stdout+again.stderr
        assert not list((runtime/'cedar').glob('*.sock'))
        print('PASS: repeated lifecycle with 150% typography and Reduced Motion')
        if not peer_blocked:
            app=subprocess.Popen([str(binaries/'cedar-task-manager'),'--source',str(ROOT)],env=env,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
            try:
                time.sleep(4)
                children=Path(f'/proc/{app.pid}/task/{app.pid}/children').read_text().split()
                assert len(children)==1,'One dedicated backend'
                backend_pid=int(children[0])
                def usage(pid):
                    raw=Path(f'/proc/{pid}/stat').read_text()
                    fields=raw[raw.rfind(')')+2:].split()
                    return (int(fields[11])+int(fields[12]))/os.sysconf('SC_CLK_TCK'),int(fields[21])*os.sysconf('SC_PAGESIZE')/1048576
                before={pid:usage(pid) for pid in (app.pid,backend_pid)};started=time.monotonic()
                time.sleep(8);elapsed=time.monotonic()-started
                for label,pid in (('frontend',app.pid),('backend',backend_pid)):
                    cpu,rss=usage(pid)
                    print(f'MEASURED {label}: {(cpu-before[pid][0])/elapsed*100:.2f}% of one core, RSS {rss:.2f} MiB over {elapsed:.2f}s (software/offscreen CI)')
            finally:
                app.terminate();app.wait(timeout=5)
            assert not list((runtime/'cedar').glob('*.sock')),'Normal close releases sockets'
        # Install the actual built binaries under isolated XDG roots, then restore.
        install_env={**env,'HOME':str(base/'home'),'XDG_DATA_HOME':str(base/'data'),'XDG_CACHE_HOME':str(base/'cache')}
        with patch.dict(os.environ,install_env), patch.object(distribution,'prepare_task_manager',return_value=binaries), patch.object(distribution,'validate',return_value='Native binaries tested; shell QML tested separately.'), contextlib.redirect_stdout(io.StringIO()):
            distribution.install(ROOT,approved=True)
            installed=distribution.installed()
            manifest=json.loads((installed/'release-files.json').read_text())
            for name in ('cedar-task-manager','cedar-taskd'):
                assert 'libexec/'+name in manifest
                assert (installed/'libexec'/name).read_bytes()==(binaries/name).read_bytes()
            launcher=distribution.paths()['bin'].with_name('cedar-task-manager')
            assert launcher.is_file() and 'current/scripts/task_manager.py' in launcher.read_text()
            journal=next((distribution.paths()['state']/'transactions').glob('*/journal.json'))
            distribution.restore_journal(journal)
            assert not launcher.exists()
            assert not (base/'data/applications/cedar-task-manager.desktop').exists()
        print('PASS: real native release payload, managed launcher, desktop entry and journal rollback')
if __name__=='__main__':main()
