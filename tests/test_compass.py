"""Compass.js: the launchers' calculator and web-search helper, run under Node."""
from pathlib import Path
import json
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'components/Compass.js').read_text().replace('.pragma library', '')
NODE = shutil.which('node')

def run(expression):
    script = SOURCE + '\nconst out = {};\nfor (const q of process.argv.slice(1)) out[q] = { calc: evaluate(q) && evaluate(q).display, url: urlFor(q) };\nout.search = searchUrl("brave", "a & b"); out.unknown = searchUrl("nope", "x"); out.engines = engines.map(e => e.id);\nprocess.stdout.write(JSON.stringify(out));'
    return json.loads(subprocess.run([NODE, '-e', script, '--', *expression], capture_output=True, text=True, check=True, timeout=20).stdout)

@unittest.skipUnless(NODE, 'node is not installed')
class Compass(unittest.TestCase):
    def test_arithmetic_and_gates(self):
        cases = {'2+2': '4', '1,000*3': '3,000', 'sqrt(2)': '1.41421356237', '20% of 50': '10', '3x4': '12', '2^10': '1,024',
                 '(1+2)*3': '9', '2pi': '6.28318530718', 'log(1000)': '3', 'min(4,2)': '2', '-5+2': '-3', '5 mod 3': '2', '2 ** 8': '256',
                 # Not arithmetic: app names, bare numbers and constants, division by zero.
                 'firefox': None, 'kitty': None, '42': None, 'pi': None, 'e': None, 'xbox': None, 'sin': None, '10/0': None}
        got = run(list(cases))
        for q, want in cases.items():
            self.assertEqual(got[q]['calc'], want, q)

    def test_addresses_and_search(self):
        cases = {'example.com': 'https://example.com', 'https://x.y/z': 'https://x.y/z', 'docs.rs/serde': 'https://docs.rs/serde',
                 'kitty': '', 'hello world': '', 'foo.bar': '', 'file.txt': ''}
        got = run(list(cases))
        for q, want in cases.items():
            self.assertEqual(got[q]['url'], want, q)
        self.assertEqual(got['search'], 'https://search.brave.com/search?q=a%20%26%20b')
        self.assertTrue(got['unknown'].startswith('https://search.brave.com/'), 'unknown engines fall back to the first')
        self.assertEqual(got['engines'][0], 'brave')
        schema = (ROOT / 'components/SettingsSchema.js').read_text()
        for engine in got['engines']:
            self.assertIn('{value:"%s"' % engine, schema, 'every engine is offered in Settings')

if __name__ == '__main__':
    unittest.main()
