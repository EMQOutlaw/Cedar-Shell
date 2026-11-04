"""Regression coverage for ownership, rollback, conflicts and untrusted values."""
from pathlib import Path
import importlib.util
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[1]
import sys
sys.path.insert(0,str(ROOT/'scripts'))  # desktop.py imports sibling helpers (portable_providers)
spec=importlib.util.spec_from_file_location('desktop',ROOT/'scripts/desktop.py')
d=importlib.util.module_from_spec(spec); spec.loader.exec_module(d)

# These four run the generated Lua through a real interpreter. `lua` is a test-only tool (CEDAR never
# executes Lua itself; Hyprland does): Arch has it, Fedora needs `dnf install lua`. Skip, never guess.
needs_lua = unittest.skipUnless(shutil.which('lua'), 'lua interpreter not installed (test-only validator)')

class WindowsValues(unittest.TestCase):
    def test_windows_rejects_unknown_out_of_range_and_bad_types(self):
        self.assertRaises(ValueError, d.validate_windows, {'bogus': 1})
        self.assertRaises(ValueError, d.validate_windows, {'gaps_in': 500})
        self.assertRaises(ValueError, d.validate_windows, {'gaps_in': 2.5})
        self.assertRaises(ValueError, d.validate_windows, {'blur_enabled': 'yes'})
        self.assertRaises(ValueError, d.validate_windows, {'layout': 'tall'})
        self.assertRaises(ValueError, d.validate_windows, {'rounding_power': 99})
        out = d.validate_windows({'gaps_in': 5, 'blur_enabled': True, 'layout': 'master', 'rounding_power': 2.0})
        self.assertEqual(out, {'gaps_in': 5, 'blur_enabled': True, 'layout': 'master', 'rounding_power': 2.0})
    def test_windows_shadow_offset_positional_and_passthrough(self):
        # both axes owned: a positional literal, no compositor read
        lines = d.render_windows({'windows': {'shadow_offset_x': 4, 'shadow_offset_y': -2}})
        self.assertEqual(lines, ['hl.config({["decoration"]={["shadow"]={["offset"]={4, -2}}}})'])
        # one axis owned: companion resolved from live config at load time,
        # never baked in (upstream changes to the unowned axis must survive)
        lines = d.render_windows({'windows': {'shadow_offset_x': 4}})
        self.assertEqual(len(lines), 1)
        self.assertIn('hl.get_config("decoration.shadow.offset") or {0, 0}', lines[0])
        self.assertIn('["offset"]={4, __cedar_off[2]}', lines[0])
        lines = d.render_windows({'windows': {'shadow_offset_y': 1.75}})
        self.assertIn('["offset"]={__cedar_off[1], 1.75}', lines[0])
    def test_windows_color_normalization(self):
        self.assertEqual(d.parse_color('#A1B2C3'), (['ffa1b2c3'], 0))
        self.assertEqual(d.parse_color('rgba(a1b2c3ff)'), (['ffa1b2c3'], 0))
        self.assertEqual(d.parse_color('rgba(161,178,195,0.5)'), (['80a1b2c3'], 0))
        self.assertEqual(d.parse_color('ff9dffb0 ff3fe0c5 45deg'), (['ff9dffb0','ff3fe0c5'], 45))
        self.assertEqual(d.parse_color('ee1a1a1a 0deg'), (['ee1a1a1a'], 0))
        self.assertEqual(d.parse_color('0xA1B2C3D4'), (['a1b2c3d4'], 0))
        self.assertRaises(ValueError, d.parse_color, 'red')
        self.assertEqual(d.norm_color('#A1B2C3'), '0xffa1b2c3')
        self.assertEqual(d.norm_color('ee1a1a1a 0deg'), '0xee1a1a1a')
        self.assertEqual(d.norm_color('ff9dffb0 ff3fe0c5 45deg'),
                         {'colors': ['0xff9dffb0','0xff3fe0c5'], 'angle': 45})
        self.assertEqual(d.parse_color('rgba(ee1a1a1a)'), (['1aee1a1a'], 0))  # rgba() reads RRGGBBAA; stops are AARRGGBB
    def test_windows_css_uniform(self):
        self.assertEqual(d.css_uniform('5'), 5)
        self.assertEqual(d.css_uniform('5 5 5 5'), 5)
        self.assertEqual(d.css_uniform('5 10 5 10'), '5 10 5 10')
    def test_windows_render_groups_and_shadow_merge(self):
        state = {'windows': {'gaps_in': 5, 'blur_enabled': True, 'blur_size': 6,
                             'shadow_offset_x': 4, 'shadow_offset_y': -2,
                             'col_active_border': 'ff3fe0c5', 'snap_enabled': True,
                             'animations_enabled': True, 'rounding': 8}}
        lines = d.render_windows(state)
        self.assertEqual(len(lines), 2)  # grouped config + positional offset line
        text = lines[0]
        for wanted in ['"general"', '"gaps_in"]=5', '"decoration"', '"blur"]', '"size"]=6',
                       '"col"]', '"active_border"]="0xff3fe0c5"',
                       '"snap"]', '"animations"]', '"rounding"]=8']:
            self.assertIn(wanted, text, wanted)
        self.assertNotIn('shadow_offset_x', text)
        self.assertEqual(lines[1], 'hl.config({["decoration"]={["shadow"]={["offset"]={4, -2}}}})')
        # gradient colours render as a table; solids as exact-byte 0xAARRGGBB
        state2 = {'windows': {'col_active_border': {'colors': ['0xff9dffb0','0xff3fe0c5'], 'angle': 45},
                              'shadow_color': '0xff1a1a1a'}}
        text2 = d.render_windows(state2)[0]
        self.assertIn('"colors"]={', text2)
        self.assertIn('"0xff9dffb0"', text2)
        self.assertIn('"angle"]=45', text2)
        self.assertIn('"0xff1a1a1a"', text2)

    def test_windows_live_rejects_missing_fields(self):
        # An empty/malformed getoption reply must be an error, never a default.
        with patch.object(d, 'command', return_value='{}'):
            values, errors = d.windows_live()
        self.assertEqual(values, {})
        self.assertIn('blur_enabled', errors)
        self.assertEqual(len(errors), len(d.WINDOWS))
        # bool options may report as a real JSON bool rather than int
        def fake(cmd):
            option = cmd[-1]
            if option == 'decoration.blur.enabled':
                return '{"option": "decoration.blur.enabled", "bool": true, "set": true}'
            return '{}'
        with patch.object(d, 'command', side_effect=fake):
            values, errors = d.windows_live()
        self.assertEqual(values, {'blur_enabled': True})
        self.assertNotIn('blur_enabled', errors)
        self.assertIn('blur_size', errors)
        # legacy int 0/1 accepted; strings, arrays, fractional ints rejected
        def typed(cmd):
            return {'decoration.blur.enabled': '{"bool": "false"}',
                    'general.resize_on_border': '{"bool": []}',
                    'decoration.blur.size': '{"int": 1.5}',
                    'decoration.blur.vibrancy': '{"float": "high"}',
                    'decoration.shadow.enabled': '{"int": 1}'}[cmd[-1]]
        with patch.object(d, 'command', side_effect=typed):
            values, errors = d.windows_live()
        self.assertEqual(values, {'shadow_enabled': True})
        for bad in ('blur_enabled', 'resize_on_border', 'blur_size', 'blur_vibrancy'):
            self.assertIn(bad, errors, bad)
    def test_windows_render_empty_state_writes_nothing(self):
        self.assertEqual(d.render_windows({'windows': {}}), [])
        self.assertEqual(d.render_windows({}), [])
