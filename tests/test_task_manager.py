"""Installer and Field Station integration contracts for the independent monitor."""
from pathlib import Path
import hashlib,json,sys,unittest
from types import SimpleNamespace
ROOT=Path(__file__).resolve().parents[1]
sys.path[:0]=[str(ROOT),str(ROOT/'scripts')]
from installer.engine.steps import add_task_manager_shortcut
class TaskIntegration(unittest.TestCase):
    def host(self,rows,code=0):return SimpleNamespace(which=lambda _:True,run=lambda *a,**k:(code,json.dumps(rows),''))
    def test_existing_shortcut_is_never_replaced(self):
        for row in ({'modmask':65,'key':'Escape'},{'modmask':65,'key':'ESC'},{'modmask':65,'key':'','keycode':9}):
            state={'bindings':[]};message=add_task_manager_shortcut(self.host([row]),state,ROOT)
            self.assertEqual(state,{'bindings':[]});self.assertIn('already assigned',message)
    def test_optional_shortcut_requires_a_successful_live_check(self):
        for rows,code in (([],1),(None,0),(['bad row'],0),([{}],0)):
            state={'bindings':[]};add_task_manager_shortcut(self.host(rows,code),state,ROOT);self.assertEqual(state['bindings'],[])
        state={'bindings':[]};add_task_manager_shortcut(self.host([]),state,ROOT)
        self.assertEqual(state['bindings'][0]['command'],'cedar-task-manager')
        add_task_manager_shortcut(self.host([]),state,ROOT);self.assertEqual(len(state['bindings']),1)
    def test_user_binding_wins_even_if_not_currently_loaded(self):
        state={'bindings':[{'keys':'SHIFT + SUPER + ESCAPE','command':'my-command'}]};before=json.dumps(state)
        add_task_manager_shortcut(self.host([]),state,ROOT);self.assertEqual(json.dumps(state),before)
    def test_overview_body_is_unchanged(self):
        text=(ROOT/'modules/FieldStation.qml').read_text()
        a=text.index('        ColumnLayout {\n            Layout.fillWidth: true\n            visible: root.page === "overview"')
        b=text.index('        Flow {',a)
        self.assertEqual(hashlib.sha256(text[a:b].encode()).hexdigest(),'529c20a9679f512cbdaa0b720bcd1f850eee4704bf728eb922ec230bcbfb7a39')
        self.assertEqual(text.count('text: "Task Manager"'),1)
        self.assertNotIn('StationTasks',text)
        self.assertTrue((ROOT/'services/SystemStats.qml').exists())
    def test_no_production_reference_to_retired_monitor(self):
        for folder,glob in [('modules','*.qml'),('services','*.qml'),('scripts','*.py')]:
            for path in (ROOT/folder).glob(glob):
                text=path.read_text();self.assertNotIn('StationTasks',text,str(path));self.assertNotIn('task_monitor.py',text,str(path))
        self.assertFalse((ROOT/'modules/StationTasks.qml').exists())
        self.assertFalse((ROOT/'scripts/task_monitor.py').exists())
        self.assertNotIn('StationTasks',(ROOT/'modules/qmldir').read_text())
