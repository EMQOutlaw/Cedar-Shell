"""Focused execution, ownership and interruption tests; no desktop takeover."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import selectors
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
import adoption_plan as plan
import distribution as d
import portable_session as session


class Plans(unittest.TestCase):
    def snapshot(self):
        return {'adapter':'hyprland','root':'/fixture/release','candidateFingerprint':'hash',
                'locker':'hyprlock','background':'external','paused':[{'pid':42,'start':'100','exe':'/usr/bin/waybar','argv':['waybar']}]}
    def test_pure_deterministic_plan_and_changed_evidence(self):
        snapshot=self.snapshot();before=copy.deepcopy(snapshot)
        result=plan.build_plan(snapshot,{'launcher':True,'trailwatch':False})
        self.assertEqual(snapshot,before)
        self.assertEqual(result,plan.build_plan(snapshot,{'launcher':True,'trailwatch':False}))
        self.assertEqual(result['mode'],'Adopted Hybrid')
        for field,value in [('start','101'),('exe','/changed/waybar'),('argv',['waybar','-c','other'])]:
            changed=copy.deepcopy(snapshot);changed['paused'][0][field]=value
            with self.assertRaises(ValueError):plan.require_unchanged(result,changed,result['selections'])
        changed=copy.deepcopy(snapshot);changed['candidateFingerprint']='other release'
        with self.assertRaises(ValueError):plan.require_unchanged(result,changed,result['selections'])
        with self.assertRaises(ValueError):plan.require_unchanged(result,snapshot,{'launcher':False})
    def test_acknowledgment_is_required_before_any_mutation(self):
        for ack in (None,'stale'):
            with patch.object(session,'unlocked'),patch.object(session,'transaction') as transaction:
                with self.assertRaisesRegex(d.Refused,'acknowledged'):
                    session.prepare({'generation':'current','supervisorReady':ack})
                transaction.assert_not_called()
    def test_runtime_generation_is_verified(self):
        row={'generation':'new','locker':'hyprlock'}
        with patch.object(session,'cedar_rows',return_value=[{'pid':42}]),patch.object(session,'ipc',return_value=json.dumps({'generation':'old','stage':3,'screenCount':1})):
            with self.assertRaisesRegex(d.Refused,'generation'):session.healthy(row)


class Recovery(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(prefix='cedar recovery 雨 ');self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name)
        self.addCleanup(patch.stopall)
        patch.dict(os.environ,{'HOME':str(self.root),'XDG_STATE_HOME':str(self.root/'state')}).start()
    def test_existing_public_directory_is_not_silently_chmodded(self):
        folder=d.paths()['state'];folder.mkdir(parents=True,mode=0o755)
        with self.assertRaises(d.Refused):d.Transaction('test')
        self.assertEqual(folder.stat().st_mode&0o777,0o755)
    def test_crash_after_replace_reconciles_and_restores_exact_file(self):
        original=self.root/'ordinary file';original.write_bytes(b'original');original.chmod(0o640)
        before=d.info(original);tx=d.Transaction('test');entry=tx.backup(original)
        with patch.object(tx,'verify_entry',side_effect=OSError('interruption')):
            with self.assertRaises(OSError):tx.apply_file(entry,b'new',0o600)
        self.assertEqual(d.read_json(tx.path)['files'][0]['state'],'applying')
        d.restore_journal(tx.path);self.assertTrue(d.same(d.info(original),before))
        d.restore_journal(tx.path);self.assertTrue(d.same(d.info(original),before))
    def test_later_edit_during_uncertain_outcome_is_preserved(self):
        target=self.root/'target';target.write_bytes(b'before');tx=d.Transaction('test');entry=tx.backup(target)
        with patch.object(tx,'verify_entry',side_effect=OSError('interruption')):
            with self.assertRaises(OSError):tx.apply_file(entry,b'new')
        target.write_bytes(b'later user edit')
        with self.assertRaises(d.Refused):d.restore_journal(tx.path)
        self.assertEqual(target.read_bytes(),b'later user edit')

    def test_commit_requires_verified_operations(self):
        tx=d.Transaction('test')
        tx.record['plan']={'operations':[{'id':'fixture','kind':'start-cedar','state':'planned'}]}
        tx.record['operations']=[{'id':'fixture','kind':'start-cedar','state':'applying'}]
        with self.assertRaisesRegex(d.Refused,'not verified'):tx.commit()
        tx.record['operations'][0]['state']='verified';tx.commit()
        result=d.read_json(tx.path)
        self.assertEqual(result['operations'][0]['state'],'committed')
        self.assertEqual(result['plan']['operations'][0]['state'],'planned')


@unittest.skipUnless(importlib.util.find_spec('gi'), 'GIO Python bindings unavailable; application execution is not tested')
class ApplicationExecution(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(prefix='cedar applications 雨 ');self.addCleanup(self.tmp.cleanup)
        self.home=Path(self.tmp.name);self.apps=self.home/'data/applications';self.apps.mkdir(parents=True)
        self.env={**os.environ,'HOME':str(self.home),'XDG_CONFIG_HOME':str(self.home/'config'),'XDG_DATA_HOME':str(self.home/'data'),'XDG_STATE_HOME':str(self.home/'state'),'XDG_DATA_DIRS':str(self.home/'empty')}
        self.helper=d.ROOT/'scripts/default_apps.py'
    def request(self,value):
        result=subprocess.run([sys.executable,str(self.helper)],input=json.dumps(value),text=True,capture_output=True,env=self.env,timeout=10)
        return json.loads(result.stdout)

    def test_missing_cli_target_returns_failure(self):
        result=subprocess.run([sys.executable,str(self.helper),'--launch','missing-fixture.desktop'],capture_output=True,text=True,env=self.env,timeout=10)
        self.assertNotEqual(result.returncode,0)
        self.assertIn('no longer installed',result.stderr)
    def entry(self,name,exec_line,extra=''):
        (self.apps/name).write_text('[Desktop Entry]\nType=Application\nName=Fixture 雨\nExec='+exec_line+'\n'+extra)
    def test_real_gio_launch_preserves_unicode_arguments_and_working_directory(self):
        recorder=self.home/'record.py';result=self.home/'arguments.json';working=self.home/'work';working.mkdir()
        recorder.write_text('import json,os,sys\nfrom pathlib import Path\nPath(sys.argv[1]).write_text(json.dumps({"argv":sys.argv[2:],"cwd":os.getcwd()}))\n')
        def quote(value):return '"'+str(value).replace('\\','\\\\').replace('"','\\"')+'"'
        self.entry('fixture.desktop',f'{sys.executable} {quote(recorder)} {quote(result)} %F',f'Path={working}\n')
        files=[str(self.home/'file with spaces 雨.txt'),str(self.home/'$(touch not-executed).txt')]
        subprocess.run([sys.executable,str(self.helper),'--launch','fixture.desktop',*files],env=self.env,check=True,capture_output=True,timeout=10)
        deadline=time.monotonic()+5
        while not result.exists() and time.monotonic()<deadline:time.sleep(.02)
        self.assertEqual(json.loads(result.read_text()),{'argv':files,'cwd':str(working)})
    def test_removed_app_and_bad_id_are_not_executed(self):
        for app in ('missing.desktop','../injected.desktop'):
            self.assertFalse(self.request({'action':'launch','id':app})['ok'])
    def test_noop_defaults_do_not_write_or_backup(self):
        self.entry('fixture.desktop','/usr/bin/true %F','MimeType=text/plain;\n')
        first=self.request({'action':'apply','role':'editor','app':'fixture.desktop'});self.assertTrue(first['ok'],first)
        paths=list((self.home/'state').rglob('*'))+list((self.home/'config').rglob('*'))
        before={str(p):(p.read_bytes(),p.stat().st_mtime_ns) for p in paths if p.is_file()}
        second=self.request({'action':'apply','role':'editor','app':'fixture.desktop'})
        self.assertEqual(second['data']['status'],'unchanged')
        paths=list((self.home/'state').rglob('*'))+list((self.home/'config').rglob('*'))
        self.assertEqual(before,{str(p):(p.read_bytes(),p.stat().st_mtime_ns) for p in paths if p.is_file()})
    def test_live_catalog_coalesces_hidden_changes_and_rearms(self):
        self.entry('first.desktop','/usr/bin/true')
        child=subprocess.Popen([sys.executable,str(self.helper),'--watch'],env=self.env,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        self.addCleanup(lambda: child.poll() is None and child.kill())
        selector=selectors.DefaultSelector();selector.register(child.stdout,selectors.EVENT_READ);self.addCleanup(selector.close)
        def send(value):child.stdin.write((json.dumps(value)+'\n').encode());child.stdin.flush()
        def receive():
            self.assertTrue(selector.select(5),'Catalog did not publish a local revision')
            return json.loads(child.stdout.readline())
        send({'action':'visible','value':True});first=receive()
        self.assertIn('first.desktop',[a['id'] for a in first['data']['apps']])
        send({'action':'visible','value':False});time.sleep(.15)
        self.entry('second.desktop','/usr/bin/true');time.sleep(.3)
        self.assertFalse(selector.select(.2),'Hidden catalog should not rescan/publish')
        send({'action':'visible','value':True});second=receive()
        self.assertEqual(first['generation'],second['generation']);self.assertGreater(second['sequence'],first['sequence'])
        self.assertIn('second.desktop',[a['id'] for a in second['data']['apps']])
        (self.apps/'first.desktop').unlink();third=receive()
        self.assertNotIn('first.desktop',[a['id'] for a in third['data']['apps']])
        child.stdin.close();child.wait(timeout=5);child.stdout.close();child.stderr.close()


class StartupDiscovery(unittest.TestCase):
    def test_include_graph_is_bounded_and_never_executes(self):
        import startup_graph
        with tempfile.TemporaryDirectory(prefix='cedar includes 雨 ') as tmp:
            root=Path(tmp);main=root/'hyprland.conf';child=root/'child with spaces.conf'
            marker=root/'must-not-exist'
            main.write_text('$part = '+str(child)+'\nsource = $part\nexec-once = touch '+str(marker)+'\n')
            child.write_text('source = '+str(main)+'\n')
            report=startup_graph.inspect(main,root,root)
            self.assertIn('Include cycle',report['unresolved']);self.assertFalse(marker.exists())
            child.write_text('source = $unresolved\n')
            self.assertFalse(startup_graph.inspect(main,root,root)['complete'])
            self.assertFalse(startup_graph.inspect(main,root,root,max_files=1)['complete'])
            child.write_text('monitor = ,preferred,auto,1\n')
            self.assertTrue(startup_graph.inspect(main,root,root)['complete'])
    def test_dynamic_lua_requires_review(self):
        import startup_graph
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);main=root/'hyprland.lua';main.write_text('dofile(os.getenv("HOME") .. "/other.lua")\n')
            self.assertFalse(startup_graph.inspect(main,root,root)['complete'])
    def test_managed_adapter_preserves_files_and_filters_private_state(self):
        import managed_adapters
        with tempfile.TemporaryDirectory() as tmp,patch.dict(os.environ,{'XDG_STATE_HOME':tmp,'XDG_CONFIG_HOME':tmp}):
            state=Path(tmp)/'caelestia/dots-state.json';state.parent.mkdir()
            state.write_text(json.dumps({'enabled_components':['hypr','auth','synthetic-private-name'],'deployed_files':{'private/path':'source'}}))
            before=state.read_bytes();result=managed_adapters.inspect('caelestia','/fixture/caelestia/shell.qml',{'caelestia-shell':'fixture-version'})
            self.assertEqual(before,state.read_bytes());self.assertEqual(result['managedFiles'],1)
            self.assertEqual(result['enabledComponents'],['auth','hypr']);self.assertFalse(result['takeoverCertified'])
            self.assertNotIn('synthetic-private-name',json.dumps(result));self.assertNotIn('private/path',json.dumps(result))
    def test_other_session_never_authorizes_handoff(self):
        import portable_providers
        with patch.dict(os.environ,{'WAYLAND_DISPLAY':'wayland-fixture','HYPRLAND_INSTANCE_SIGNATURE':'session-current'}):
            for env in ({},{'HYPRLAND_INSTANCE_SIGNATURE':'session-other'},{'WAYLAND_DISPLAY':'another-display'}):
                with self.assertRaises(d.Refused):portable_providers.require_session(env)
            portable_providers.require_session({'HYPRLAND_INSTANCE_SIGNATURE':'session-current'})


class Measurements(unittest.TestCase):
    def test_ticks_use_monotonic_delta_and_identity_not_cpu_snapshot(self):
        import measure_resources as measure
        previous={(42,1):{'ticks':200,'rss':4096,'pss':2048}}
        current={(42,1):{'ticks':250,'rss':8192,'pss':4096},(43,2):{'ticks':1,'rss':2048,'pss':1024}}
        result=measure.compare(previous,current,2,100)
        self.assertEqual(result['cpuOneCorePercent'],25)
        self.assertEqual(result['rssSumBytes'],10240);self.assertEqual(result['pssBytes'],5120)
        self.assertEqual(result['newIdentities'],1)
        current[(42,1)]['pss']=None;self.assertIsNone(measure.compare(previous,current,2,100)['pssBytes'])
