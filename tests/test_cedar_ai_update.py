import io,json,subprocess,sys,tempfile,unittest,urllib.error
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
import cedar_ai_update as u

class CedarAiUpdate(unittest.TestCase):
    def run_serve(self,request):
        responses=[]
        with patch('sys.stdin',io.StringIO(json.dumps(request)+'\n')),patch.object(u,'respond',lambda ok,payload:responses.append((ok,payload))):
            code=u.serve()
        self.assertEqual(len(responses),1)
        ok,payload=responses[0]
        return code,{"ok":ok,("data" if ok else "error"):payload}
    def test_status_reports_installed_state_without_network(self):
        probe=subprocess.CompletedProcess([],0,stdout='0.3.1\n',stderr='')
        with patch.object(u.subprocess,'run',return_value=probe):
            code,response=self.run_serve({'action':'status'})
        self.assertEqual(code,0)
        self.assertTrue(response['ok'])
        self.assertEqual(response['data']['installed'],'0.3.1')
    def test_status_absence_is_explicit(self):
        probe=subprocess.CompletedProcess([],0,stdout='',stderr='')
        with patch.object(u.subprocess,'run',return_value=probe):
            code,response=self.run_serve({'action':'status'})
        self.assertTrue(response['ok'])
        self.assertIsNone(response['data']['installed'])
    def test_serve_install_returns_output_and_state(self):
        with patch.object(u,'install',return_value=0),patch.object(u,'installed_version',return_value='0.1.0'),patch.object(u,'cedar_ai_command',return_value='/home/u/.local/bin/cedar-ai'):
            code,response=self.run_serve({'action':'install'})
        self.assertEqual(code,0)
        self.assertTrue(response['ok'])
        self.assertEqual(response['data']['installed'],'0.1.0')
    def test_serve_install_failure_is_honest(self):
        def failing_install():
            print("Download failed: connection refused")
            return 1
        with patch.object(u,'install',side_effect=failing_install) as install:
            code,response=self.run_serve({'action':'install'})
        install.assert_called_once()
        self.assertEqual(code,1)
        self.assertFalse(response['ok'])
        self.assertIn('connection refused',response['error'])
    def test_serve_install_capture_is_fd_level_single_json(self):
        probe = (
            "import sys, io, os, json\n"
            "sys.path.insert(0, %r)\n"
            "import cedar_ai_update as u\n"
            "sys.stdin = io.StringIO(json.dumps({'action':'install'}) + chr(10))\n"
            "u.install = lambda: (os.write(1, b'native stdout'), os.write(2, b'native stderr'), 0)[-1]\n"
            "u.installed_version = lambda: '0.1.0'\n"
            "u.cedar_ai_command = lambda: '/x/cedar-ai'\n"
            "u.serve()\n"
        ) % str(Path(u.__file__).resolve().parent)
        with tempfile.NamedTemporaryFile('w', suffix='.py', delete=False) as f:
            f.write(probe)
            probe_path = f.name
        try:
            out = subprocess.run([sys.executable, probe_path], capture_output=True, text=True)
        finally:
            Path(probe_path).unlink()
        self.assertEqual(out.stderr, '')
        lines = [l for l in out.stdout.strip().split('\n') if l]
        self.assertEqual(len(lines), 1)
        response = json.loads(lines[0])
        self.assertTrue(response['ok'])
        self.assertIn('native stdout', response['data']['output'])
        self.assertIn('native stderr', response['data']['output'])
    def test_serve_install_translates_exceptions(self):
        with patch.object(u,'install',side_effect=OSError('disk full')):
            code,response=self.run_serve({'action':'install'})
        self.assertEqual(code,1)
        self.assertFalse(response['ok'])
        self.assertIn('disk full',response['error'])
    def test_unknown_action_fails(self):
        code,response=self.run_serve({'action':'defenestrate'})
        self.assertEqual(code,1)
        self.assertFalse(response['ok'])
    @staticmethod
    def completed(code):
        return subprocess.CompletedProcess([],code)
    def test_plant_descriptor_creates_and_preserves_unknown_keys(self):
        with tempfile.TemporaryDirectory() as home:
            with patch.object(u,'config_dir',return_value=Path(home)):
                path=u.plant_descriptor()
                data=json.loads(path.read_text())
                self.assertEqual(data['id'],'cedar-ai')
                self.assertEqual(data['unit'],'cedar-ai.service')
                path.write_text(json.dumps({'id':'cedar-ai','custom':'keep me','unit':'other.service'}))
                u.plant_descriptor()
                data=json.loads(path.read_text())
                self.assertEqual(data['custom'],'keep me')
                self.assertEqual(data['unit'],'cedar-ai.service')
    def test_plant_descriptor_permissions_are_private(self):
        import os, stat
        old_umask = os.umask(0o022)
        try:
            with tempfile.TemporaryDirectory() as home:
                with patch.object(u,'config_dir',return_value=Path(home)):
                    path=u.plant_descriptor()
                self.assertEqual(stat.S_IMODE(path.stat().st_mode),0o600)
                self.assertEqual(stat.S_IMODE(path.parent.stat().st_mode),0o700)
        finally:
            os.umask(old_umask)
    def test_plant_desktop_entry(self):
        with tempfile.TemporaryDirectory() as home:
            with patch.dict(u.os.environ,{'XDG_DATA_HOME':home}):
                path=u.plant_desktop_entry()
            text=path.read_text()
            self.assertIn('Name=CEDAR Ai',text)
            self.assertIn('127.0.0.1:3650',text)
    def test_candidate_pythons_prefers_pipx_home(self):
        with patch.dict(u.os.environ,{'PIPX_HOME':'/tmp/pipx-home'}):
            candidates=u.candidate_pythons()
        self.assertEqual(str(candidates[0]),'/tmp/pipx-home/venvs/cedar-ai/bin/python')
    def test_ensure_installer_rebuilds_incomplete_venv(self):
        with tempfile.TemporaryDirectory() as home:
            data=Path(home)/'data'
            broken=data/'venv'
            broken.mkdir(parents=True)  # interrupted creation: no bin/python
            calls=[]
            def fake_run(argv,**kw):
                calls.append(argv)
                if argv[1:3]==['-m','venv']:
                    (Path(argv[-1])/'bin').mkdir(parents=True)
                return self.completed(0)
            with patch.object(u.shutil,'which',return_value=None),patch.object(u,'DATA_DIR',data),patch.object(u.Path,'home',return_value=Path(home)),patch.object(u.subprocess,'run',side_effect=fake_run):
                command=u.ensure_installer(Path('/tmp/src'))
            self.assertTrue((data/'venv/bin').is_dir())
            self.assertTrue(any(a[1:3]==['-m','venv'] for a in calls))
            self.assertEqual(command,str(Path(home)/'.local/bin/cedar-ai'))
    def test_pipx_install_retires_managed_venv(self):
        with tempfile.TemporaryDirectory() as home:
            data=Path(home)/'data'
            (data/'venv/bin').mkdir(parents=True)
            with patch.object(u.shutil,'which',return_value='/usr/bin/pipx'),patch.object(u,'DATA_DIR',data),patch.object(u.subprocess,'run',return_value=self.completed(0)):
                self.assertIsNotNone(u.ensure_installer(Path('/tmp/src')))
            self.assertFalse((data/'venv').exists())
    def test_plant_unit_writes_inactive_unit_and_preserves_existing(self):
        with tempfile.TemporaryDirectory() as home:
            with patch.object(u,'config_dir',return_value=Path(home)),patch.object(u.subprocess,'run',return_value=self.completed(0)):
                path=u.plant_unit('/home/u/.local/bin/cedar-ai')
                text=path.read_text()
                self.assertIn('ExecStart=%h/.local/bin/cedar-ai serve',text)
                path.write_text('# user edited')
                self.assertIsNone(u.plant_unit('/home/u/.local/bin/cedar-ai'))
                self.assertEqual(path.read_text(),'# user edited')
    def test_install_lock_refuses_a_concurrent_install(self):
        import fcntl
        with tempfile.TemporaryDirectory() as home:
            state=Path(home)/'state'; state.mkdir()
            lock=open(state/'install.lock','w')
            fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
            try:
                with patch.object(u,'STATE_DIR',state),patch('sys.stdout',io.StringIO()) as out:
                    self.assertEqual(u.install(),1)
            finally:
                lock.close()
            self.assertIn('already running',out.getvalue())
    def test_installed_version_probe_failure_is_reported_not_raised(self):
        broken=Path(tempfile.mkdtemp())/'python'
        broken.write_text('#!')  # not executable
        with patch.object(u,'candidate_pythons',return_value=[broken]):
            self.assertIsNone(u.installed_version())
        self.assertIn(str(broken),u.probe_error)
    def test_status_includes_probe_error(self):
        with patch.object(u,'installed_version',return_value=None),patch.object(u,'probe_error','x: boom'),patch.object(u,'cedar_ai_command',return_value=''):
            code,response=self.run_serve({'action':'status'})
        self.assertTrue(response['ok'])
        self.assertEqual(response['data']['probe_error'],'x: boom')
    def test_ensure_installer_prefers_pipx(self):
        with tempfile.TemporaryDirectory() as home:
            with patch.object(u.shutil,'which',return_value='/usr/bin/pipx'),patch.object(u,'DATA_DIR',Path(home)/'data'),patch.object(u.subprocess,'run',return_value=self.completed(0)) as run:
                self.assertEqual(u.ensure_installer(Path('/tmp/src')),str(Path.home()/'.local/bin/cedar-ai'))
        self.assertEqual(run.call_args.args[0][:2],['/usr/bin/pipx','install'])
    def test_ensure_installer_venv_path(self):
        with tempfile.TemporaryDirectory() as home:
            data=Path(home)/'data'
            with patch.object(u.shutil,'which',return_value=None),patch.object(u,'DATA_DIR',data),patch.object(u.Path,'home',return_value=Path(home)):
                (data/'venv/bin').mkdir(parents=True)
                (data/'venv/bin/python').write_text('#!')
                (data/'venv/bin/cedar-ai').write_text('#!')
                with patch.object(u.subprocess,'run',return_value=self.completed(0)):
                    command=u.ensure_installer(Path('/tmp/src'))
            self.assertEqual(command,str(Path(home)/'.local/bin/cedar-ai'))
    def test_ensure_installer_reports_pip_failure(self):
        with tempfile.TemporaryDirectory() as home:
            data=Path(home)/'data'
            (data/'venv/bin').mkdir(parents=True)
            (data/'venv/bin/python').write_text('#!')
            runs=[self.completed(0),self.completed(1)]  # probe passes, install fails
            with patch.object(u.shutil,'which',return_value=None),patch.object(u,'DATA_DIR',data),patch.object(u.subprocess,'run',side_effect=runs),patch('sys.stdout',io.StringIO()) as out:
                self.assertIsNone(u.ensure_installer(Path('/tmp/src')))
            self.assertIn('pip reported a failure',out.getvalue())
    def test_release_lookup(self):
        payload={'tag_name':'v1.0.0','tarball_url':'https://example.test/x.tar.gz'}
        with patch.object(u,'fetch_json',return_value=payload):
            self.assertEqual(u.latest_release(),('v1.0.0','https://example.test/x.tar.gz'))
    def test_no_release_falls_back_to_main(self):
        error=urllib.error.HTTPError(u.LATEST_RELEASE,404,'Not Found',{},None)
        with patch.object(u,'fetch_json',side_effect=error):
            self.assertIsNone(u.latest_release())
    def test_other_http_errors_raise(self):
        error=urllib.error.HTTPError(u.LATEST_RELEASE,500,'Server Error',{},None)
        with patch.object(u,'fetch_json',side_effect=error),self.assertRaises(urllib.error.HTTPError):
            u.latest_release()

if __name__=='__main__':
    unittest.main()
