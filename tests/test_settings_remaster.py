"""State integrity checks for Settings' new transactional interactions."""
from pathlib import Path
import importlib.util
import json
import tempfile
import unittest
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[1]
def module(name):
    spec=importlib.util.spec_from_file_location(name,ROOT/'scripts'/f'{name}.py')
    obj=importlib.util.module_from_spec(spec);spec.loader.exec_module(obj);return obj
d=module('desktop');info=module('settings_info');net=module('connections')
class RemasterTransactions(unittest.TestCase):
    def setUp(self):
        temp=tempfile.TemporaryDirectory();self.addCleanup(temp.cleanup)
        self.own=Path(temp.name);p=patch.object(d,'OWN',self.own);p.start();self.addCleanup(p.stop)
        self.state={'input':{'sensitivity':.2},'monitors':[],'bindings':[],'mainDisplay':'DP-2'}
        (self.own/'settings.json').write_text(json.dumps(self.state))
    def test_external_input_change_is_not_overwritten(self):
        with patch.object(d,'snapshot',return_value={'input':{'sensitivity':.7}}),patch.object(d,'install') as install:
            with self.assertRaisesRegex(ValueError,'outside Settings'):d.action({'action':'input','values':{'sensitivity':.4},'expected':{'sensitivity':.2}})
            install.assert_not_called()
    def test_unrelated_external_input_change_is_preserved(self):
        with patch.object(d,'snapshot',return_value={'input':{'sensitivity':.2,'kb_layout':'de'}}),patch.object(d,'install') as install:
            d.action({'action':'input','values':{'sensitivity':.4},'expected':{'sensitivity':.2,'kb_layout':'us'}})
            self.assertEqual(install.call_args.args[0]['input'],{'sensitivity':.4})
    def test_input_reset_keeps_display_and_bindings(self):
        with patch.object(d,'install') as install:
            d.action({'action':'reset-input'})
            saved=install.call_args.args[0]
            self.assertEqual(saved['input'],{});self.assertEqual(saved['mainDisplay'],'DP-2')
    def test_changed_display_geometry_is_not_applied(self):
        live={'name':'DP-2','width':2560,'height':1440,'refreshRate':240,'x':100,'y':0,'scale':1,'transform':0}
        with patch.object(d,'hypr',return_value=[live]),patch.object(d,'install') as install:
            with self.assertRaisesRegex(ValueError,'Displays changed'):d.action({'action':'displays','monitors':[],'expected':[{**live,'x':0}]})
            install.assert_not_called()
    def test_confirmed_replacement_only_matches_reviewed_binding(self):
        bind={'keys':'SUPER + B','arg':'browser','dispatcher':'exec','editable':True}
        with patch.object(d,'snapshot',return_value={'bindings':[bind]}),patch.object(d,'install') as install:
            d.action({'action':'binding','keys':'SUPER+B','command':'kitty','replace':[bind]})
            self.assertEqual(install.call_args.args[0]['bindings'][0]['command'],'kitty')
            install.reset_mock()
            with self.assertRaisesRegex(ValueError,'changed'):d.action({'action':'binding','keys':'SUPER+B','command':'kitty','replace':[{**bind,'arg':'old browser'}]})
            install.assert_not_called()
    def test_callback_replacement_is_rejected(self):
        bind={'keys':'SUPER + B','arg':'callback','dispatcher':'lua','editable':False}
        with patch.object(d,'snapshot',return_value={'bindings':[bind]}),patch.object(d,'install') as install:
            with self.assertRaises(ValueError):d.action({'action':'binding','keys':'SUPER+B','command':'kitty','replace':[bind]})
            install.assert_not_called()
    def test_later_input_override_is_reported(self):
        with patch.object(d,'command',return_value='{"float":0.8}'):
            with self.assertRaisesRegex(ValueError,'later override'):d.verify_inputs({'sensitivity':.3})
        with patch.object(d,'command',return_value='{"float":0.300000001}'):
            d.verify_inputs({'sensitivity':.3})
    def test_vrr_written_only_after_explicit_choice(self):
        live={'name':'DP-2','width':2560,'height':1440,'refreshRate':240,'vrr':False,'availableModes':['2560x1440@240.00Hz']}
        draft={'name':'DP-2','mode':'2560x1440@240.00','x':0,'y':0,'scale':1,'transform':0}
        self.assertNotIn('vrr',d.render({'monitors':d.validate_monitors([draft],[live])}))
        saved=d.validate_monitors([{**draft,'vrrPolicy':2}],[live])
        self.assertIn('["vrr"]=2',d.render({'monitors':saved}))
        with self.assertRaises(ValueError):d.validate_monitors([{**draft,'vrrPolicy':99}],[live])
    def test_mirror_is_validated_and_rendered_in_both_syntaxes(self):
        live=[{'name':n,'width':1920,'height':1080,'refreshRate':60,'availableModes':['1920x1080@60.00Hz']} for n in ('DP-1','DP-2')]
        row=lambda n,**k:{'name':n,'mode':'1920x1080@60.00','x':0,'y':0,'scale':1,'transform':0,**k}
        saved=d.validate_monitors([row('DP-1'),row('DP-2',mirror='DP-1')],live)
        self.assertEqual(saved[1]['mirror'],'DP-1');self.assertNotIn('mirror',saved[0])
        self.assertIn('["mirror"]="DP-1"',d.render_lua({'monitors':saved}))
        self.assertIn('monitor = DP-2, 1920x1080@60.00, 0x0, 1.0, transform, 0, mirror, DP-1',d.render_conf({'monitors':saved}))
        for bad in ([row('DP-1',mirror='DP-1'),row('DP-2')],[row('DP-1',mirror='DP-2'),row('DP-2',mirror='DP-1')],[row('DP-1'),row('DP-2',mirror='HDMI-A-9')]):
            with self.assertRaises(ValueError):d.validate_monitors(bad,live)
    def test_display_profiles_store_data_without_reloading(self):
        live=[{'name':'DP-2','width':2560,'height':1440,'refreshRate':240,'availableModes':['2560x1440@240.00Hz']}]
        layout=[{'name':'DP-2','mode':'2560x1440@240.00','x':0,'y':0,'scale':1,'transform':0}]
        with patch.object(d,'hypr',return_value=live),patch.object(d,'install') as install,patch.object(d,'reload_validate') as reload:
            d.action({'action':'save-profile','name':'Desk','monitors':layout,'mainDisplay':'DP-2'})
            install.assert_not_called();reload.assert_not_called()
            state=json.loads((self.own/'settings.json').read_text())
            self.assertEqual([p['name'] for p in state['displayProfiles']],['Desk'])
            self.assertEqual(state['mainDisplay'],'DP-2');self.assertEqual(state['input'],{'sensitivity':.2})
            self.assertNotIn('Desk',d.render(state))
            with self.assertRaises(ValueError):d.action({'action':'save-profile','name':'bad/name','monitors':layout})
            with self.assertRaises(ValueError):d.action({'action':'save-profile','name':'Other','monitors':[{**layout[0],'name':'DP-9'}]})
            with self.assertRaises(ValueError):d.action({'action':'save-profile','name':'Main','monitors':layout,'mainDisplay':'DP-1'})
            d.action({'action':'delete-profile','name':'Desk'})
            self.assertEqual(json.loads((self.own/'settings.json').read_text())['displayProfiles'],[])
            with self.assertRaises(ValueError):d.action({'action':'delete-profile','name':'Desk'})
    def test_profile_actions_wait_for_display_trial(self):
        (self.own/'pending.json').write_text(json.dumps({'token':'t','deadline':0,'files':{}}))
        with self.assertRaisesRegex(ValueError,'display trial'):d.action({'action':'save-profile','name':'Desk','monitors':[]})
    def test_service_actions_are_whitelisted(self):
        with patch.object(info,'run') as run:
            with self.assertRaises(ValueError):info.action({'action':'restart','unit':'sshd.service'})
            run.assert_not_called()
    def test_health_distinguishes_missing_failed_and_active(self):
        for state,label in [('LoadState=not-found','Unavailable'),('LoadState=loaded\nActiveState=failed','Failed'),('LoadState=loaded\nActiveState=active','Healthy')]:
            with patch.object(info,'run',return_value=state):self.assertEqual(info.service(('PipeWire','pipewire.service',True))['status'],label)
    def test_autoconnect_edits_one_uuid_property(self):
        obj=net.Network.__new__(net.Network)
        with patch.object(obj,'saved',return_value=[{'path':'/connection/1','uuid':'a-b-c'}]),patch.object(net.subprocess,'run') as run:
            run.return_value.returncode=0
            obj.action({'action':'autoconnect','path':'/connection/1','enabled':False})
            self.assertEqual(run.call_args.args[0],['nmcli','connection','modify','uuid','a-b-c','connection.autoconnect','no'])