class Values(unittest.TestCase):
    @needs_lua
    def test_lua_strings_roundtrip_without_execution(self):
        value='"\\\n; os.execute("false"); -- café\x00'
        encoded=d.lua(value)
        script='local s='+encoded+'; for i=1,#s do io.write(string.byte(s,i)," ") end'
        result=subprocess.run(['lua','-'],input=script,text=True,capture_output=True,check=True)
        self.assertEqual(bytes(map(int,result.stdout.split())),value.encode())
    def test_input_rejects_unknown_and_nonfinite(self):
        for data in [{'exec':'oops'},{'sensitivity':float('nan')},{'repeat_rate':1.5},{'numlock_by_default':'false'},{'kb_layout':'us"; evil()'}]:
            with self.assertRaises((ValueError,TypeError)): d.validate_inputs(data)
    @needs_lua
    def test_nested_touchpad_is_valid_lua(self):
        text=d.render({'input':{'touchpad:tap-to-click':True,'kb_layout':'us'}})
        r=subprocess.run(['lua','-'],input='hl={on=function() end,exec_cmd=function() end,config=function(c) assert(c.input.touchpad["tap-to-click"]==true) end}\n'+text,text=True,capture_output=True)
        self.assertEqual(r.returncode,0,r.stderr)
    @needs_lua
    def test_cedar_starts_with_hyprland_unless_turned_off(self):
        script='started=nil hl={config=function() end,exec_cmd=function(c) started=c end,on=function(e,f) if e=="hyprland.start" then f() end end}\n'
        r=subprocess.run(['lua','-'],input=script+d.render_lua({})+'\nassert(started:find("cedar_session.py start",1,true))',text=True,capture_output=True)
        self.assertEqual(r.returncode,0,r.stderr)
        self.assertIn('exec-once = python3 ', d.render_conf({})); self.assertIn('cedar_session.py start', d.render_conf({}))
        self.assertNotIn('cedar_session', d.render_lua({'sessionStart': False})+d.render_conf({'sessionStart': False}))
    def test_monitors_cannot_drop_output_or_inject_mode(self):
        current=[{'name':'DP-1','width':1920,'height':1080,'refreshRate':60,'availableModes':['1920x1080@60.00Hz']}]
        with self.assertRaises(ValueError): d.validate_monitors([],current)
        with self.assertRaises(ValueError): d.validate_monitors([{'name':'DP-1','mode':'os.execute()'}],current)
        item={'name':'DP-1','mode':'1920x1080@60.00','scale':1.25,'x':0,'y':0,'transform':0}
        self.assertEqual(d.validate_monitors([item],current)[0]['scale'],1.25)
    def test_keys_canonicalized(self):
        self.assertEqual(d.validate_combo('shift + super + f'),'SUPER + SHIFT + F')
        with self.assertRaises(ValueError): d.validate_combo('SUPER + " ; os.execute()')

