import hashlib,importlib.util,io,json,os,stat,sys,tarfile,tempfile,unittest
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
        with self.assertRaises(PermissionError):policy.require('location')
        with patch.dict(os.environ,{'CEDAR_LOCAL_ONLY':'1'}):
            with self.assertRaises(PermissionError):policy.require('weather')
    def test_install_repeat_update_and_restore(self):
        with patch.object(d,'validate',return_value='Fixture validation'),patch.object(d,'ensure_unlocked'),patch.object(d,'release_in_use',return_value=False):
            d.install(d.ROOT,approved=True)
            first=d.installed();self.assertTrue((first/'shell.qml').is_file())
            d.install(d.ROOT,approved=True);self.assertEqual(d.installed(),first)
            d.recover_latest('install');self.assertFalse((d.paths()['data']/'current').exists())
            self.assertTrue((d.paths()['data']/'recovery/distribution.py').is_file())
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

if __name__=='__main__':unittest.main()