PAGES=['FirstRunSettings','SettingsOverview','AppearanceSettings','DefaultAppsSettings','DesktopSettingsPage','TopBarSettings','CoreSettings','DisplaySettings','InputSettings','KeybindSettings','ConnectionsPage','HotspotSettings','AudioSettings','NotificationSettings','PowerSettings','TimeSettings','SystemSettings','AboutSettings','WeatherLocationSettings']
class SingleEntryPoints(unittest.TestCase):
    """Settings has one way to reach each place: the sidebar (and search)."""
    def test_pages_do_not_navigate_or_open_other_surfaces(self):
        import re
        pattern=re.compile(r'\bnavigate\(|signal navigate|ShellState\.(toggle|open|lock|settingsPage)|Canopy\.(open|context|toggle)|CoreService\.expand')
        for name in PAGES:
            text=(ROOT/'modules'/f'{name}.qml').read_text()
            self.assertIsNone(pattern.search(text),f'{name} adds a second route to another place')
    def test_each_preference_has_one_custom_control(self):
        import re
        owners={}
        for name in PAGES:
            for key in set(re.findall(r'Config\.set\("(\w+)"',(ROOT/'modules'/f'{name}.qml').read_text())):
                owners.setdefault(key,[]).append(name)
        self.assertEqual({k:v for k,v in owners.items() if len(v)>1},{})
    def test_sidebar_is_the_only_page_navigation(self):
        panel=(ROOT/'modules/SettingsPanel.qml').read_text()
        self.assertNotIn('family-',panel)
        self.assertEqual(panel.count('onClicked:root.navigate('),2)  # sidebar item, search result


