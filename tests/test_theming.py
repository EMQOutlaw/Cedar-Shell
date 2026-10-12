"""Native configuration and transaction tests; these do not certify rendered appearance."""
import base64
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import tomllib
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
from theming import adapters, engine, formats, registry, tokens, wallpaper
from theming.transaction import Store, Conflict, file_op
from application_theming import public_plan

class Theming(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.home=Path(self.temp.name)
        self.store=Store(self.home,self.home/'config',self.home/'data',self.home/'state')
        self.theme=tokens.compile_theme()
    def tearDown(self):self.temp.cleanup()
    def put(self,path,text):path.parent.mkdir(parents=True,exist_ok=True);path.write_text(text);return path
    def detected(self,*ids):return [{**s,'installed':id in ids,'native':True,'flatpaks':[]} for id,s in registry.REGISTRY.items()]
    def options(self,**values):return {**engine.DEFAULT,'enabled':True,'inherit':False,**values}
    def test_tokens_contrast_and_variants(self):
        for mode in ('light','dark'):
            theme=tokens.compile_theme({}, {'variant':mode});t=theme['tokens']
            for surface in ('background.primary','surface.default','background.elevated'):
                self.assertGreaterEqual(tokens.contrast(t['text.primary'],t[surface]),4.5)
                self.assertGreaterEqual(tokens.contrast(t['text.secondary'],t[surface]),4.5)
        self.assertNotEqual(tokens.compile_theme()['colors'],tokens.compile_theme({}, {'variant':'light'})['colors'])
    def test_semantic_override_and_shell_agree(self):
        theme=tokens.compile_theme({'tokens':{'accent.primary':'#123456'}},{'accent':'#abcdef'})
        self.assertEqual(theme['tokens']['accent.primary'],'#abcdef');self.assertEqual(theme['colors']['green'],'#abcdef')
    def test_invalid_tokens(self):
        for options in ({'accent':'red\nexec evil'},{'opacity':0},{'fontSize':True},{'terminalPalette':{'text.primary':'#ffffff'}}):
            with self.assertRaises(ValueError):tokens.compile_theme({},options)
    def test_terminal_independent(self):
        t=tokens.compile_theme({}, {'terminalPalette':{'terminal.red':'#123456'}})['tokens']
        self.assertEqual(t['terminal.red'],'#123456');self.assertNotEqual(t['status.error'],'#123456')
    def test_native_adapter_idempotence_and_reset(self):
        self.put(self.store.config/'hypr/hyprland.conf','# User settings\n')
        skipped={'gtk4','gnome-terminal','tilix','obs','spotify','discord'}
        for id in registry.REGISTRY.keys()-skipped:
            with self.subTest(adapter=id):
                ops=adapters.generate(self.store,id,self.theme)
                self.store.apply(ops)
                self.assertEqual(self.store.apply(adapters.generate(self.store,id,self.theme))['changed'],0)
                self.store.restore(reset=True)
                for op in ops:self.assertEqual(self.store.read_op(op),op['before'])
    def test_existing_settings_and_comments(self):
        samples={'alacritty/alacritty.toml':'# personal\n[general]\nimport = ["local.toml"]\n[window]\npadding = { x = 12, y = 9 }\n[font]\nsize = 14\n',
                 'kitty/kitty.conf':'# personal\nmap ctrl+shift+x launch\nfont_size 14\n',
                 'foot/foot.ini':'# personal\n[main]\nterm=xterm-256color\n[scrollback]\nlines=30000\n',
                 'gtk-3.0/settings.ini':'# personal\n[Settings]\ngtk-enable-animations=0\n',
                 'kdeglobals':'# personal\n[KDE]\nSingleClick=false\n',
                 'Code/User/settings.json':'{\n// personal\n"editor.tabSize": 3, "workbench.colorCustomizations": {"editor.lineHighlightBorder":"#123456"},\n}\n'}
        for p,s in samples.items():self.put(self.store.config/p,s)
        for id in ('alacritty','kitty','foot','gtk3','kde','vscode'):self.store.apply(adapters.generate(self.store,id,self.theme))
        self.assertIn('padding = { x = 12, y = 9 }',(self.store.config/'alacritty/alacritty.toml').read_text())
        self.assertIn('map ctrl+shift+x launch',(self.store.config/'kitty/kitty.conf').read_text())
        self.assertIn('lines=30000',(self.store.config/'foot/foot.ini').read_text())
        self.assertIn('SingleClick=false',(self.store.config/'kdeglobals').read_text())
        self.assertIn('gtk-enable-animations=0',(self.store.config/'gtk-3.0/settings.ini').read_text())
        doc=formats.jsonc_load((self.store.config/'Code/User/settings.json').read_text())
        self.assertEqual(doc['editor.tabSize'],3);self.assertEqual(doc['workbench.colorCustomizations']['editor.lineHighlightBorder'],'#123456')
        self.store.restore(True)
        for path,original in samples.items():self.assertEqual((self.store.config/path).read_text(),original)
    def test_invalid_config_preserved(self):
        path=self.put(self.store.config/'alacritty/alacritty.toml','[broken\n')
        with self.assertRaises(ValueError):adapters.generate(self.store,'alacritty',self.theme)
        self.assertEqual(path.read_text(),'[broken\n')
    def test_symlinks_readonly_and_outside(self):
        target=self.put(self.store.config/'real','content');link=self.store.config/'link';link.symlink_to(target)
        with self.assertRaises(Conflict):self.store.snapshot(link)
        target.chmod(0o400)
        with self.assertRaises(Conflict):self.store.apply([file_op(self.store,target,'new','test')])
        with self.assertRaises(Conflict):self.store.snapshot('/etc/passwd')
        target.chmod(0o600)
    def test_later_edits_are_preserved(self):
        path=self.put(self.store.config/'kitty/kitty.conf','font_size 14\n')
        self.store.apply(adapters.generate(self.store,'kitty',self.theme));path.write_text(path.read_text()+'# later edit\n')
        with self.assertRaises(Conflict):self.store.restore(True)
        with self.assertRaises(Conflict):self.store.apply(adapters.generate(self.store,'kitty',self.theme))
        self.assertIn('# later edit',path.read_text())
    def test_failed_write_rolls_back(self):
        a=self.put(self.store.config/'a','old a');b=self.put(self.store.config/'b','old b')
        ops=[file_op(self.store,a,'new a','test'),file_op(self.store,b,'new b','test')];original=self.store.write_op
        def fail(op,snapshot):
            if op['path']==str(b) and snapshot==op['after']:raise OSError('simulated failure')
            original(op,snapshot)
        with patch.object(self.store,'write_op',side_effect=fail),self.assertRaises(OSError):self.store.apply(ops)
        self.assertEqual(a.read_text(),'old a');self.assertEqual(b.read_text(),'old b');self.assertFalse((self.store.state/'pending.json').exists())
    def test_interrupted_recovery(self):
        a=self.put(self.store.config/'a','old');op=file_op(self.store,a,'new','test')
        self.store.save(self.store.state/'pending.json',{'id':'test','operations':[op],'ownersBefore':{}});self.store.write_op(op,op['after'])
        with self.store.lock():self.store.recover()
        self.assertEqual(a.read_text(),'old')
    def test_interrupted_conflict(self):
        a=self.put(self.store.config/'a','old');op=file_op(self.store,a,'new','test')
        self.store.save(self.store.state/'pending.json',{'id':'test','operations':[op],'ownersBefore':{}});a.write_text('user')
        with self.assertRaises(Conflict):self.store.recover()
        self.assertEqual(a.read_text(),'user')
    def test_restore_previous(self):
        path=self.put(self.store.config/'a','original')
        self.store.apply([file_op(self.store,path,'one','test')]);self.store.apply([file_op(self.store,path,'two','test')])
        self.store.restore();self.assertEqual(path.read_text(),'one');self.store.restore(True);self.assertEqual(path.read_text(),'original')
    def test_preview_apply_and_stale(self):
        options=self.options(apps=['alacritty']);detected=self.detected('alacritty')
        plan=engine.preview(self.store,options,detected)
        self.assertNotIn('before',json.dumps(public_plan(plan)))
        engine.apply(self.store,options,plan['id'],detected)
        with self.assertRaises(Conflict):engine.apply(self.store,options,plan['id'],detected)
    def test_missing_app_and_disabled(self):
        plan=engine.preview(self.store,self.options(apps=['kitty']),self.detected())
        self.assertEqual(plan['reports'][0]['status'],'Not installed')
        self.assertFalse(any(o['app']=='kitty' for o in plan['operations']))
        plan=engine.preview(self.store,self.options(enabled=False,mode='external'),self.detected())
        self.assertEqual([o['app'] for o in plan['operations']],['preferences'])
    def test_app_override(self):
        opt=self.options(apps=['kitty'],overrides={'kitty':{'accent':'#123456'}})
        plan=engine.preview(self.store,opt,self.detected('kitty'))
        content=''.join(base64.b64decode(o['after']['data']).decode() for o in plan['operations'] if o['app']=='kitty')
        self.assertIn('cursor #123456',content)
    def test_discovery(self):
        self.put(self.store.config/'kitty/kitty.conf','')
        apps={a['id']:a for a in registry.discover(self.store,which=lambda x: '/bin/'+x if x=='alacritty' else None,flatpaks=['org.mozilla.firefox'])}
        self.assertTrue(apps['alacritty']['installed']);self.assertTrue(apps['kitty']['native']);self.assertIn('org.mozilla.firefox',apps['firefox']['flatpaks'])
    def test_conflicting_managers(self):
        self.put(self.store.config/'matugen/config.toml','')
        self.assertTrue(registry.conflicts(self.store)['possibleOwners'])
    def test_flatpak_no_files(self):
        detected=self.detected('vscode');next(a for a in detected if a['id']=='vscode').update(native=False,flatpaks=['com.visualstudio.code'])
        plan=engine.preview(self.store,self.options(apps=['vscode']),detected)
        self.assertFalse(any(o['app']=='vscode' for o in plan['operations']))
        self.assertEqual(plan['reports'][0]['status'],'Requires portal integration')
    def test_jsonc_strings_comments_and_trailing_commas(self):
        raw='{// comment\n "literal": ",}", "other": true,}'
        result=formats.jsonc_patch(raw,{'theme':'CEDAR'})
        self.assertEqual(formats.jsonc_load(result)['literal'],',}');self.assertIn('// comment',result)
    def test_wallpaper_cache(self):
        path=self.put(self.home/'image.png','fake image');result=type('Result',(),{'returncode':0,'stdout':bytes([50,100,70])*1024})()
        with patch('theming.wallpaper.shutil.which',return_value='/bin/magick'),patch('theming.wallpaper.subprocess.run',return_value=result) as run:
            a=wallpaper.extract(self.store,path);b=wallpaper.extract(self.store,path);self.assertEqual(a,b);self.assertEqual(run.call_count,1)
            self.assertEqual(wallpaper.extract(self.store,path,'light','#123456')['colors']['green'],'#123456')
    def test_real_fixtures(self):
        fixtures=Path(__file__).parent/'fixtures/theming'
        for adapter,source,destination in [('alacritty','alacritty.toml','alacritty/alacritty.toml'),('vscode','settings.jsonc','Code/User/settings.json'),('kde','kdeglobals','kdeglobals')]:
            path=self.put(self.store.config/destination,(fixtures/source).read_text())
            before=path.read_bytes();self.store.apply(adapters.generate(self.store,adapter,self.theme));self.store.restore(True);self.assertEqual(path.read_bytes(),before)
    def test_foot_legacy_schema(self):
        with patch('theming.adapters.foot_version',return_value=None):
            self.put(self.store.config/'foot/foot.ini','font=monospace:size=11\n[colors]\nbackground=000000\n')
            op=adapters.generate(self.store,'foot',self.theme)[0]
            text=base64.b64decode(op['after']['data']).decode();self.assertIn('[colors]',text);self.assertIn('[cursor]',text);self.assertNotIn('colors-dark',text)
    def test_inherited_theme_events(self):
        options=self.options(inherit=True,apps=['alacritty']);detected=self.detected('alacritty')
        path=self.put(self.store.config/'cedar/theme.json',json.dumps({'colors':{'green':'#abcdef'}}))
        plan=engine.preview(self.store,options,detected);engine.apply(self.store,options,plan['id'],detected)
        path.write_text(json.dumps({'colors':{'green':'#fedcba'}}))
        plan=engine.preview(self.store,options,detected);engine.apply(self.store,options,plan['id'],detected)
        self.assertIn('#fedcba',(self.store.config/'alacritty/alacritty.toml').read_text())
    def test_palette_mode_override(self):
        dark={'mode':'dark','colors':{'background':'#010203','text':'#ffffff'}}
        theme=tokens.compile_theme(dark,{'variant':'light'});self.assertGreater(tokens.luminance(theme['tokens']['background.primary']),.7)
    def test_unlocked_wallpaper_accent(self):
        self.put(self.store.config/'cedar/desktop.json',json.dumps({'wallpaper':'/image.png'}))
        with patch('theming.wallpaper.extract',return_value={'colors':{'green':'#123456'}}):
            plan=engine.preview(self.store,self.options(wallpaper=True,accent='#abcdef'),self.detected())
            self.assertEqual(plan['theme']['tokens']['accent.primary'],'#123456')
    def test_restore_pauses_auto_sync(self):
        from application_theming import dispatch
        options=self.options();plan=engine.preview(self.store,options,self.detected());engine.apply(self.store,options,plan['id'],self.detected())
        dispatch({'action':'restore'},self.store)
        self.assertTrue(self.store.json(self.store.state/'status.json',{})['paused'])
    def test_gtk_preferences_schema_and_lock(self):
        def command(argv):
            if argv[1]=='list-keys':return 'color-scheme\naccent-color\nfont-name\nmonospace-font-name\nicon-theme'
            if argv[1]=='writable':return 'true'
            return ''
        with patch('theming.adapters.shutil.which',return_value='/bin/tool'),patch('theming.adapters.run',side_effect=command):
            ops=adapters.generate(self.store,'gtk4',self.theme)
            self.assertEqual(ops[0]['after']['data'],"'prefer-dark'")
            self.assertTrue(any(o['path'].endswith('accent-color') for o in ops))
        with patch('theming.adapters.shutil.which',return_value='/bin/tool'),patch('theming.adapters.run',side_effect=['color-scheme','false']):
            with self.assertRaises(Conflict):adapters.generate(self.store,'gtk4',self.theme)
    def test_terminal_profile_adapters(self):
        keys='use-theme-colors background-color foreground-color palette cursor-colors-set cursor-background-color cursor-foreground-color highlight-colors-set highlight-background-color highlight-foreground-color'
        def command(argv):
            if argv[1]=='get':return "'2b7c4080-0ddd-46c5-8f23-563fd3ba789d'"
            if argv[1]=='list-keys':return keys.replace(' ','\n')
            if argv[1]=='writable':return 'true'
            return ''
        with patch('theming.adapters.shutil.which',return_value='/bin/tool'),patch('theming.adapters.run',side_effect=command):
            for id in ('gnome-terminal','tilix'):
                ops=adapters.generate(self.store,id,self.theme);self.assertGreaterEqual(len(ops),4)
                self.assertTrue(all('2b7c4080-' in o['path'] for o in ops))
    def test_gsettings_transaction(self):
        values={'/org/test/color':"'dark'"}
        def command(args):
            if args[1]=='read':return values.get(args[2],'')
            if args[1]=='write':values[args[2]]=args[3]
            if args[1]=='reset':values.pop(args[2],None)
            return ''
        op={'kind':'gsettings','app':'test','path':'/org/test/color','before':{'data':"'dark'",'mode':0},'after':{'data':"'light'",'mode':0}}
        with patch('theming.transaction.run',side_effect=command):
            self.store.apply([op]);self.assertEqual(values[op['path']],"'light'");self.store.restore();self.assertEqual(values[op['path']],"'dark'")
if __name__=='__main__':unittest.main()
