"""Migration regressions, entirely isolated from the user's desktop."""
import importlib.util,json,os,stat,sys,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
import migrate
import cedar_cli
import install

class Migration(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='cedar paths with spaces ');self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name)
        env={'HOME':str(self.root/'home'),**{'XDG_'+key.upper()+'_HOME':str(self.root/(key+' directory')) for key in ['config','data','state','cache']}}
        self.env=patch.dict(os.environ,env);self.env.start();self.addCleanup(self.env.stop)
        self.paths=migrate.locations()
    def legacy(self,value):
        p=self.paths['config']/'foxfire/settings.json';p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(value));return p
    def settings(self):return json.loads((self.paths['config']/'cedar/settings.json').read_text())
    def test_fresh_and_repeated(self):
        first=migrate.migrate();second=migrate.migrate()
        self.assertEqual(self.settings(),{'schemaVersion':1});self.assertFalse(second['created'])
        self.assertEqual(stat.S_IMODE(Path(first['backup']).stat().st_mode),0o700)
    def test_legacy_unknown_keys_assets_and_exact_mapping(self):
        original={'barStyle':'foxfire','clock24':False,'unknown':{'value':'foxfire'},'browser':'my-foxfire-browser'}
        old=self.legacy(original)
        asset=old.parent/'custom/my foxfire asset.txt';asset.parent.mkdir();asset.write_text('foxfire user script')
        result=migrate.migrate()
        self.assertEqual(json.loads(old.read_text()),original)
        self.assertEqual(self.settings(),{**original,'barStyle':'cedar','schemaVersion':1})
        self.assertEqual((self.paths['config']/'cedar/custom/my foxfire asset.txt').read_text(),'foxfire user script')
        self.assertEqual(result['status'],'committed');repeat=migrate.migrate();self.assertFalse(repeat['created']);self.assertFalse(repeat['preservedConflicts'])
    def test_all_xdg_namespaces(self):
        for base in self.paths.values():
            source=base/'foxfire/custom';source.parent.mkdir(parents=True);source.write_text('custom state')
        migrate.migrate()
        for base in self.paths.values():self.assertEqual((base/'cedar/custom').read_text(),'custom state')
    def test_both_namespaces_new_values_win_without_merging_unknown_preferences(self):
        self.legacy({'clock24':False,'unknown':'old'})
        new=self.paths['config']/'cedar/settings.json';new.parent.mkdir();new.write_text('{"clock24":true,"unknown":"new"}')
        result=migrate.migrate();self.assertEqual(self.settings(),{'clock24':True,'unknown':'new'})
        self.assertIn('config/settings.json',result['preservedConflicts'])
    def test_future_schema_and_invalid_values_stop_before_commit(self):
        for value in [{'schemaVersion':999},{'clock24':'false'},{'barHeight':True},[]]:
            self.legacy(value)
            with self.assertRaises(ValueError):migrate.migrate()
            self.assertFalse((self.paths['config']/'cedar/settings.json').exists())
    def test_failure_rolls_back_committed_files(self):
        self.legacy({'clock24':False})
        p=self.paths['data']/'foxfire/asset';p.parent.mkdir(parents=True);p.write_text('asset')
        original=migrate.write_json
        def fail(path,value):
            if path.name=='journal.json' and len(value.get('created',[]))==2 and value['status']=='validated':raise OSError('Simulated disk failure')
            original(path,value)
        with patch.object(migrate,'write_json',side_effect=fail):
            with self.assertRaises(OSError):migrate.migrate()
        self.assertFalse((self.paths['config']/'cedar/settings.json').exists());self.assertTrue(p.exists())
    def test_recovery_preserves_later_edits(self):
        self.legacy({'clock24':False});result=migrate.migrate()
        p=self.paths['config']/'cedar/settings.json';p.write_text('{"clock24":true}')
        self.assertEqual(migrate.recover(Path(result['backup'])/'journal.json'),[str(p)])
        self.assertTrue(p.exists())
    def test_recovery_removes_only_unchanged_copies(self):
        old=self.legacy({'clock24':False});result=migrate.migrate()
        self.assertFalse(migrate.recover(Path(result['backup'])/'journal.json'))
        self.assertTrue(old.exists());self.assertFalse((self.paths['config']/'cedar/settings.json').exists())
    def test_locked_or_unknown_activation_never_touches_files(self):
        for code in [0,2,127]:
            with patch.object(cedar_cli,'run',return_value=type('Result',(),{'returncode':code})()),patch.object(cedar_cli,'private') as writes:
                with self.assertRaises(RuntimeError):cedar_cli.activate()
                writes.assert_not_called()
    def test_command_conflict_not_overwritten(self):
        p=self.root/'home/.local/bin/cedar';p.parent.mkdir(parents=True);p.write_text('unrelated application')
        with self.assertRaises(RuntimeError):install.preflight()
        self.assertEqual(p.read_text(),'unrelated application')
    def test_repeated_registration(self):
        install.register();install.register()
        for path,target in install.links().items():self.assertEqual(path.resolve(),target)
    def test_missing_optional_dependencies_are_not_fatal(self):
        original=install.shutil.which
        with patch.object(install.shutil,'which',side_effect=lambda c: None if c in ('cava','nvidia-smi') else original(c)):
            self.assertIn('cava',[x['command'] for x in install.dependencies()])
    def test_missing_required_dependencies_stop(self):
        with patch.object(install.shutil,'which',return_value=None):
            with self.assertRaises(RuntimeError):install.dependencies()