class DesktopSingleRoutes(unittest.TestCase):
    """Across the desktop, each place has one visible button."""
    def sources(self):
        return {f.relative_to(ROOT).as_posix():f.read_text() for d in ('modules','components') for f in (ROOT/d).rglob('*.qml')}
    def test_settings_has_one_button(self):
        import re
        route=re.compile(r'ShellState\.(open|toggle)\("settings"\)|settingsPage *=')
        # Canopy's Full Settings; the legacy Control Center replaces Canopy when it is disabled;
        # the network indicator falls back only when Canopy is disabled; Trails replays history.
        allowed={'modules/CanopyPanel.qml','modules/ControlPanel.qml','components/NetworkIndicator.qml','modules/TrailCanopy.qml'}
        found={name for name,text in self.sources().items() if route.search(text) and not name.startswith('modules/Settings')}
        self.assertEqual(found-allowed,set())
    def test_canopy_tabs_skip_destinations_with_bar_buttons(self):
        canopy=(ROOT/'services/Canopy.qml').read_text();panel=(ROOT/'modules/CanopyPanel.qml').read_text()
        self.assertIn('model: Canopy.tabs',panel);self.assertNotIn('text: "Open"',panel)
        for topic in ('"quick"','"network"','"notifications"'):self.assertIn(topic,canopy.split('function barRoute')[1].split('}')[0])
    def test_signals_do_not_carry_navigation(self):
        text=(ROOT/'services/CoreSources.qml').read_text()+(ROOT/'services/CoreService.qml').read_text()
        for label in ('"Connections"','"System settings"','"Notification Center"','"Open update menu"'):self.assertNotIn('label: '+label,text)
    def test_overlays_do_not_link_to_each_other(self):
        self.assertNotIn('toggle("themes")',(ROOT/'modules/WallpaperPicker.qml').read_text())
        station=(ROOT/'modules/FieldStation.qml').read_text()
        self.assertNotIn('toggle("settings")',station);self.assertIn('!Config.moduleEnabled("go")',station)
