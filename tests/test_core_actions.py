"""Core file/recorder handling must act on real, explicitly selected data."""
from pathlib import Path
import importlib.util,json,os,sys,tempfile,unittest
from unittest.mock import patch
SCRIPTS=Path(__file__).resolve().parents[1]/'scripts'
sys.path.insert(0,str(SCRIPTS))
import core_actions as actions
import core_probe as probe
class FileActions(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.path=Path(self.tmp.name)/'a ; $(touch no).png';self.path.write_bytes(b'\x89PNG\r\n\x1a\nexample')
    def test_file_uri_is_decoded_as_data(self):
        self.assertEqual(actions.local_file(self.path.as_uri()),self.path)
        with patch.object(actions.subprocess,'Popen') as launch:
            actions.action({'action':'open-file','path':str(self.path)})
            self.assertEqual(launch.call_args.args[0],['xdg-open',str(self.path)])
    def test_devices_remote_urls_and_unknown_actions_rejected(self):
        for value in ['/dev/null','https://example.org/image.png','file://another-machine/tmp/a',str(self.path.parent)]:
            with self.assertRaises((ValueError,FileNotFoundError)):actions.local_file(value)
        with self.assertRaises(ValueError):actions.action({'action':'exec','path':str(self.path)})
    def test_image_copy_checks_actual_png_bytes(self):
        self.path.write_bytes(b'not an image')
        with patch.object(actions,'run') as run:
            with self.assertRaises(ValueError):actions.action({'action':'copy-image','path':str(self.path)})
            run.assert_not_called()
    def test_stale_recorder_identity_cannot_stop_new_process(self):
        with patch.object(actions,'recording',return_value=[{'pid':123,'startTicks':200}]),patch.object(actions,'run') as run:
            with self.assertRaises(ValueError):actions.action({'action':'stop-recording','pid':123,'startTicks':100})
            run.assert_not_called()
    def test_omarchy_owned_recording_uses_its_finalize_flow(self):
        marker=Path(self.tmp.name)/'recording';marker.write_text('/tmp/video.mp4')
        row={'pid':123,'startTicks':200,'file':'/tmp/video.mp4'}
        with patch.object(actions,'RECORDING_FILE',marker),patch.object(actions,'recording',return_value=[row]),patch.object(actions,'run') as run:
            with patch.object(actions,'omarchy',return_value=True):
                actions.action({'action':'stop-recording','pid':123,'startTicks':200})
            self.assertEqual(run.call_args.args[0],['omarchy','capture','screenrecording','--stop-recording'])
    def test_multiple_recorders_stop_only_the_selected_process(self):
        rows=[{'pid':123,'startTicks':200},{'pid':456,'startTicks':300}]
        with patch.object(actions,'recording',return_value=rows),patch.object(actions,'run') as run,patch.object(actions.os,'pidfd_open',return_value=99) as opened,patch.object(actions.os,'close') as close,patch.object(actions.signal,'pidfd_send_signal') as send:
            with patch.object(actions,'omarchy',return_value=True):
                actions.action({'action':'stop-recording','pid':123,'startTicks':200})
            opened.assert_called_once_with(123);send.assert_called_once_with(99,actions.signal.SIGINT);close.assert_called_once_with(99);run.assert_not_called()
    def test_pid_reuse_during_stop_is_rejected(self):
        with patch.object(actions,'recording',side_effect=[[{'pid':123,'startTicks':200}],[{'pid':123,'startTicks':400}]]),patch.object(actions.os,'pidfd_open',return_value=99),patch.object(actions.os,'close') as close,patch.object(actions.signal,'pidfd_send_signal') as send:
            with self.assertRaises(ValueError):
                actions.action({'action':'stop-recording','pid':123,'startTicks':200})
            send.assert_not_called();close.assert_called_once_with(99)
    def test_package_count_comes_only_from_successful_check(self):
        with patch.object(actions.subprocess,'run') as run:
            run.return_value.returncode=2;run.return_value.stdout='';run.return_value.stderr=''
            self.assertEqual(actions.action({'action':'check-updates'})['count'],0)
            run.return_value.returncode=1;run.return_value.stderr='Unavailable'
            with self.assertRaisesRegex(RuntimeError,'Unavailable'):actions.action({'action':'check-updates'})
    def test_keyboard_led_states_are_not_guessed(self):
        p=Path(self.tmp.name)/'brightness';p.write_text('1\n')
        self.assertEqual(probe.keyboard({'capslock':[p]}),{'capslock':True})
        p.unlink();self.assertEqual(probe.keyboard({'capslock':[p]}),{})