class Transactions(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name); self.main=self.root/'hypr/hyprland.lua'; self.main.parent.mkdir()
        self.original='-- personal config\n'; self.main.write_text(self.original)
        self.own=self.root/'cedar/hypr'; self.own.mkdir(parents=True)
        self.patches=[patch.object(d,'MAIN',self.main),patch.object(d,'OWN',self.own),patch.object(d,'CONFIG',self.root)]
        for p in self.patches: p.start(); self.addCleanup(p.stop)
        self.state={'input':{'sensitivity':.25},'monitors':[],'bindings':[]}
    def test_first_install_only_appends_and_keeps_user_file(self):
        user=self.own/'user.lua'; user.write_text('-- never rewrite me')
        with patch.object(d,'reload_validate'): d.install(self.state)
        self.assertTrue(self.main.read_text().startswith(self.original))
        self.assertEqual(user.read_text(),'-- never rewrite me')
        with patch.object(d,'reload_validate'): d.install(self.state)
        self.assertEqual(self.main.read_text().count('-- CEDAR graphical settings'),1)
    def test_failed_reload_restores_config(self):
        with patch.object(d,'reload_validate',side_effect=RuntimeError('bad config')):
            with self.assertRaises(RuntimeError): d.install(self.state)
        self.assertEqual(self.main.read_text(),self.original)
        self.assertFalse((self.own/'generated.lua').exists())
    def test_snapshot_reports_a_running_monitor_manager(self):
        """hyprmoncfgd re-applies its own layout and silently undoes CEDAR's
        trial; the snapshot must surface it so the page can say so."""
        from unittest.mock import Mock
        def base(running):
            return [patch.object(d,'hypr',return_value=[]), patch.object(d,'command',side_effect=lambda args: '' if 'udevadm' in args else '{}'),
                    patch.object(d,'windows_live',return_value=({},{})),
                    patch.object(d.subprocess,'run',side_effect=lambda args,**k: Mock(returncode=0 if running and 'hyprmoncfgd' in args else 1))]
        for running in (True, False):
            patches = base(running)
            for p in patches: p.start()
            try:
                self.assertEqual(d.snapshot()['displayManager']['active'], running)
            finally:
                for p in patches: p.stop()

    def test_display_manager_reports_dormant_hyprmoncfg_wiring(self):
        """The daemon off is not the same as the threat gone: hyprmoncfg's
        loader line and rules file stay in MAIN and dofile() on every reload.
        The snapshot must report the dormant wiring and whether it currently
        overrides CEDAR's rules (Lua: whoever loads last wins)."""
        from unittest.mock import Mock
        cedar = '-- CEDAR graphical settings (user overrides load last).\n'
        def probe(pgrep_hits):
            return [patch.object(d,'hypr',return_value=[]), patch.object(d,'command',side_effect=lambda args: '' if 'udevadm' in args else '{}'),
                    patch.object(d,'windows_live',return_value=({},{})),
                    patch.object(d.subprocess,'run',side_effect=lambda args,**k: Mock(returncode=0 if 'hyprmoncfgd' in args and pgrep_hits else 1))]
        self.main.write_text(cedar + 'do local path = os.getenv("HOME") .. "/.config/hypr/hyprmoncfg-monitors.lua"; local file = io.open(path, "r"); if file then file:close(); dofile(path) end end\n')
        (self.root/'hypr').mkdir(exist_ok=True); (self.root/'hypr'/'hyprmoncfg-monitors.lua').write_text('-- Generated by hyprmoncfg\n')
        # Rules load after CEDAR: dormant, and overriding.
        patches = probe(False)
        for p in patches: p.start()
        try:
            state = d.snapshot()['displayManager']
            self.assertTrue(state['dormant'] and not state['active'], 'dormant wiring is reported with the daemon off')
            self.assertIn('AFTER', state['detail'])
            self.assertIn('hyprmoncfg-monitors.lua', state['detail'])
        finally:
            for p in patches: p.stop()
        # Rules load before CEDAR's marker: CEDAR wins today, but the wiring
        # is still reported so the next run of the tool is not a surprise.
        # Byte-identical to the real hyprmoncfg-written loader (this machine's
        # ~/.config/hypr/hyprland.lua), so production detection cannot miss
        # the real shape.
        self.main.write_text('do local path = os.getenv("HOME") .. "/.config/hypr/hyprmoncfg-monitors.lua"; local file = io.open(path, "r"); if file then file:close(); dofile(path) end end' + '\n' + cedar)
        patches = probe(False)
        for p in patches: p.start()
        try:
            state = d.snapshot()['displayManager']
            self.assertTrue(state['dormant'], 'the wiring is reported whichever order loads')
            self.assertIn('after it', state['detail'])
        finally:
            for p in patches: p.stop()
        # A comment mentioning the filename is not a loader line (reviewbot):
        # a leftover note above CEDAR's marker must not read as overriding.
        self.main.write_text('-- removed hyprmoncfg-monitors.lua here\ndo local p = "x"\n' + cedar)
        patches = probe(False)
        for p in patches: p.start()
        try:
            self.assertFalse(d.snapshot()['displayManager']['dormant'], 'a comment mention is not wiring')
        finally:
            for p in patches: p.stop()
        # The daemon running is the active shape, whatever MAIN says (the QML
        # ternary branches on it).
        patches = probe(True)
        for p in patches: p.start()
        try:
            state = d.snapshot()['displayManager']
            self.assertTrue(state['active'] and not state['dormant'], 'a running daemon is active, not dormant')
        finally:
            for p in patches: p.stop()
        # An unreadable MAIN is reported honestly, never a clean all-clear
        # (skipped as root: chmod 000 does not stop root from reading).
        if os.geteuid() != 0:
            self.main.write_text(cedar)
            self.main.chmod(0o000)
            patches = probe(False)
            for p in patches: p.start()
            try:
                state = d.snapshot()['displayManager']
                self.assertTrue(state['detail'] != '' and not state['dormant'] and not state['active'],
                                'an unreadable MAIN says so instead of clearing')
            finally:
                for p in patches: p.stop()
                self.main.chmod(0o600)
            self.main.chmod(0o600)
        # No wiring, daemon off: nothing to report.
        patches = probe(False)
        for p in patches: p.start()
        try:
            state = d.snapshot()['displayManager']
            self.assertFalse(state['dormant'] or state['active'] or state['detail'], 'no manager, no wiring: honest all-clear')
        finally:
            for p in patches: p.stop()

    def test_display_rollback_survives_shell_and_preserves_new_user_edits(self):
        with patch.object(d,'reload_validate'),patch.object(d.subprocess,'Popen') as process:
            result=d.install(self.state,True)
            self.assertTrue(process.call_args.kwargs['start_new_session'])
            self.main.write_text(self.main.read_text()+'-- user edit during trial\n')
            d.restore_pending('wrong-token')
            self.assertTrue((self.own/'pending.json').exists())
            d.restore_pending(result['pending']['token'])
        self.assertEqual(self.main.read_text(),self.original+'-- user edit during trial\n')
        self.assertFalse((self.own/'generated.lua').exists())
    def test_conflicting_binding_is_not_written(self):
        with patch.object(d,'snapshot',return_value={'bindings':[{'keys':'SUPER + F','description':'Files','submap':''}]}):
            with self.assertRaisesRegex(ValueError,'Files'):
                d.action({'action':'binding','keys':'SUPER + F','command':'kitty'})
        self.assertFalse((self.own/'generated.lua').exists())
    def test_rollback_completes_when_main_vanishes_mid_trial(self):
        """Round 9: a MAIN removed during the trial must not abort the
        automatic rollback — MAIN is recreated from the backup, the other
        files and pending state are restored and the reload runs."""
        with patch.object(d,'reload_validate'),patch.object(d.subprocess,'Popen'):
            result = d.install(self.state, True)
            backup_text = json.loads((self.own/'pending.json').read_text())['files'][str(self.main)]
            self.main.unlink()
            d.restore_pending(result['pending']['token'])
        self.assertEqual(self.main.read_text(), backup_text)
        self.assertFalse((self.own/'pending.json').exists())

    def test_keep_cannot_save_expired_trial(self):
        with patch.object(d,'reload_validate'),patch.object(d.subprocess,'Popen'):
            result=d.install(self.state,True)
            file=self.own/'pending.json'; pending=json.loads(file.read_text()); pending['deadline']=0; file.write_text(json.dumps(pending))
            d.action({'action':'keep','token':result['pending']['token']})
        self.assertFalse((self.own/'generated.lua').exists())
    def test_trial_rollback_reproduces_the_trial_effective_config(self):
        """Review: Revert undoes the loader move even when the user appended an
        unrelated comment during the trial — the comment survives, the block
        returns to the line it originally occupied."""
        with patch.object(d,'reload_validate'): d.install(self.state)
        self.main.write_text(self.main.read_text()+'-- pinning tool block\n')
        with patch.object(d,'reload_validate'),patch.object(d.subprocess,'Popen'):
            result = d.install(self.state, True)
            self.assertTrue(self.main.read_text().rstrip().endswith(d.loader().strip()))  # the trial runs with CEDAR last
            self.main.write_text(self.main.read_text()+'-- user comment during trial\n')
            d.restore_pending(result['pending']['token'])
        rolled = self.main.read_text()
        self.assertIn('-- user comment during trial', rolled)               # the edit survives
        self.assertIn('-- pinning tool block', rolled)
        self.assertLess(rolled.index('-- CEDAR graphical settings'), rolled.index('-- pinning tool block'))  # original ordering restored

    def test_non_display_install_never_moves_the_loader(self):
        """Review: only display transactions may reorder MAIN — an input or
        shortcut apply must never silently change which monitor rules win."""
        with patch.object(d,'reload_validate'): d.install(self.state)
        self.main.write_text(self.main.read_text()+'-- pinning tool block\n')
        with patch.object(d,'reload_validate'): d.install({**self.state,'input':{'sensitivity':.2}})
        text = self.main.read_text()
        self.assertLess(text.index('-- CEDAR graphical settings'), text.index('-- pinning tool block'))  # ordering untouched

    def test_crlf_main_survives_a_trial_byte_exact(self):
        """Round 8: newline-preserving reads end to end — a CRLF hyprland.lua
        comes back byte-identical from a trial, and a newline-only concurrent
        edit is treated as a user edit (the rollback leaves it alone)."""
        with patch.object(d,'reload_validate'): d.install(self.state)
        crlf = self.main.read_text().replace('\n', '\r\n')
        self.main.write_bytes(crlf.encode())
        with patch.object(d,'reload_validate'),patch.object(d.subprocess,'Popen'):
            result = d.install(self.state, True)
            self.assertTrue(any(self.main.read_bytes().endswith(v.encode()) for v in d._loader_variants()))
            d.restore_pending(result['pending']['token'])
        self.assertEqual(self.main.read_bytes(), crlf.encode())  # zero CRLF sequences lost

    def test_crlf_conversion_during_a_trial_counts_as_a_user_edit(self):
        with patch.object(d,'reload_validate'): d.install(self.state)
        with patch.object(d,'reload_validate'),patch.object(d.subprocess,'Popen'):
            result = d.install(self.state, True)
            edited = self.main.read_bytes().replace(b'\n', b'\r\n')
            self.main.write_bytes(edited)
            d.restore_pending(result['pending']['token'])
        self.assertEqual(self.main.read_bytes(), edited)  # the user's newline change outranks the undo

    def test_rollback_replays_trial_edits_onto_the_original_ordering(self):
        """Review: trial-time edits before/around the relocated block — a
        deleted leading comment, a prepended Lua comment — must replay onto
        the pre-Apply ordering without commenting the loader out."""
        with patch.object(d,'reload_validate'): d.install(self.state)
        # an original leading comment that the trial deletes, and a pinning block after the loader
        self.main.write_text('-- original leading comment\n' + self.main.read_text() + '-- pinning tool block\n')
        with patch.object(d,'reload_validate'),patch.object(d.subprocess,'Popen'):
            result = d.install(self.state, True)
            edited = self.main.read_text().replace('-- original leading comment\n', '') + '-- prepended\n-- lua comment\n'
            self.main.write_text('-- prepended\n-- lua comment\n' + edited)  # delete leading comment AND prepend two lines
            d.restore_pending(result['pending']['token'])
        rolled = self.main.read_text()
        self.assertIn('-- prepended\n-- lua comment\n', rolled)             # user lines survive, at the top
        self.assertNotIn('-- original leading comment', rolled)             # their deletion survives
        # the loader runs uncommented and in its original place (before the pinning block)
        self.assertLess(rolled.index('-- CEDAR graphical settings'), rolled.index('-- pinning tool block'))
        import re as _re
        self.assertTrue(_re.search(r'(?m)^-- CEDAR graphical settings', rolled))  # uncommented
        self.assertNotIn('-- lua comment\n-- CEDAR graphical settings', rolled)   # never swallowed by a user comment

    def test_unmappable_rollback_leaves_main_and_completes(self):
        """A trial-time rewrite that cannot be mapped back leaves MAIN as the
        user wrote it; the rollback still completes and the warning is logged."""
        with patch.object(d,'reload_validate'): d.install(self.state)
        self.main.write_text(self.main.read_text()+'-- pinning tool block\n')
        with patch.object(d,'reload_validate'),patch.object(d.subprocess,'Popen'):
            result = d.install(self.state, True)
            self.assertTrue(self.main.read_text().rstrip().endswith(d.loader().strip()))  # a real relocation happened
            self.main.write_text('-- completely rewritten by the user\n')
            d.restore_pending(result['pending']['token'])
        self.assertEqual(self.main.read_text(), '-- completely rewritten by the user\n')
        self.assertFalse((self.own/'pending.json').exists())
        self.assertTrue((self.own/'backups'/'rollback-warnings.log').exists())  # the unmappable history is reported

    def test_unterminated_append_during_trial_is_not_concatenated(self):
        """Review: relocation → an append with no trailing newline → Revert.
        The documented rejection: MAIN stays byte-identical to what the user
        wrote (the partial line at EOF) and the warning is logged."""
        with patch.object(d,'reload_validate'): d.install(self.state)
        self.main.write_text(self.main.read_text()+'-- pinning tool block\n')
        with patch.object(d,'reload_validate'),patch.object(d.subprocess,'Popen'):
            result = d.install(self.state, True)
            before_rollback = self.main.read_text() + '-- partial line without newline'
            self.main.write_text(before_rollback)
            d.restore_pending(result['pending']['token'])
        self.assertEqual(self.main.read_bytes(), before_rollback.encode())  # MAIN untouched, nothing concatenated
        self.assertFalse((self.own/'pending.json').exists())
        self.assertTrue((self.own/'backups'/'rollback-warnings.log').exists())  # the rejection is reported

    def test_loader_is_moved_behind_a_later_monitor_pinning_block(self):
        """A tool that appends its own monitor rules after CEDAR's loader would
        override every display change on reload (hyprmoncfg, seen live). A
        display install leaves CEDAR's loader as the last thing MAIN runs."""
        with patch.object(d,'reload_validate'): d.install(self.state)
        self.main.write_text(self.main.read_text()+'-- Added by hyprmoncfg: its generated monitor rules load last.\ndofile(os.getenv("HOME") .. "/.config/hypr/hyprmoncfg-monitors.lua")\n')
        with patch.object(d,'reload_validate'),patch.object(d.subprocess,'Popen'): d.install(self.state, True)
        text=self.main.read_text()
        self.assertTrue(text.rstrip().endswith(d.loader().strip()),'the CEDAR loader must run last')
        self.assertEqual(text.count('-- CEDAR graphical settings'),1)
        self.assertIn('hyprmoncfg', text)  # the user's other tool is preserved, only outranked
    def test_rollback_cleans_a_repositioned_loader_without_eating_edits(self):
        with patch.object(d,'reload_validate'): d.install(self.state)
        self.main.write_text(self.main.read_text()+'-- Added by tool\n')
        with patch.object(d,'reload_validate'): d.install(self.state)
        d.restore({str(self.main): self.original})  # a pre-CEDAR backup: the loader must go
        text=self.main.read_text()
        self.assertNotIn('-- CEDAR graphical settings', text)
        self.assertIn('-- Added by tool', text)
        self.assertEqual(text, self.original+'-- Added by tool\n')  # no separator residue