class Branding(unittest.TestCase):
    def test_canonical_content(self):
        data=json.loads((ROOT/'data/branding.json').read_text())
        self.assertEqual(data['name'],'CEDAR')
        self.assertEqual(data['acronym'],'Contextual Environment & Desktop Automation Runtime')
        self.assertEqual(data['psalm']['text'],'The righteous shall flourish like the palm tree: he shall grow like a cedar in Lebanon.')
        self.assertEqual([v['text'] for v in data['john']['verses']],[
            'For God so loved the world, that he gave his only begotten Son, that whosoever believeth in him should not perish, but have everlasting life.',
            'For God sent not his Son into the world to condemn the world; but that the world through him might be saved.'])
        self.assertEqual(data['john']['translation'],'King James Version (KJV)')
    def test_legacy_names_are_allowlisted(self):
        allow=json.loads((ROOT/'data/legacy-allowlist.json').read_text())
        import re
        found=[]
        for path in ROOT.rglob('*'):
            if not path.is_file() or any(x in path.parts for x in ['.git','__pycache__']):continue
            if path.suffix in ['.png','.log']:continue
            try:text=path.read_text()
            except UnicodeError:continue
            if re.search('foxfire',text,re.I):found.append(str(path.relative_to(ROOT)))
        self.assertEqual(set(found)-set(allow),set())

