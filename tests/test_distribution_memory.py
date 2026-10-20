"""Release hashing and inventory inspection must not scale RAM with asset size."""
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import tracemalloc
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts import distribution
from installer.engine.update import content_digest


class DistributionMemory(unittest.TestCase):
    def test_large_asset_verifies_with_bounded_python_allocation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'data').mkdir()
            asset = root / 'asset.bin'
            with asset.open('wb') as stream:
                stream.truncate(16 * 1024 * 1024)
            (root / 'data/source-files.json').write_text(json.dumps(['asset.bin']))
            expected = hashlib.sha256()
            for _ in range(256):
                expected.update(bytes(64 * 1024))
            tree_digest = hashlib.sha256(b'asset.bin\0' + expected.digest() + b'0\0').hexdigest()
            tracemalloc.start()
            try:
                self.assertEqual(distribution.files(root), [(asset, Path('asset.bin'))])
                self.assertEqual(distribution.digest(asset), expected.hexdigest())
                self.assertEqual(content_digest(root), tree_digest)
                _, peak = tracemalloc.get_traced_memory()
            finally:
                tracemalloc.stop()
            self.assertLess(peak, 2 * 1024 * 1024, 'Release validation retained an asset-sized Python allocation')


if __name__ == '__main__':
    unittest.main()
