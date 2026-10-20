#!/usr/bin/env python3
"""Compare release inventory/hash allocations with a local Git revision.

Optional development microbenchmark. No network, installed files or desktop
changes. Peak RSS here belongs to one isolated benchmark worker, not the shell
process group; use measure_resources.py for the runtime acceptance budget.
"""
import argparse
import importlib.util
import json
from pathlib import Path
import resource
import subprocess
import sys
import tempfile
import time
import tracemalloc

ROOT = Path(__file__).resolve().parents[1]


def worker(module_path, fixture):
    spec = importlib.util.spec_from_file_location('distribution_benchmark', module_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    tracemalloc.start()
    started = time.perf_counter()
    rows = module.files(Path(fixture))
    checksum = module.digest(rows[0][0])
    seconds = time.perf_counter() - started
    peak = tracemalloc.get_traced_memory()[1]
    tracemalloc.stop()
    return {'seconds': seconds, 'python_peak_bytes': peak,
            'process_peak_rss_kib': resource.getrusage(resource.RUSAGE_SELF).ru_maxrss,
            'sha256': checksum}


def benchmark(reference, size_mib, runs):
    commit = subprocess.check_output(['git', 'rev-parse', '--verify', '--end-of-options', reference + '^{commit}'],
                                     cwd=ROOT, text=True).strip()
    with tempfile.TemporaryDirectory(prefix='cedar-release-benchmark-') as directory:
        fixture = Path(directory)
        (fixture / 'data').mkdir()
        (fixture / 'data/source-files.json').write_text('["asset.bin"]')
        with (fixture / 'asset.bin').open('wb') as stream:
            stream.truncate(size_mib * 1024 * 1024)
        baseline = fixture / 'baseline.py'
        baseline.write_bytes(subprocess.check_output(['git', 'show', commit + ':scripts/distribution.py'], cwd=ROOT))
        results = {}
        for label, module in (('before', baseline), ('after', ROOT / 'scripts/distribution.py')):
            results[label] = [json.loads(subprocess.check_output(
                [sys.executable, str(Path(__file__).resolve()), '--worker', str(module), str(fixture)],
                cwd=ROOT, text=True, timeout=120)) for _ in range(runs)]
        hashes = {row['sha256'] for rows in results.values() for row in rows}
        if len(hashes) != 1:
            raise RuntimeError('Validation hashes differ between benchmark runs')
        return {'reference_commit': commit, 'asset_bytes': size_mib * 1024 * 1024,
                'metrics': 'Python traced allocations and worker peak RSS; not shell process-group PSS', **results}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reference', help='local Git revision containing the original implementation')
    parser.add_argument('--size-mib', type=int, default=64)
    parser.add_argument('--runs', type=int, default=3)
    parser.add_argument('--worker', nargs=2, help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.worker:
        result = worker(*args.worker)
    else:
        if not args.reference or not 1 <= args.size_mib <= 512 or not 1 <= args.runs <= 20:
            parser.error('require --reference, --size-mib in 1..512, and --runs in 1..20')
        result = benchmark(args.reference, args.size_mib, args.runs)
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
