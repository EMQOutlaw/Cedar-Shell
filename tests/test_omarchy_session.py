"""Controlled fixtures: these do not certify real session lock or GPU behavior."""
import contextlib,copy,io,json,os,sys,tempfile,time,unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
import distribution as d
import omarchy_session as s

class OmarchySession(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='cedar session 雨 ');self.addCleanup(self.temp.cleanup);self.base=Path(self.temp.name)
        env={'HOME':str(self.base/'home'),**{'XDG_'+k+'_HOME':str(self.base/k.lower()) for k in ['CONFIG','DATA','STATE','CACHE']}}
        self.environment=patch.dict(os.environ,env);self.environment.start();self.addCleanup(self.environment.stop)
        wait=patch.object(s,'wait_for_trial');wait.start();self.addCleanup(wait.stop)
        api=patch.object(s,'verify_session_api');api.start();self.addCleanup(api.stop)
        self.config={'version':1,'bar':{'layout':{'left':[{'id':'example.widget'}]}},'idle':{'lock':420},'disabledPlugins':['omarchy.weather'],'custom':{'keep':'unchanged'}}
    def row(self,stage='trial'):
        return {'id':'fixture','stage':stage,'root':str(d.ROOT),'omarchyShell':'/example/shell.qml','login':False,'deadline':time.time()+120}
    def test_transform_preserves_settings(self):
        original=copy.deepcopy(self.config);out=s.transformed(self.config)
        self.assertEqual(self.config,original);self.assertEqual(out['idle'],original['idle']);self.assertEqual(out['custom'],original['custom'])
        self.assertEqual(out['bar']['layout'],original['bar']['layout']);self.assertEqual(out['bar']['id'],'cedar.integration')
        self.assertEqual(out['disabledPlugins'],['omarchy.weather',*s.DISABLE])
    def test_discovery_does_not_depend_on_default_qs_config(self):
        with patch.object(d,'command',return_value='[]') as command:
            self.assertEqual(s.instances(),[])
            command.assert_called_once_with(['qs','list','--all','-j'],timeout=5)
    def test_modified_upstream_api_refused(self):
        with self.assertRaises(d.Refused):s.verify_upstream(d.ROOT,self.base/'unknown-upstream')
    def test_protected_services_never_enabled_or_disabled(self):
        for name in s.PROTECTED:
            config=copy.deepcopy(self.config);config['disabledPlugins'].append(name)
            if name=='omarchy.lock':
                with self.assertRaisesRegex(d.Refused,'omarchy.lock'):s.transformed(config)
            else:
                original=copy.deepcopy(config)
                self.assertIn(name,s.transformed(config)['disabledPlugins'])
                self.assertEqual(config,original)
        self.assertFalse(set(s.DISABLE)&set(s.PROTECTED))
    def test_invalid_schema_refused(self):
        for value in [None,[],{'version':2,'bar':{}},{'version':1},{'version':1,'bar':{},'disabledPlugins':'oops'}]:
            with self.assertRaises(d.Refused):s.transformed(value)
    def test_native_lock_requires_explicit_fields(self):
        row=self.row();state={'passwordPam':True,'locked':False,'requested':False,'secure':False}
        with patch.object(d,'command',return_value=json.dumps([{'solitaryBlockedBy':[]}])) ,patch.object(s,'ipc',return_value=json.dumps(state)):
            self.assertFalse(s.lock_state(row))
        with patch.object(d,'command',return_value='[{}]'):
            with self.assertRaises(d.Refused):s.lock_state(row)
        with patch.object(d,'command',return_value='[{"solitaryBlockedBy":["LOCK"]}]'),patch.object(s,'ipc',return_value=json.dumps(state)):
            self.assertTrue(s.lock_state(row))
        with patch.object(d,'command',return_value='[{"solitaryBlockedBy":["WORKSPACE"]}]'),patch.object(s,'ipc',return_value=json.dumps(state)):
            with self.assertRaises(d.Refused):s.lock_state(row)
    def test_missing_authentication_never_unlocked(self):
        with patch.object(d,'command',return_value='[{"solitaryBlockedBy":[]}]'),patch.object(s,'ipc',return_value='{}'):
            with self.assertRaises(d.Refused):s.lock_state(self.row())
    def test_timeout_restores(self):
        row=self.row();row['deadline']=0;s.save(row)
        with patch.object(s,'lock_state',return_value=False),patch.object(s,'healthy'),patch.object(s,'restore') as restore:
            s.supervise('fixture');restore.assert_called_once()
    def test_crash_restores(self):
        s.save(self.row())
        with patch.object(s,'lock_state',return_value=False),patch.object(s,'healthy',side_effect=d.Refused('process ended')),patch.object(s,'restore') as restore:
            s.supervise('fixture');restore.assert_called_once()
    def test_locked_timeout_defers_until_unlocked(self):
        row=self.row();row['deadline']=0;s.save(row)
        events=[]
        def lock():events.append('probe');return len(events)==1
        with patch.object(s,'lock_state',side_effect=lambda row:lock()),patch.object(s,'healthy'),patch.object(s,'restore',side_effect=lambda row:events.append('restored')),patch.object(s.time,'sleep'):
            s.supervise('fixture')
        self.assertEqual(events,['probe','probe','restored'])
    def test_unknown_lock_defers(self):
        row=self.row();row['deadline']=0;s.save(row)
        with patch.object(s,'lock_state',side_effect=[d.Refused('unknown'),False]),patch.object(s,'healthy'),patch.object(s,'restore') as restore,patch.object(s.time,'sleep'):
            s.supervise('fixture');restore.assert_called_once()
    def test_expired_trial_cannot_be_kept(self):
        row=self.row();row['deadline']=0;s.save(row)
        with patch.object(s,'unlocked'),patch.object(s,'healthy'):
            with self.assertRaises(d.Refused):s.keep()
        self.assertEqual(s.read_record()['stage'],'trial')
    def test_login_requires_keep_and_separate_approval(self):
        row=self.row();s.save(row)
        with patch.object(s,'unlocked'),patch.object(s,'healthy'):
            with self.assertRaises(d.Refused):s.keep(login=True,approved=True)
        row['stage']='kept';s.save(row)
        with patch.object(s,'unlocked'),patch.object(s,'healthy'),patch.object(d,'approve',side_effect=d.Refused('declined')):
            with self.assertRaises(d.Refused):s.keep(login=True)
        self.assertFalse(s.read_record()['login'])
    def test_offline_recovery_needs_no_compositor(self):
        file=self.base/'shell.json';file.write_text('baseline');before=d.info(file)
        tx=d.Transaction('omarchy-session');entry=tx.backup(file);tx.apply_file(entry,b'candidate');tx.commit()
        row=self.row();row['journal']=str(tx.path);s.save(row)
        with patch.object(s,'no_graphical_session',return_value=True),patch.object(s,'ipc') as ipc:
            self.assertTrue(s.request_restore());ipc.assert_not_called()
        self.assertEqual(d.info(file),before);self.assertFalse(s.active())
    def test_user_edits_prevent_stop(self):
        file=self.base/'shell.json';file.write_text('baseline');tx=d.Transaction('omarchy-session');entry=tx.backup(file);tx.apply_file(entry,b'candidate');file.write_text('user edit')
        row=self.row();row['journal']=str(tx.path)
        with patch.object(s,'no_graphical_session',return_value=False),patch.object(s,'unlocked'),patch.object(s,'ipc') as ipc:
            with self.assertRaises(d.Refused):s.restore(row)
            ipc.assert_not_called()
        self.assertEqual(file.read_text(),'user edit')
    def test_login_without_confirmation_recovers(self):
        row=self.row();s.save(row)
        with patch.object(s,'spawn_supervisor') as spawn:s.login();spawn.assert_called_once()
        self.assertEqual(s.read_record()['stage'],'restore-requested')
    def test_different_supervisor_cannot_touch_session(self):
        s.save(self.row())
        with patch.object(s,'lock_state') as probe:s.supervise('stale');probe.assert_not_called()
    def test_previous_login_supervisor_cannot_touch_new_generation(self):
        row=self.row();row['generation']='new-login';s.save(row)
        with patch.object(s,'lock_state') as probe:s.supervise('fixture','old-login');probe.assert_not_called()
    def test_suspend_waits_for_secure_coverage(self):
        s.save(self.row())
        with patch.object(s,'ipc',side_effect=['ok','{"secure":false}','{"secure":true}']),patch.object(s,'lock_state',return_value=True),patch.object(s.time,'sleep'),patch.object(d,'command') as command:
            s.request_lock(True);command.assert_called_once_with(['systemctl','suspend'])
    def test_update_refused_during_session(self):
        s.save(self.row())
        with contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaises(d.Refused):d.install(d.ROOT,approved=True)
        self.assertFalse((d.paths()['data']/'current').exists())
    def test_trial_keep_login_restore_transaction(self):
        config=Path.home()/'.config/omarchy/shell.json';d.write_json(config,self.config);original=d.info(config)
        row=self.row();row.update({'original':self.config,'adapter':'fixture','omarchyPid':1,'config':str(config)})
        with patch.object(s,'inspect',return_value=row),patch.object(d,'validate',return_value='Fixture'),patch.object(s,'unlocked'),patch.object(s,'spawn_supervisor'),contextlib.redirect_stdout(io.StringIO()):s.trial(d.ROOT,True)
        self.assertEqual(d.info(config),original,'Backup must precede live mutation')
        row=s.read_record()
        with patch.object(s,'unlocked'):s.prepare(row)
        self.assertEqual(d.read_json(config)['bar']['id'],'cedar.integration')
        self.assertTrue((config.parent/'hooks/post-boot.d/95-cedar-session').exists())
        row=s.read_record();row['stage']='trial';s.save(row)
        with patch.object(s,'unlocked'),patch.object(s,'healthy'),contextlib.redirect_stdout(io.StringIO()):
            s.keep();self.assertFalse(s.read_record()['login']);s.keep(login=True,approved=True)
        self.assertTrue(s.read_record()['login'])
        with patch.object(s,'no_graphical_session',return_value=True):s.restore(s.read_record())
        self.assertEqual(d.info(config),original)
        self.assertFalse((config.parent/'hooks/post-boot.d/95-cedar-session').exists())
    def test_preparation_interruption_restores(self):
        config=Path.home()/'.config/omarchy/shell.json';d.write_json(config,self.config);original=d.info(config)
        row=self.row();row.update({'original':self.config,'adapter':'fixture','omarchyPid':1,'config':str(config)})
        with patch.object(s,'inspect',return_value=row),patch.object(d,'validate',return_value='Fixture'),patch.object(s,'unlocked'),patch.object(s,'spawn_supervisor'),contextlib.redirect_stdout(io.StringIO()):s.trial(d.ROOT,True)
        with patch.object(s,'unlocked'),patch.dict(os.environ,{'CEDAR_INJECT_FAILURE':'activate'}):
            with self.assertRaises(OSError):s.prepare(s.read_record())
        with patch.object(s,'no_graphical_session',return_value=True):s.restore(s.read_record())
        self.assertEqual(d.info(config),original)
    def test_omacale_guard_precedes_swap_and_restores_without_touching_clone(self):
        config=Path.home()/'.config/omarchy/shell.json'
        original_config={**self.config,'bar':{'id':'omacale.bar'},'plugins':[{'id':'local.lock'}],'disabledPlugins':['omarchy.lock','omarchy.idle']}
        d.write_json(config,original_config);original=d.info(config)
        locker=config.parent/'plugins/local.lock/Service.qml';d.atomic(locker,b'existing authentication');locker_before=d.info(locker)
        row=self.row();row.update({'original':original_config,'adapter':'fixture','omarchyPid':1,'config':str(config),'omacale':{'lockId':'local.lock','disable':['local.osd']}})
        with patch.object(s,'inspect',return_value=row),patch.object(d,'validate',return_value='Fixture'),patch.object(s,'unlocked'),patch.object(s,'spawn_supervisor'),contextlib.redirect_stdout(io.StringIO()):s.trial(d.ROOT,True)
        with patch.object(s,'unlocked'):s.prepare(s.read_record())
        row=s.read_record();self.assertEqual(row['stage'],'coordinating')
        self.assertEqual(d.read_json(config)['bar']['id'],'omacale.bar')
        with patch.object(s,'unlocked'),patch.object(s,'ipc',return_value='false'):
            with self.assertRaises(d.Refused):s.coordinated(row)
        self.assertEqual(d.read_json(config)['bar']['id'],'omacale.bar')
        with patch.object(s,'unlocked'),patch.object(s,'ipc',return_value='true'):s.coordinated(row)
        self.assertEqual(d.read_json(config)['bar']['id'],'cedar.integration')
        self.assertEqual(d.info(locker),locker_before)
        self.assertNotIn('local.lock',d.read_json(config)['disabledPlugins'])
        with patch.object(s,'no_graphical_session',return_value=True):s.restore(s.read_record())
        self.assertEqual(d.info(config),original);self.assertEqual(d.info(locker),locker_before)
        self.assertFalse((config.parent/'plugins/cedar.omacale-guard/manifest.json').exists())

if __name__=='__main__':unittest.main()
