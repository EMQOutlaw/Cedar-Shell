import importlib.util,io,json,os,subprocess,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('audio_instruments',ROOT/'scripts/audio_instruments.py')
audio=importlib.util.module_from_spec(spec);spec.loader.exec_module(audio)

class AudioInstruments(unittest.TestCase):
    def fixture(self):
        return dict(outputs=[dict(id=1,name='speakers',label='Speakers',volume=.5,muted=False)],inputs=[],streams=[dict(id=3,serial='42',app='browser',label='Browser',output=1,volume=.6)],default='speakers',microphone='',scenes=[])
    def test_stale_stream_never_moves_a_reused_id(self):
        with patch.object(audio,'snapshot',return_value=self.fixture()),patch.object(audio,'run') as run:
            with self.assertRaises(ValueError):audio.handle(dict(action='route',stream=3,serial='old',output='speakers'))
            run.assert_not_called()
    def test_routes_real_stream_by_validated_identity(self):
        with patch.object(audio,'snapshot',return_value=self.fixture()),patch.object(audio,'run') as run:
            audio.handle(dict(action='route',stream=3,serial='42',output='speakers'))
            run.assert_called_once_with('move-sink-input','3','speakers')
    def test_disconnected_scene_does_not_partially_change_audio(self):
        data=self.fixture();data['scenes']=[dict(name='Night',output=dict(name='missing',volume=.4,muted=False),microphone=None,streams=[])]
        with patch.object(audio,'snapshot',return_value=data),patch.object(audio,'run') as run:
            with self.assertRaises(ValueError):audio.handle(dict(action='apply-scene',name='Night'))
            run.assert_not_called()
    def test_scene_snapshots_real_values_private_file(self):
        with tempfile.TemporaryDirectory() as tmp,patch.dict(os.environ,{'XDG_CONFIG_HOME':tmp}),patch.object(audio,'snapshot',return_value=self.fixture()):
            audio.handle(dict(action='save-scene',name='Music'))
            data=audio.scenes()[0]
            self.assertEqual(data['output']['volume'],.5)
            self.assertEqual(data['streams'][0]['output'],'speakers')
            self.assertEqual(audio.scene_path().stat().st_mode & 0o777,0o600)
    def test_invalid_volume_rejected(self):
        for value in [float('nan'),float('inf'),-1,2]:
            with self.assertRaises(ValueError):audio.bounded(value)

if __name__=='__main__':unittest.main()
