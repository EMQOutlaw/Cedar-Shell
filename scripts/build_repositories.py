#!/usr/bin/env python3
"""Rebuild project-owned pacman/dnf repositories from complete stable releases.

Only vMAJOR.MINOR releases containing both native packages are eligible. Every
eligible package is retained; numeric version order makes old-tag reruns safe.
No GitHub settings or remote files are changed by this script. The output is a
fresh GitHub Pages tree, with symlinks materialized for upload-pages-artifact.
"""
import argparse
import hashlib
import html
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
from urllib.parse import urlsplit

VERSION = r'(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)'
TAG = re.compile(r'v(' + VERSION + r')')
ARCH = re.compile(r'cedar-shell-(' + VERSION + r')-([1-9][0-9]*)-any\.pkg\.tar\.zst')
RPM = re.compile(r'cedar-shell-(' + VERSION + r')-([1-9][0-9]*(?:\.fc[0-9]+)?)\.noarch\.rpm')
REPOSITORY = re.compile(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+')


def run(args, **kwargs):
    return subprocess.run([str(arg) for arg in args], check=True, text=True, **kwargs)


def package_kind(name):
    for kind, pattern in (('arch', ARCH), ('rpm', RPM)):
        match = pattern.fullmatch(name)
        if match:
            return kind, match.group(1), match.group(2)
    raise ValueError('Unexpected package filename: ' + name)


def version_key(version):
    if not re.fullmatch(VERSION, version):
        raise ValueError('Invalid release version: ' + version)
    return tuple(map(int, version.split('.')))


def release_assets(releases, required_tag=None):
    """Validate API metadata and choose complete, non-draft, non-prerelease pairs."""
    selected = []
    seen = set()
    if required_tag is not None and not TAG.fullmatch(required_tag):
        raise ValueError('Expected a stable vMAJOR.MINOR tag.')
    for release in releases:
        tag = release.get('tag_name', '')
        match = TAG.fullmatch(tag)
        if release.get('draft') or release.get('prerelease') or not match:
            continue
        if tag in seen:
            raise ValueError('Duplicate release tag: ' + tag)
        seen.add(tag)
        pair = {}
        for asset in release.get('assets', []):
            name = asset.get('name', '')
            if not (name.endswith('.pkg.tar.zst') or name.endswith('.noarch.rpm')):
                continue
            kind, version, _ = package_kind(name)
            if version != match.group(1) or kind in pair:
                raise ValueError('Ambiguous or mismatched package in ' + tag)
            pair[kind] = asset
        if set(pair) == {'arch', 'rpm'}:
            selected.append((tag, pair))
    if required_tag is not None and required_tag not in {tag for tag, _ in selected}:
        raise ValueError('Required release does not contain both native packages: ' + required_tag)
    if not selected:
        raise ValueError('No complete stable native-package releases were found.')
    return sorted(selected, key=lambda item: version_key(item[0][1:]))


def download_releases(repository, destination, required_tag):
    if not REPOSITORY.fullmatch(repository) or any(part in ('.', '..') for part in repository.split('/')):
        raise ValueError('Invalid GitHub owner/repository.')
    # --slurp preserves page boundaries; flatten explicitly, not line-oriented JSON.
    response = run(['gh', 'api', '--paginate', '--slurp', f'repos/{repository}/releases?per_page=100'], capture_output=True)
    pages = json.loads(response.stdout)
    selected = release_assets([release for page in pages for release in page], required_tag)
    destination.mkdir(parents=True, exist_ok=True)
    for tag, pair in selected:
        for asset in pair.values():
            name = asset['name']
            run(['gh', 'release', 'download', tag, '--repo', repository, '--pattern', name, '--dir', destination])
            path = destination / name
            if path.is_symlink() or not path.is_file() or path.stat().st_size != asset['size']:
                raise ValueError('Downloaded asset size differs: ' + name)
            digest = asset.get('digest')
            if digest and digest != 'sha256:' + hashlib.sha256(path.read_bytes()).hexdigest():
                raise ValueError('Downloaded asset digest differs: ' + name)
    return selected


def verify_metadata(path):
    kind, version, release = package_kind(path.name)
    if kind == 'arch':
        result = run(['bsdtar', '-xOf', path, '.PKGINFO'], capture_output=True).stdout
        fields = {}
        for line in result.splitlines():
            key, separator, value = line.partition(' = ')
            if separator:
                fields.setdefault(key, []).append(value)
        expected = {'pkgname': ['cedar-shell'], 'pkgver': [version + '-' + release], 'arch': ['any']}
        if any(fields.get(key) != value for key, value in expected.items()):
            raise ValueError('Arch package metadata disagrees with its filename: ' + path.name)
    else:
        result = run(['rpm', '-qp', '--queryformat', '%{NAME}\n%{VERSION}\n%{RELEASE}\n%{ARCH}\n', path], capture_output=True).stdout
        if result.splitlines() != ['cedar-shell', version, release, 'noarch']:
            raise ValueError('RPM metadata disagrees with its filename: ' + path.name)
    return kind, version


def validate_base_url(url):
    parsed = urlsplit(url)
    if (parsed.scheme != 'https' or not parsed.netloc or parsed.query or parsed.fragment or
            parsed.username or parsed.password or not re.fullmatch(r'https://[A-Za-z0-9./_-]+', url) or
            '..' in parsed.path.split('/')):
        raise ValueError('Repository base URL must be a plain HTTPS URL without credentials/query/fragment.')
    return url.rstrip('/')


def sign(path, key):
    run(['gpg', '--batch', '--yes', '--local-user', key, '--detach-sign', path])


def build(source, output, base_url, signing_key=None):
    base_url = validate_base_url(base_url)
    if signing_key and not re.fullmatch(r'[A-Fa-f0-9]{40,64}', signing_key):
        raise ValueError('Signing key must be a full GPG fingerprint.')
    if output.exists():
        raise ValueError('Output must not already exist: ' + str(output))
    packages = []
    pairs = {}
    for path in sorted(source.iterdir()):
        if path.is_symlink() or not path.is_file():
            raise ValueError('Package inputs must be regular files: ' + path.name)
        kind, version, _ = package_kind(path.name)
        if kind in pairs.setdefault(version, set()):
            raise ValueError('More than one package of a kind for ' + version)
        pairs[version].add(kind)
        packages.append(path)
    if not pairs or any(pair != {'arch', 'rpm'} for pair in pairs.values()):
        raise ValueError('Every version must contain exactly one Arch package and one binary RPM.')
    packages.sort(key=lambda path: (version_key(package_kind(path.name)[1]), path.name))
    for path in packages:
        verify_metadata(path)
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='cedar-repositories-', dir=output.parent) as temporary:
        site = Path(temporary) / 'site'
        arch = site / 'arch/x86_64'
        fedora = site / 'fedora/noarch'
        arch.mkdir(parents=True)
        fedora.mkdir(parents=True)
        copied = []
        for path in packages:
            kind, version, _ = package_kind(path.name)
            target = (arch if kind == 'arch' else fedora) / path.name
            shutil.copy2(path, target)
            if signing_key:
                if kind == 'arch':
                    sign(target, signing_key)
                else:
                    # CI imports a dedicated, unencrypted signing subkey into an isolated GNUPGHOME.
                    run(['rpmsign', '--define', '_gpg_name ' + signing_key, '--define',
                         '__gpg ' + (shutil.which('gpg') or '/usr/bin/gpg'), '--define',
                         '_gpg_path ' + os.environ['GNUPGHOME'], '--addsign', target])
            copied.append({'version': version, 'path': str(target.relative_to(site)),
                           'sha256': hashlib.sha256(target.read_bytes()).hexdigest()})
        database = arch / 'cedar.db.tar.gz'
        # Add oldest first, newest last. repo-add stores one current version, while
        # old payloads remain available to clients with a cached database.
        run(['repo-add', database, *(arch / path.name for path in packages if ARCH.fullmatch(path.name))])
        run(['createrepo_c', '--database', fedora])
        for path in arch.iterdir():
            if path.name.endswith('.old'):
                path.unlink()
            elif path.is_symlink():
                data = path.read_bytes()
                path.unlink()
                path.write_bytes(data)
        if signing_key:
            for name in ('cedar.db.tar.gz', 'cedar.files.tar.gz'):
                sign(arch / name, signing_key)
                shutil.copy2(arch / (name + '.sig'), arch / (name.split('.tar.')[0] + '.sig'))
            run(['gpg', '--batch', '--yes', '--local-user', signing_key, '--armor', '--detach-sign', fedora / 'repodata/repomd.xml'])
            public_key = run(['gpg', '--batch', '--armor', '--export', signing_key], capture_output=True).stdout
            if not public_key:
                raise ValueError('No public key exported for signing fingerprint.')
            (site / 'cedar-signing-key.asc').write_text(public_key)
        signed = bool(signing_key)
        (site / 'cedar.repo').write_text(
            '[cedar]\nname=CEDAR project packages\nbaseurl=' + base_url + '/fedora/noarch\n'
            'enabled=1\ngpgcheck=' + str(int(signed)) + '\nrepo_gpgcheck=' + str(int(signed)) + '\n' +
            ('gpgkey=' + base_url + '/cedar-signing-key.asc\n' if signed else ''))
        (site / 'cedar-pacman.conf').write_text(
            '[cedar]\nSigLevel = ' + ('Required DatabaseRequired' if signed else 'Never') +
            '\nServer = ' + base_url + '/arch/$arch\n')
        (site / 'repositories.json').write_text(json.dumps({
            'latest': max(pairs, key=version_key), 'signing_fingerprint': signing_key,
            'packages': copied}, indent=2, sort_keys=True) + '\n')
        (site / '.nojekyll').touch()
        status = ('Signed with ' + signing_key) if signed else 'UNSIGNED: package signatures are not configured.'
        (site / 'index.html').write_text(
            '<!doctype html><html lang="en"><meta charset="utf-8"><title>CEDAR packages</title>'
            '<h1>CEDAR project package repositories</h1><p>Not official Arch Linux or Fedora repositories.</p><p>' +
            html.escape(status) + '</p><ul><li><a href="cedar-pacman.conf">pacman configuration</a></li>'
            '<li><a href="cedar.repo">dnf configuration</a></li>'
            '<li><a href="repositories.json">Versions and SHA-256 checksums</a></li></ul></html>\n')
        site.rename(output)
    print('Built repositories through ' + max(pairs, key=version_key) + ' at ' + str(output))


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    inputs = parser.add_mutually_exclusive_group(required=True)
    inputs.add_argument('--packages', type=Path, help='directory containing only complete native-package pairs')
    inputs.add_argument('--github', help='download all complete stable releases from owner/repository')
    parser.add_argument('--required-tag', help='fail unless this stable release has both packages (with --github)')
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--base-url', required=True)
    parser.add_argument('--signing-key', help='full fingerprint of a GPG secret key already imported into GNUPGHOME')
    args = parser.parse_args()
    if args.github:
        if not args.required_tag:
            parser.error('--github requires --required-tag')
        with tempfile.TemporaryDirectory(prefix='cedar-downloads-') as temporary:
            source = Path(temporary)
            download_releases(args.github, source, args.required_tag)
            build(source, args.out.resolve(), args.base_url, args.signing_key)
    else:
        if args.required_tag:
            parser.error('--required-tag is only valid with --github')
        build(args.packages.resolve(), args.out.resolve(), args.base_url, args.signing_key)


if __name__ == '__main__':
    main()
