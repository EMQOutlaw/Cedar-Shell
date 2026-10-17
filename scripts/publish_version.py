#!/usr/bin/env python3
"""Advance the published two-part version for each first-parent main commit.

Release bookkeeping commits do not count. Counting from an immutable baseline
also catches queued pushes and prevents dev's older VERSION from rolling back main.
The Arch PKGBUILD, the Fedora spec and the Nix package follow VERSION.
"""
import datetime
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
PREFIX = 'chore(release): publish CEDAR '
CHANGELOG_IDENTITY = 'CEDAR release automation <41898282+github-actions[bot]@users.noreply.github.com>'
# RPM changelog dates are English whatever the locale.
DAYS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']

def next_version(base, subjects):
    if not re.fullmatch(r'\d+\.\d+', base):
        raise ValueError('Expected a two-part release version')
    major, minor = map(int, base.split('.'))
    return f'{major}.{minor + sum(not subject.startswith(PREFIX) for subject in subjects)}'

def replace_once(pattern, replacement, text):
    changed, count = re.subn(pattern, replacement, text, flags=re.M)
    if count != 1:
        raise ValueError('Expected exactly one version field matching ' + pattern)
    return changed

def validate_version(version):
    if not re.fullmatch(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)', version):
        raise ValueError('Expected a canonical two-part release version')

def pkgbuild_text(text, version):
    validate_version(version)
    text = replace_once(r'^pkgver=.*$', 'pkgver=' + version, text)
    return replace_once(r'^pkgrel=.*$', 'pkgrel=1', text)

def nix_text(text, version):
    validate_version(version)
    return replace_once(r'  version = "[^"\n]+";', f'  version = "{version}";', text)

def changelog_date(day):
    return f'{DAYS[day.weekday()]} {MONTHS[day.month - 1]} {day.day:02d} {day.year}'

def spec_text(text, version, day=None):
    """Set Version, reset Release to 1 and open %changelog with this version (once)."""
    validate_version(version)
    text = replace_once(r'^Version:([ \t]*).*$', lambda m: 'Version:' + m.group(1) + version, text)
    text = replace_once(r'^Release:([ \t]*).*$', lambda m: 'Release:' + m.group(1) + '1%{?dist}', text)
    head, marker, tail = text.partition('%changelog\n')
    if not marker:
        raise ValueError('Expected a %changelog section')
    if re.match(r'\* .* - ' + re.escape(version) + r'-1$', tail.lstrip().split('\n', 1)[0]):
        return text  # A retried publication keeps its existing entry.
    day = day or datetime.datetime.now(datetime.timezone.utc).date()
    entry = f'* {changelog_date(day)} {CHANGELOG_IDENTITY} - {version}-1\n- Automated release {version}\n'
    return head + marker + entry + ('\n' + tail if tail.strip() else tail)

REWRITERS = (('packaging/arch/PKGBUILD', pkgbuild_text), ('packaging/nix/package.nix', nix_text),
             ('packaging/fedora/cedar-shell.spec', spec_text))

def main():
    base = json.loads((ROOT / '.github/release-base.json').read_text())
    subprocess.run(['git', 'merge-base', '--is-ancestor', base['commit'], 'HEAD'], cwd=ROOT, check=True)
    subjects = subprocess.check_output(['git', 'log', '--first-parent', '--format=%s', base['commit'] + '..HEAD'], cwd=ROOT, text=True).splitlines()
    version = next_version(base['version'], subjects)
    # Validate every recipe before modifying any file; missing definitions fail closed.
    updates = [(ROOT / name, rewrite((ROOT / name).read_text(), version)) for name, rewrite in REWRITERS]
    (ROOT / 'VERSION').write_text(version + '\n')
    for path, content in updates:
        path.write_text(content)
    print(version)

if __name__ == '__main__':
    main()
