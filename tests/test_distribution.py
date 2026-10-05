import hashlib,importlib.util,io,json,os,shutil,stat,subprocess,sys,tarfile,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
import distribution as d
import network_policy as policy

class Distribution(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='cedar 雨 paths ');self.addCleanup(self.temp.cleanup);self.root=Path(self.temp.name)
        self.env=patch.dict(os.environ,{'HOME':str(self.root/'home'),**{'XDG_'+k+'_HOME':str(self.root/k.lower()) for k in ['CONFIG','DATA','STATE','CACHE']}});self.env.start();self.addCleanup(self.env.stop)
    def test_backup_restore_mode_time_and_conflicts(self):
        file=self.root/'example';file.write_text('private baseline');file.chmod(0o640);before=d.info(file)
        tx=d.Transaction('test');entry=tx.backup(file);tx.apply_file(entry,b'cedar write');tx.commit()
        self.assertEqual(stat.S_IMODE((tx.directory/entry['backup']).stat().st_mode),0o600)
        file.write_text('later user edit')
        with self.assertRaises(d.Refused):d.restore_journal(tx.path)
        self.assertEqual(file.read_text(),'later user edit')
        file.write_text('cedar write');file.chmod(0o600);d.restore_journal(tx.path)
        self.assertEqual(d.info(file),before)
    def test_link_and_absence_restore(self):
        link=self.root/'pointer';link.symlink_to('original');new=self.root/'new'
        tx=d.Transaction('test');a=tx.backup(link);b=tx.backup(new);tx.apply_link(a,'candidate');tx.apply_file(b,b'new');d.restore_journal(tx.path)
        self.assertEqual(os.readlink(link),'original');self.assertFalse(new.exists())
    def test_corrupt_backup_refuses(self):
        file=self.root/'file';file.write_text('old');tx=d.Transaction('test');e=tx.backup(file);tx.apply_file(e,b'new');(tx.directory/e['backup']).write_text('corrupted')
        with self.assertRaises(d.Refused):d.restore_journal(tx.path)
        self.assertEqual(file.read_text(),'new')
    def test_interrupt_durable_intent(self):
        file=self.root/'file';file.write_text('old');tx=d.Transaction('test');e=tx.backup(file)
        with patch.object(d,'atomic',side_effect=OSError('disk full')):
            with self.assertRaises(OSError):tx.apply_file(e,b'new')
        self.assertEqual(file.read_text(),'old');d.restore_journal(tx.path)
    def test_interrupted_second_owned_write_restores_baseline(self):
        file=self.root/'shell-config';file.write_text('original');before=d.info(file)
        tx=d.Transaction('session');entry=tx.backup(file);tx.apply_file(entry,b'coordinating')
        with patch.object(d,'atomic',side_effect=OSError('interrupted second stage')):
            with self.assertRaises(OSError):tx.replace_owned_file(entry,b'active')
        self.assertEqual(file.read_text(),'coordinating')
        d.restore_journal(tx.path);self.assertEqual(d.info(file),before)
    def test_stage_injection_and_concurrency(self):
        tx=d.Transaction('test')
        with patch.dict(os.environ,{'CEDAR_INJECT_FAILURE':'prepare'}):
            with self.assertRaises(OSError):tx.stage('prepare')
        self.assertEqual(d.read_json(tx.path)['stage'],'prepare')
        with d.exclusive():
            with self.assertRaises(d.Refused):
                with d.exclusive():pass
    def test_symlink_parent_not_followed(self):
        outside=self.root/'outside';outside.mkdir();(self.root/'managed').symlink_to(outside)
        with self.assertRaises(d.Refused):d.atomic(self.root/'managed/file',b'data')
        self.assertEqual(list(outside.iterdir()),[])
    def test_safe_archive_rejects_escape_links_and_duplicates(self):
        for names,kind in [(['../escape'],tarfile.REGTYPE),(['/absolute'],tarfile.REGTYPE),(['link'],tarfile.SYMTYPE),(['x','x'],tarfile.REGTYPE)]:
            archive=self.root/'test.tar.gz'
            with tarfile.open(archive,'w:gz') as tar:
                for name in names:
                    info=tarfile.TarInfo(name);info.type=kind;info.linkname='/outside';tar.addfile(info,io.BytesIO(b''))
            with self.assertRaises(d.Refused):d.safe_extract(archive,self.root/'out')
    def test_privacy_denies_before_network(self):
        for feature in ['weather','location','city-search']:
            with self.assertRaises(PermissionError):policy.require(feature)
        config=d.paths()['config']/'settings.json';d.write_json(config,{'localOnly':False,'weatherEnabled':True})
        policy.require('weather');policy.require('city-search')
        policy.require('location') # IP location follows the weather permission by default.
        d.write_json(config,{'localOnly':False,'weatherEnabled':True,'weatherAutomatic':False})
        with self.assertRaises(PermissionError):policy.require('location')
        d.write_json(config,{'localOnly':False,'weatherEnabled':False,'weatherAutomatic':True})
        with self.assertRaises(PermissionError):policy.require('location')
        d.write_json(config,{'localOnly':False,'weatherEnabled':True})
        with patch.dict(os.environ,{'CEDAR_LOCAL_ONLY':'1'}):
            with self.assertRaises(PermissionError):policy.require('weather')
    def test_install_repeat_update_and_restore(self):
        with patch.object(d,'validate',return_value='Fixture validation'),patch.object(d,'ensure_unlocked'),patch.object(d,'release_in_use',return_value=False):
            d.install(d.ROOT,approved=True)
            first=d.installed();self.assertTrue((first/'shell.qml').is_file())
            d.install(d.ROOT,approved=True);self.assertEqual(d.installed(),first)
            d.recover_latest('install');self.assertFalse((d.paths()['data']/'current').exists())
            self.assertTrue((d.paths()['data']/'recovery/distribution.py').is_file())
    def upgrade_fixture(self):
        with patch.object(d,'validate',return_value='Fixture validation'):
            d.install(d.ROOT,approved=True)
        source=self.root/'upgrade source'
        shutil.copytree(d.ROOT,source,ignore=shutil.ignore_patterns('.git','__pycache__'))
        (source/'VERSION').write_text('0.1.0-dev.fixture\n')
        protected=[d.paths()['data']/'current',d.paths()['bin'],*(d.paths()['data']/'recovery').glob('*.py')]
        return source,{path:d.info(path) for path in protected}
    def test_upgrade_lock_refusal_precedes_any_installed_helper_write(self):
        source,before=self.upgrade_fixture()
        with patch.object(d,'ensure_unlocked',side_effect=d.Refused('Fixture locked')),patch.object(d.Transaction,'apply_file') as write,patch.object(d,'validate') as validate:
            with self.assertRaisesRegex(d.Refused,'Fixture locked'):d.install(source,approved=True)
        write.assert_not_called();validate.assert_not_called()
        self.assertEqual({path:d.info(path) for path in before},before)
    def test_lock_beginning_during_validation_preserves_installed_helpers(self):
        source,before=self.upgrade_fixture()
        with patch.object(d,'ensure_unlocked',side_effect=[None,d.Refused('Fixture lock began')]),patch.object(d,'release_in_use',return_value=False),patch.object(d,'validate',return_value='Fixture validation'),patch.object(d.Transaction,'apply_file') as write:
            with self.assertRaisesRegex(d.Refused,'Fixture lock began'):d.install(source,approved=True)
        write.assert_not_called()
        self.assertEqual({path:d.info(path) for path in before},before)
    def test_running_release_blocks_upgrade_before_helpers_or_validation(self):
        source,before=self.upgrade_fixture()
        with patch.object(d,'ensure_unlocked'),patch.object(d,'release_in_use',return_value=True),patch.object(d.Transaction,'apply_file') as write,patch.object(d,'validate') as validate:
            with self.assertRaisesRegex(d.Refused,'release is in use'):d.install(source,approved=True)
        write.assert_not_called();validate.assert_not_called()
        self.assertEqual({path:d.info(path) for path in before},before)
    def test_uninstall_restores_entire_chain(self):
        file=self.root/'entry';file.write_text('baseline')
        for content in [b'first release',b'second release']:
            tx=d.Transaction('install');entry=tx.backup(file);tx.apply_file(entry,content);tx.commit()
        with patch.object(d,'ensure_unlocked'),patch.object(d,'release_in_use',return_value=False):d.uninstall(approved=True)
        self.assertEqual(file.read_text(),'baseline')
    def test_uninstall_preflights_older_backups(self):
        file=self.root/'entry';file.write_text('baseline')
        first=d.Transaction('install');entry=first.backup(file);first.apply_file(entry,b'first release');first.commit()
        second=d.Transaction('install');next_entry=second.backup(file);second.apply_file(next_entry,b'second release');second.commit()
        (first.directory/entry['backup']).write_text('corrupt baseline')
        with patch.object(d,'ensure_unlocked'),patch.object(d,'release_in_use',return_value=False):
            with self.assertRaises(d.Refused):d.uninstall(approved=True)
        self.assertEqual(file.read_text(),'second release')
        self.assertEqual(d.read_json(second.path)['stage'],'commit')
    def test_install_conflict_and_full_disk(self):
        binary=d.paths()['bin'];binary.parent.mkdir(parents=True);binary.write_text('unrelated program')
        with self.assertRaises(d.Refused):d.install(d.ROOT,approved=True)
        self.assertEqual(binary.read_text(),'unrelated program');binary.unlink()
        with patch.object(d.shutil,'disk_usage',return_value=type('Space',(),{'free':0})()):
            with self.assertRaises(d.Refused):d.install(d.ROOT,approved=True)
        self.assertFalse((d.paths()['data']/'current').exists())
    def test_redaction_synthetic_secrets(self):
        from redaction import redact
        value=redact('token=syntheticsecret password=example 192.0.2.9 person@example.invalid')
        self.assertNotIn('syntheticsecret',value);self.assertNotIn('person@',value);self.assertNotIn('192.0.2.9',value)
    def test_manifest_reconciles_files(self):
        for plugin in d.read_json(d.ROOT/'data/plugins.json')['plugins']:
            for file in plugin['files']:self.assertTrue((d.ROOT/file).is_file(),file)
    def test_relative_xdg_uses_spec_default(self):
        with patch.dict(os.environ,{'XDG_CONFIG_HOME':'relative'}):self.assertEqual(d.paths()['config'],Path.home()/'.config/cedar')
    def test_explicit_plan_has_no_mutation(self):
        plan=d.plan_install(d.ROOT);self.assertEqual(plan['desktopChanges'],[]);self.assertFalse(d.paths()['state'].exists())
    def test_signature_failure_precedes_extraction(self):
        with patch.object(d,'command',side_effect=d.Refused('bad signature')),patch.object(d,'safe_extract') as extract:
            with self.assertRaises(d.Refused):d.update(Path('archive'),Path('sig'),Path('key'))
            extract.assert_not_called()
    def test_standalone_recovery_cli_reports_session_refusals(self):
        recovery=self.root/'standalone recovery';recovery.mkdir()
        for name in ('distribution.py','omarchy_session.py','omarchy_providers.py','portable_session.py','portable_providers.py','portable_controls.py','adoption_plan.py','startup_graph.py'):
            shutil.copy2(d.ROOT/'scripts'/name,recovery/name)
        for action in ('keep','activate'):
            result=subprocess.run([sys.executable,str(recovery/'distribution.py'),action],cwd=self.root,text=True,capture_output=True)
            self.assertEqual(result.returncode,1)
            self.assertIn('CEDAR: No CEDAR trial is running.',result.stderr)
            self.assertIn('cedar try',result.stderr)
            self.assertNotIn('Traceback',result.stderr)
    def test_source_inventory_excludes_nested_clone_and_private_extras(self):
        source=self.root/'source';(source/'data').mkdir(parents=True)
        (source/'shell.qml').write_text('fixture shell')
        names=['data/source-files.json','shell.qml']
        d.write_json(source/'data/source-files.json',names)
        nested=source/'cedar-shell';(nested/'.git').mkdir(parents=True)
        (nested/'shell.qml').write_text('duplicate clone')
        (source/'settings.json').write_text('private local preferences')
        (source/'local-link').symlink_to(self.root)
        self.assertEqual([str(rel) for _,rel in d.files(source)],names)
        from package_release import package
        archive=self.root/'candidate.tar.gz';package(source,archive)
        with tarfile.open(archive) as tar:
            self.assertEqual(set(tar.getnames()),{'cedar-shell/'+n for n in [*names,'ARTIFACT-CONTENTS.json']})
        self.assertTrue((nested/'shell.qml').is_file())
    def test_source_inventory_rejects_missing_assets_and_symlink_parents(self):
        source=self.root/'source';(source/'data').mkdir(parents=True)
        manifest=source/'data/source-files.json'
        for names in [['missing.qml'],['../escape'],['/absolute'],['data/source-files.json']*2]:
            d.write_json(manifest,names)
            with self.assertRaises(d.Refused):d.files(source)
        outside=self.root/'outside';outside.mkdir();(outside/'asset').write_text('private')
        (source/'assets').symlink_to(outside)
        d.write_json(manifest,['assets/asset'])
        with self.assertRaises(d.Refused):d.files(source)

if __name__=='__main__':unittest.main()