class PrimaryDisplay(unittest.TestCase):
    setUp = Transactions.setUp
    def test_primary_verification_failure_undoes_the_relocation(self):
        """Round-6: a cursor/X11 verification failure AFTER install() must undo
        the loader relocation too, exactly like a trial revert."""
        with patch.object(d,'reload_validate'): d.install(self.state)
        self.main.write_text(self.main.read_text()+'-- pinning tool block\n')
        before_apply = self.main.read_text()
        with patch.object(d,'hypr',return_value=[{'name':'DP-2'}]), patch.object(d,'command',return_value='{"str":"DP-1"}'), \
             patch.object(d,'reload_validate'), patch.dict(d.os.environ,{'DISPLAY':''}):
            with self.assertRaisesRegex(ValueError,'override'):
                d.apply_primary({**self.state,'mainDisplay':'DP-2'}, 'DP-2')
        self.assertEqual(self.main.read_text(), before_apply)

    @needs_lua
    def test_primary_render_preserves_layout_and_runs_x11_only_on_login(self):
        state={**self.state,'mainDisplay':'DP-2'}
        text=d.render(state)
        lua_test='''
local startup
hl={
 config=function(c) if c.cursor then assert(c.cursor.default_monitor=="DP-2") end end,
 on=function(event, callback) assert(event=="hyprland.start"); startup=callback end,
 exec_cmd=function(command) assert(command=="xrandr --output DP-2 --primary") end,
 monitor=function() error("Primary selection must not change layout") end
}
'''+text+'\nassert(startup); startup()\n'
        result=subprocess.run(['lua','-'],input=lua_test,text=True,capture_output=True)
        self.assertEqual(result.returncode,0,result.stderr)
    def test_disconnected_primary_does_not_write(self):
        with patch.object(d,'hypr',return_value=[{'name':'DP-1'}]):
            with self.assertRaisesRegex(ValueError,'disconnected'): d.apply_primary(self.state,'DP-2')
        self.assertFalse((self.own/'generated.lua').exists())
    def test_x11_primary_parser(self):
        self.assertEqual(d.x11_outputs('DP-1 connected primary 3440x1440+0+0\nDP-2 connected 2560x1440+3440+0\nHDMI-A-1 disconnected'),(['DP-1','DP-2'],'DP-1'))
    def test_x11_failure_restores_files_and_previous_primary(self):
        calls=[]
        def command(args):
            calls.append(args)
            if args==['xrandr','--query']: return 'DP-1 connected primary 3440x1440+0+0\nDP-2 connected 2560x1440+3440+0'
            if args==['xrandr','--output','DP-2','--primary']: raise RuntimeError('x11 failed')
            if 'getoption' in args: return '{"str":"DP-2"}'
            return ''
        with patch.object(d,'hypr',return_value=[{'name':'DP-2'}]), patch.object(d,'command',side_effect=command), patch.object(d,'reload_validate'), patch.object(d.shutil,'which',return_value='/usr/bin/xrandr'), patch.dict(d.os.environ,{'DISPLAY':':0'}):
            with self.assertRaisesRegex(RuntimeError,'x11 failed'): d.apply_primary(self.state,'DP-2')
        self.assertEqual(self.main.read_text(),self.original)
        self.assertFalse((self.own/'generated.lua').exists())
        self.assertIn(['xrandr','--output','DP-1','--primary'],calls)
    def test_wayland_only_session_saves_cursor_with_clear_x11_status(self):
        with patch.object(d,'hypr',return_value=[{'name':'DP-2'}]), patch.object(d,'command',return_value='{"str":"DP-2"}'), patch.object(d,'reload_validate'), patch.dict(d.os.environ,{'DISPLAY':''}):
            result=d.apply_primary(self.state,'DP-2')
        self.assertIn('X11 is unavailable',result['message'])
        self.assertEqual(json.loads((self.own/'settings.json').read_text())['mainDisplay'],'DP-2')

if __name__=='__main__': unittest.main()
