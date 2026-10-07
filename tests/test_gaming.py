"""gaming.py: the Lua runtime-config builder and option validation."""
from pathlib import Path
import importlib.util
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('gaming', ROOT / 'scripts/gaming.py')
gaming = importlib.util.module_from_spec(spec); spec.loader.exec_module(gaming)

class LuaConfig(unittest.TestCase):
    def test_nested_tables_per_option(self):
        self.assertEqual(gaming.lua_config({'blur': False}), 'hl.config({ decoration = { blur = { enabled = false } } })')
        self.assertEqual(gaming.lua_config({'animations': True}), 'hl.config({ animations = { enabled = true } })')
        self.assertEqual(gaming.lua_config({'blur': False, 'animations': False}),
                         'hl.config({ decoration = { blur = { enabled = false } }, animations = { enabled = false } })')

    def test_unknown_options_are_refused_before_any_command(self):
        calls = []
        gaming.run = lambda argv, timeout=6: calls.append(argv) or 'ok'
        with self.assertRaises(ValueError): gaming.apply({'opacity': False})
        with self.assertRaises(ValueError): gaming.apply({'blur': 'no'})
        self.assertEqual(calls, [])

if __name__ == '__main__':
    unittest.main()
