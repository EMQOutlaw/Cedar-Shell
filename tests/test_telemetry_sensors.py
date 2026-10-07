"""telemetry.py `sensors`: hwmon discovery the shell reads in-process afterwards."""
from pathlib import Path
import importlib.util
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('telemetry', ROOT / 'scripts/telemetry.py')
telemetry = importlib.util.module_from_spec(spec); spec.loader.exec_module(telemetry)

class Sensors(unittest.TestCase):
    def test_lists_inputs_with_chip_and_label(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            cpu = base / 'hwmon3'; cpu.mkdir(); (cpu / 'name').write_text('k10temp\n')
            (cpu / 'temp1_input').write_text('50250\n'); (cpu / 'temp1_label').write_text('Tctl\n')
            (cpu / 'temp3_input').write_text('35000\n')
            nvme = base / 'hwmon0'; nvme.mkdir(); (nvme / 'name').write_text('nvme\n'); (nvme / 'temp1_input').write_text('32850\n')
            (base / 'hwmon9').mkdir()  # no name file: skipped
            rows = telemetry.sensors(base)
            self.assertEqual([(r['chip'], r['label'], Path(r['path']).name) for r in rows],
                             [('nvme', '', 'temp1_input'), ('k10temp', 'Tctl', 'temp1_input'), ('k10temp', '', 'temp3_input')])

    def test_missing_tree_is_empty(self):
        self.assertEqual(telemetry.sensors(Path('/nonexistent/hwmon')), [])

if __name__ == '__main__':
    unittest.main()
