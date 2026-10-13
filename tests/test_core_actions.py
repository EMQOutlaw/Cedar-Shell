"""Core file/recorder handling must act on real, explicitly selected data."""
from pathlib import Path
import importlib.util,io,json,os,sys,tempfile,unittest
from unittest.mock import patch
SCRIPTS=Path(__file__).resolve().parents[1]/'scripts'
sys.path.insert(0,str(SCRIPTS))
import core_actions as actions
import core_probe as probe
class FileActions(unittest.TestCase):
    def test_system_upgrade_opens_interactive_terminal(self):
        with patch.object(actions,'launch') as launch:
            result=actions.action({'action':'upgrade-system'})
        launch.assert_called_once_with('terminal',[sys.executable,str(SCRIPTS/'upgrade_system.py')])
        self.assertEqual(result['action'],'upgrade-system')
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

class ProbeCadence(unittest.TestCase):
    def run_probe(self, leds):
        with patch.object(probe, 'LEDS') as root, patch.object(probe, 'recording', return_value=[]) as recording, patch.object(probe, 'keyboard', return_value={}), patch.object(probe.time, 'sleep', side_effect=[None] * 10 + [KeyboardInterrupt]) as sleep, patch('sys.stdout', new_callable=io.StringIO) as output:
            root.glob.return_value = leds
            with self.assertRaises(KeyboardInterrupt):
                probe.watch()
        return root, recording, sleep, output.getvalue()

    def test_no_leds_sleep_until_recorder_scan_and_rediscover_devices(self):
        root, recording, sleep, output = self.run_probe([])
        self.assertEqual([call.args[0] for call in sleep.call_args_list], [3] * 11)
        self.assertEqual(recording.call_count, 11)
        self.assertEqual(root.glob.call_count, 4)  # Both LEDs at 0 and 30 seconds.
        self.assertEqual(len(output.splitlines()), 1)

    def test_probe_exits_when_the_shell_that_started_it_is_gone(self):
        # Output only flows on change, so a killed shell never breaks the pipe;
        # the probe must notice the reparenting itself rather than poll forever.
        with patch.object(probe, 'LEDS') as root, patch.object(probe, 'recording', return_value=[]), patch.object(probe, 'keyboard', return_value={}), \
             patch.object(probe.os, 'getppid', side_effect=[100, 100, 100, 1]), patch.object(probe.time, 'sleep') as sleep, patch('sys.stdout', new_callable=io.StringIO):
            root.glob.return_value = []
            probe.watch()
        self.assertEqual(sleep.call_count, 2)

    def test_leds_keep_one_second_responsiveness(self):
        root, recording, sleep, output = self.run_probe([Path('/unused/brightness')])
        self.assertEqual([call.args[0] for call in sleep.call_args_list], [1] * 11)
        self.assertEqual(recording.call_count, 4)
        self.assertEqual(root.glob.call_count, 2)
        self.assertEqual(len(output.splitlines()), 1)
