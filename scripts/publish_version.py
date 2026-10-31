#!/usr/bin/env python3
"""Advance the published two-part version for each first-parent main commit.

Release bookkeeping commits do not count. Counting from an immutable baseline
also catches queued pushes and prevents dev's older VERSION from rolling back main.
"""
import datetime
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
PREFIX = 'chore(release): publish CEDAR '

def next_version(base, subjects):
    if not re.fullmatch(r'\d+\.\d+', base):
        raise ValueError('Expected a two-part release version')
    major, minor = map(int, base.split('.'))
    return f'{major}.{minor + sum(not subject.startswith(PREFIX) for subject in subjects)}'

def update_spec(text, version, date=None):
    """The Fedora spec's Version, Release and newest %changelog entry for `version`; unchanged when already there."""
    if re.search(r'^Version:\s+' + re.escape(version) + r'\s*$', text, flags=re.M):
        return text
    date = date or datetime.date.today()
    text = re.sub(r'^Version:(\s+).*$', lambda m: 'Version:' + m.group(1) + version, text, count=1, flags=re.M)
    text = re.sub(r'^Release:(\s+)\d+(.*)$', lambda m: 'Release:' + m.group(1) + '1' + m.group(2), text, count=1, flags=re.M)
    entry = f'* {date:%a %b %d %Y} CEDAR release automation <41898282+github-actions[bot]@users.noreply.github.com> - {version}-1\n- Automated release {version}\n'
    return re.sub(r'^%changelog\n', '%changelog\n' + entry + '\n', text, count=1, flags=re.M).rstrip('\n') + '\n'

def main():
    base = json.loads((ROOT / '.github/release-base.json').read_text())
    subprocess.run(['git', 'merge-base', '--is-ancestor', base['commit'], 'HEAD'], cwd=ROOT, check=True)
    subjects = subprocess.check_output(['git', 'log', '--first-parent', '--format=%s', base['commit'] + '..HEAD'], cwd=ROOT, text=True).splitlines()
    version = next_version(base['version'], subjects)
    (ROOT / 'VERSION').write_text(version + '\n')
    arch = ROOT / 'packaging/arch/PKGBUILD'
    if arch.exists(): arch.write_text(re.sub(r'^pkgver=.*$', 'pkgver=' + version, arch.read_text(), flags=re.M))
    nix = ROOT / 'packaging/nix/package.nix'
    if nix.exists(): nix.write_text(re.sub(r'  version = "[^"]+";', f'  version = "{version}";', nix.read_text()))
    spec = ROOT / 'packaging/fedora/cedar-shell.spec'
    if spec.exists(): spec.write_text(update_spec(spec.read_text(), version))
    print(version)

if __name__ == '__main__':
    main()
