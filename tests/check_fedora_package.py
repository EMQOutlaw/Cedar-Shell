#!/usr/bin/env python3
"""Verify a built cedar-shell RPM against the release archive it was built from.

Usage: check_fedora_package.py cedar-shell-VERSION-1.fcNN.ARCH.rpm cedar-VERSION-x86_64.tar.gz

Needs rpm2cpio and cpio (a Fedora container has both). Checks that every archive
file is under /usr/share/cedar byte-for-byte with its executable bit, that no
file was added to that tree except the two Task Manager binaries, that no .pyc
was byte-compiled in, that the wrappers and desktop entry are present, and
that the RPM carries no scriptlets. Exit status 0 means every check passed.
"""
from pathlib import Path
import hashlib, os, subprocess, sys, tarfile, tempfile

def archive_entries(path):
    out = {}
    with tarfile.open(path) as tar:
        for member in tar:
            if not member.isfile(): continue
            rel = member.name.split('/', 1)[1]
            out[rel] = (hashlib.sha256(tar.extractfile(member).read()).hexdigest(), bool(member.mode & 0o100))
    return out

def main(rpm, archive):
    rpm, archive = Path(rpm).resolve(), Path(archive).resolve()
    expected = archive_entries(archive)
    problems = []
    with tempfile.TemporaryDirectory(prefix='cedar-rpm-') as temp:
        subprocess.run('rpm2cpio ' + repr(str(rpm)) + ' | cpio -idm --quiet', shell=True, cwd=temp, check=True)
        tree = Path(temp) / 'usr/share/cedar'
        if not tree.is_dir(): raise SystemExit('No /usr/share/cedar in ' + rpm.name)
        shipped = {str(p.relative_to(tree)): p for p in tree.rglob('*') if p.is_file() or p.is_symlink()}
        for rel, (digest, executable) in expected.items():
            p = shipped.pop(rel, None)
            if p is None: problems.append('missing from the package: ' + rel); continue
            if hashlib.sha256(p.read_bytes()).hexdigest() != digest: problems.append('content differs: ' + rel)
            if bool(p.stat().st_mode & 0o100) != executable: problems.append('executable bit differs: ' + rel)
        extra = sorted(shipped)
        allowed = {'libexec/cedar-taskd', 'libexec/cedar-task-manager'}
        for rel in extra:
            if rel not in allowed: problems.append('not in the archive: ' + rel)
        for rel in allowed:
            if rel not in extra: problems.append('Task Manager binary missing: ' + rel)
            elif not os.access(tree / rel, os.X_OK): problems.append('not executable: ' + rel)
        for rel in ('usr/bin/cedar', 'usr/bin/cedar-task-manager', 'usr/share/applications/cedar-task-manager.desktop', 'usr/share/icons/hicolor/scalable/apps/cedar-shield.svg',
                    'usr/share/licenses/cedar-shell/Omarchy-MIT.txt', 'usr/share/licenses/cedar-shell/LICENSES.md'):
            if not (Path(temp) / rel).is_file(): problems.append('missing: /' + rel)
        wrapper = (Path(temp) / 'usr/bin/cedar').read_text() if (Path(temp) / 'usr/bin/cedar').is_file() else ''
        if 'exec python3 /usr/share/cedar/scripts/distribution.py "$@"' not in wrapper: problems.append('cedar wrapper does not run the system tree')
        if any(p.suffix == '.pyc' for p in Path(temp).rglob('*.pyc')): problems.append('byte-compiled Python was added')
    scripts = subprocess.run(['rpm', '-qp', '--scripts', str(rpm)], capture_output=True, text=True)
    if scripts.returncode == 0 and scripts.stdout.strip(): problems.append('the package carries scriptlets:\n' + scripts.stdout)
    for line in problems: print(line)
    if problems: raise SystemExit(str(len(problems)) + ' problem(s) in ' + rpm.name)
    print(rpm.name + ': ' + str(len(expected)) + ' archive files identical under /usr/share/cedar; Task Manager, wrappers, desktop entry and licenses present; no scriptlets.')

if __name__ == '__main__':
    if len(sys.argv) != 3: raise SystemExit(__doc__)
    main(sys.argv[1], sys.argv[2])