class Activation(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(prefix='cedar activation ');self.addCleanup(self.tmp.cleanup)
        self.home=Path(self.tmp.name)
        self.env=patch.dict(os.environ,{'HOME':str(self.home),'XDG_CONFIG_HOME':str(self.home/'.config'),'XDG_STATE_HOME':str(self.home/'.local/state'),'XDG_DATA_HOME':str(self.home/'.local/share'),'XDG_CACHE_HOME':str(self.home/'.cache'),'XDG_RUNTIME_DIR':str(self.home/'runtime')})
        self.env.start();self.addCleanup(self.env.stop);(self.home/'runtime').mkdir()
        install.register()
        config=self.home/'.config';self.old=self.home/'old source';(self.old/'scripts').mkdir(parents=True);(self.old/'scripts/theme-hook').write_text('legacy hook')
        (config/'quickshell/foxfire').symlink_to(self.old)
        for group in ['theme-set.d','post-boot.d']:
            d=config/'omarchy/hooks'/group;d.mkdir(parents=True);(d/'90-foxfire').symlink_to(self.old/'scripts/theme-hook')
        from desktop import loader
        main=config/'hypr/hyprland.lua';main.parent.mkdir();main.write_text('-- untouched monitor configuration'+loader(config/'foxfire/hypr').replace('-- CEDAR graphical settings','-- Foxfire graphical settings'))
        self.original=main.read_text();self.current=self.home/'.local/state/omarchy/current/theme.name';self.current.parent.mkdir(parents=True);self.current.write_text('foxfire')
        self.live={'foxfire'};self.calls=[];self.fail=False
    def command(self,args,check=True,timeout=20):
        self.calls.append(args)
        out='';code=0
        if args[0]=='omarchy-hyprland-session-locked':code=1
        elif args[:3]==['qs','list','-j']:out=json.dumps([{}] if args[-1] in self.live else [])
        elif args[0]=='qs' and 'isLocked' in args:out='false'
        elif args[0]=='qs' and args[-1]=='stop':self.live.discard(args[2])
        elif args[:3]==['omarchy','theme','set']:
            self.current.write_text(args[-1])
            if args[-1]=='cedar' and self.fail:raise RuntimeError('Simulated launch failure')
            self.live.add(args[-1])
        return type('Result',(),{'returncode':code,'stdout':out,'stderr':''})()
    def test_activation_then_repeat_then_recovery_never_duplicates_shells(self):
        with patch.object(cedar_cli,'run',side_effect=self.command),patch.object(install,'validate',return_value='validated'):
            cedar_cli.activate();cedar_cli.activate()
            self.assertEqual(self.live,{'cedar'})
            from desktop import loader
            self.assertEqual((self.home/'.config/hypr/hyprland.lua').read_text(),'-- untouched monitor configuration'+loader(self.home/'.config/cedar/hypr'))
            self.assertEqual(sum(c[:3]==['omarchy','theme','set'] for c in self.calls),1)
            self.assertTrue((self.home/'.config/omarchy/hooks/post-boot.d/90-cedar').is_symlink())
            self.assertFalse((self.home/'.config/omarchy/hooks/post-boot.d/90-foxfire').exists())
            cedar_cli.rollback()
            self.assertEqual(self.live,{'foxfire'})
            self.assertEqual((self.home/'.config/hypr/hyprland.lua').read_text(),self.original)
    def test_failed_activation_restores_startup(self):
        self.fail=True
        with patch.object(cedar_cli,'run',side_effect=self.command),patch.object(install,'validate',return_value='validated'):
            with self.assertRaises(RuntimeError):cedar_cli.activate()
            self.assertEqual(self.live,{'foxfire'})
            self.assertEqual((self.home/'.config/hypr/hyprland.lua').read_text(),self.original)
            self.assertTrue((self.home/'.config/omarchy/hooks/post-boot.d/90-foxfire').is_symlink())
    def test_rollback_preserves_external_edit(self):
        with patch.object(cedar_cli,'run',side_effect=self.command),patch.object(install,'validate',return_value='validated'):
            cedar_cli.activate()
            main=self.home/'.config/hypr/hyprland.lua';main.write_text('user changed configuration')
            with self.assertRaises(RuntimeError):cedar_cli.rollback()
            self.assertEqual(main.read_text(),'user changed configuration')
            self.assertEqual(self.live,{'cedar'})

class RuntimeMigration(unittest.TestCase):
    setUp = Migration.setUp
    legacy = Migration.legacy
    def test_timer_moves_to_state_without_changing_preferences(self):
        self.legacy({'clock24':False})
        old=self.paths['config']/'foxfire/core-timer.json';old.write_text('{"active":true,"deadline":12345}')
        migrate.migrate()
        self.assertTrue(old.exists())
        self.assertFalse((self.paths['config']/'cedar/core-timer.json').exists())
        self.assertEqual(json.loads((self.paths['state']/'cedar/core-timer.json').read_text()),{'active':True,'deadline':12345})
    def test_destination_symlink_does_not_escape_namespace(self):
        self.legacy({'clock24':False})
        old=self.paths['config']/'foxfire/assets/item';old.parent.mkdir();old.write_text('asset')
        outside=self.root/'outside';outside.mkdir()
        new=self.paths['config']/'cedar';new.mkdir();(new/'assets').symlink_to(outside)
        with self.assertRaises(RuntimeError):migrate.migrate()
        self.assertFalse((outside/'item').exists())

class QuickshellInventory(unittest.TestCase):
    def test_empty_inventory_plain_text_is_not_json(self):
        result=type('Result',(),{'returncode':0,'stdout':'No running instances for "config"\nUse --all to list all instances.\n','stderr':''})()
        with patch.object(cedar_cli,'run',return_value=result):self.assertEqual(cedar_cli.instances('cedar'),[])
