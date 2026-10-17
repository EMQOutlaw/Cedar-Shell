"""Native-package boundary tests; real makepkg/rpmbuild verification is separate."""
import datetime
import hashlib
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch

from scripts import build_packages as packages
from scripts import build_repositories as repositories
from scripts import publish_version as publish


class ArchiveValidation(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.files = {'VERSION': b'1.8\n', 'scripts/distribution.py': b'print("cedar")\n',
                      'licenses/Omarchy-MIT.txt': b'license\n', 'docs/LICENSES.md': b'licenses\n'}

    def archive(self, extra=None, manifest_change=None):
        manifest = {name: {'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
                    for name, data in self.files.items()}
        if manifest_change:
            manifest_change(manifest)
        path = self.root / 'release.tar.gz'
        entries = [('cedar-shell/' + name, data) for name, data in self.files.items()]
        entries.append(('cedar-shell/ARTIFACT-CONTENTS.json', json.dumps(manifest).encode()))
        if extra:
            entries.append(extra)
        with tarfile.open(path, 'w:gz') as archive:
            for name, data in entries:
                member = tarfile.TarInfo(name)
                member.mode = 0o755 if name.endswith('.py') else 0o644
                member.size = len(data)
                archive.addfile(member, io.BytesIO(data))
        return path

    def test_complete_archive(self):
        version, manifest, raw, modes = packages.archive_info(self.archive())
        self.assertEqual(version, '1.8')
        self.assertEqual(manifest, json.loads(raw))
        self.assertEqual(modes['scripts/distribution.py'], 0o755)

    def test_traversal_duplicate_and_extra_file(self):
        for extra in [('cedar-shell/../escape', b'x'), ('cedar-shell/VERSION', b'9.9'),
                      ('cedar-shell/extra', b'x')]:
            with self.subTest(extra=extra), self.assertRaises(SystemExit):
                packages.archive_info(self.archive(extra=extra))

    def test_wrong_hash_size_and_missing_required_file(self):
        for field, value in [('sha256', '0' * 64), ('bytes', -1)]:
            with self.subTest(field=field), self.assertRaises(SystemExit):
                packages.archive_info(self.archive(manifest_change=lambda manifest: manifest['VERSION'].update({field: value})))
        del self.files['licenses/Omarchy-MIT.txt']
        with self.assertRaises(SystemExit):
            packages.archive_info(self.archive())

    def test_bad_version(self):
        for version in (b'../../evil', b'1.2\ncommand', b'01.2', b'v1.2'):
            self.files['VERSION'] = version
            with self.subTest(version=version), self.assertRaises(SystemExit):
                packages.archive_info(self.archive())

    def test_symlink_rejected(self):
        archive_path = self.root / 'link.tar.gz'
        with tarfile.open(archive_path, 'w:gz') as archive:
            member = tarfile.TarInfo('cedar-shell/link')
            member.type = tarfile.SYMTYPE
            member.linkname = '/etc/passwd'
            archive.addfile(member)
        with self.assertRaises(SystemExit):
            packages.archive_info(archive_path)

    def test_package_payload_must_be_exact(self):
        _, manifest, contents, modes = packages.archive_info(self.archive())
        tree = self.root / 'tree'
        for rel, data in self.files.items():
            dest = tree / 'usr/share/cedar' / rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(data)
            dest.chmod(modes[rel])
        (tree / 'usr/share/cedar/ARTIFACT-CONTENTS.json').write_bytes(contents)
        wrapper = tree / 'usr/bin/cedar'
        wrapper.parent.mkdir(parents=True)
        wrapper.write_text(packages.WRAPPER)
        wrapper.chmod(0o755)
        for rel in packages.LICENSE_FILES:
            target = tree / 'usr/share/licenses/cedar-shell' / Path(rel).name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(self.files[rel])
        with patch.object(packages, 'extract', return_value=tree):
            packages.verify_package(Path('package.pkg.tar.zst'), manifest, contents, modes)
            unexpected = tree / '.unexpected-install-hook'
            unexpected.write_text('not package metadata')
            with self.assertRaises(SystemExit):
                packages.verify_package(Path('package.pkg.tar.zst'), manifest, contents, modes)
            unexpected.unlink()
            wrapper.write_text('#!/bin/sh\nexit 0\n')
            with self.assertRaises(SystemExit):
                packages.verify_package(Path('package.pkg.tar.zst'), manifest, contents, modes)

    def test_rpm_extraction_streams_explicit_uncompressed_format(self):
        package = self.root / 'cedar-shell-1.8-1.fc43.noarch.rpm'
        package.write_bytes(b'rpm fixture')
        destination = self.root / 'extracted'
        destination.mkdir()
        def convert(argv, **kwargs):
            self.assertEqual(argv, ['rpm2archive', '--nocompression', '-'])
            self.assertEqual(kwargs['stdin'].read(), b'rpm fixture')
            with tarfile.open(fileobj=kwargs['stdout'], mode='w') as archive:
                member = tarfile.TarInfo('usr/bin/cedar')
                member.size = 5
                archive.addfile(member, io.BytesIO(b'cedar'))
        with patch.object(packages.shutil, 'which', return_value='/usr/bin/rpm2archive'), \
                patch.object(packages.subprocess, 'run', side_effect=convert):
            tree = packages.extract(package, destination)
        self.assertEqual((tree / 'usr/bin/cedar').read_bytes(), b'cedar')


class RecipesAndVersions(unittest.TestCase):
    def test_current_recipes_agree(self):
        self.assertEqual(packages.check(), [])

    def test_archive_checksum_is_injected_once(self):
        digest = '1' * 64
        text = packages.checksummed_pkgbuild("sha256sums=('SKIP')\n", digest)
        self.assertIn(digest, text)
        with self.assertRaises(SystemExit):
            packages.checksummed_pkgbuild(text, digest)

    def test_all_recipe_versions_and_release_reset(self):
        self.assertEqual(publish.pkgbuild_text('pkgver=1.8\npkgrel=3\n', '1.10'), 'pkgver=1.10\npkgrel=1\n')
        self.assertEqual(publish.nix_text('  version = "1.8";', '1.10'), '  version = "1.10";')
        spec = 'Version:        1.8\nRelease:        3%{?dist}\n%changelog\n* Old entry - 1.8-3\n- Old\n'
        updated = publish.spec_text(spec, '1.10', datetime.date(2026, 10, 17))
        self.assertIn('Version:        1.10', updated)
        self.assertIn('Release:        1%{?dist}', updated)
        self.assertIn('Sat Oct 17 2026', updated)
        self.assertTrue(updated.endswith('* Old entry - 1.8-3\n- Old\n'))
        self.assertEqual(publish.spec_text(updated, '1.10', datetime.date(2026, 10, 18)), updated)

    def test_malformed_recipes_fail(self):
        for rewrite, source in [(publish.pkgbuild_text, 'pkgver=1.8\n'),
                                (publish.nix_text, 'version missing'),
                                (publish.spec_text, 'Version: 1.8\nRelease: 1\n')]:
            with self.subTest(rewrite=rewrite.__name__), self.assertRaises(ValueError):
                rewrite(source, '1.9')
        with self.assertRaises(ValueError):
            publish.pkgbuild_text('pkgver=1.8\npkgrel=1\npkgver=1.8\n', '1.9')


def release(version, kinds=('arch', 'rpm'), **fields):
    names = {'arch': f'cedar-shell-{version}-1-any.pkg.tar.zst',
             'rpm': f'cedar-shell-{version}-1.fc43.noarch.rpm'}
    return {'tag_name': 'v' + version, 'assets': [{'name': names[kind]} for kind in kinds], **fields}


class RepositorySelection(unittest.TestCase):
    def test_numeric_order_and_incomplete_historical_releases(self):
        releases = [release('1.10'), release('1.9'), release('1.8', kinds=('arch',)), release('1.11', prerelease=True)]
        selected = repositories.release_assets(releases, 'v1.9')
        self.assertEqual([tag for tag, _ in selected], ['v1.9', 'v1.10'])
        with self.assertRaises(ValueError):
            repositories.release_assets(releases, 'v1.8')

    def test_duplicate_mismatch_and_required_tag_fail(self):
        for releases in ([release('1.9'), release('1.9')],
                         [dict(release('1.9'), assets=release('1.8')['assets'])],
                         [release('1.9', draft=True)]):
            with self.subTest(releases=releases), self.assertRaises(ValueError):
                repositories.release_assets(releases, 'v1.9')
        with self.assertRaises(ValueError):
            repositories.release_assets([release('1.9')], 'v1.9\nmain')

    def test_unsafe_names_and_urls_fail(self):
        for name in ('../cedar-shell-1.8-1-any.pkg.tar.zst', '-bad.rpm', 'cedar-shell-1.8-1.x86_64.rpm'):
            with self.subTest(name=name), self.assertRaises(ValueError):
                repositories.package_kind(name)
        for url in ('http://example.com', 'https://x/../x', 'https://x/\nmalicious', 'https://a:b@x', 'https://x/?query=1'):
            with self.subTest(url=url), self.assertRaises(ValueError):
                repositories.validate_base_url(url)
        self.assertEqual(repositories.validate_base_url('https://emqoutlaw.github.io/Cedar-Shell/'),
                         'https://emqoutlaw.github.io/Cedar-Shell')

    def test_native_metadata_cannot_disagree_with_filename(self):
        from subprocess import CompletedProcess
        with patch.object(repositories, 'run', return_value=CompletedProcess([], 0, stdout='pkgname = cedar-shell\npkgver = 1.8-1\narch = any\n')):
            self.assertEqual(repositories.verify_metadata(Path('cedar-shell-1.8-1-any.pkg.tar.zst')), ('arch', '1.8'))
            with self.assertRaises(ValueError):
                repositories.verify_metadata(Path('cedar-shell-1.9-1-any.pkg.tar.zst'))
        with patch.object(repositories, 'run', return_value=CompletedProcess([], 0, stdout='cedar-shell\n1.8\n1.fc43\nnoarch\n')):
            self.assertEqual(repositories.verify_metadata(Path('cedar-shell-1.8-1.fc43.noarch.rpm')), ('rpm', '1.8'))

    def test_fresh_indexes_preserve_history_materialize_aliases_and_do_not_overwrite(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / 'packages'
            source.mkdir()
            for version in ('1.10', '1.9'):
                for asset in release(version)['assets']:
                    (source / asset['name']).write_text('fixture ' + asset['name'])
            calls = []
            def native(argv, **kwargs):
                calls.append([str(arg) for arg in argv])
                if argv[0] == 'repo-add':
                    directory = Path(argv[1]).parent
                    for name in ('cedar.db', 'cedar.files'):
                        (directory / (name + '.tar.gz')).write_bytes(b'index fixture')
                        (directory / name).symlink_to(name + '.tar.gz')
                elif argv[0] == 'createrepo_c':
                    directory = Path(argv[-1]) / 'repodata'
                    directory.mkdir()
                    (directory / 'repomd.xml').write_text('<repomd/>')
                else:
                    self.fail('Unexpected native command')
            output = root / 'site'
            with patch.object(repositories, 'verify_metadata'), patch.object(repositories, 'run', side_effect=native):
                repositories.build(source, output, 'https://example.com/Cedar-Shell')
                with self.assertRaises(ValueError):
                    repositories.build(source, output, 'https://example.com/Cedar-Shell')
            manifest = json.loads((output / 'repositories.json').read_text())
            self.assertEqual(manifest['latest'], '1.10')
            self.assertEqual(len(manifest['packages']), 4)
            self.assertIn('1.9-1-any', calls[0][2])
            self.assertIn('1.10-1-any', calls[0][3])
            self.assertFalse(any(path.is_symlink() for path in output.rglob('*')))
            self.assertIn('SigLevel = Never', (output / 'cedar-pacman.conf').read_text())
            self.assertIn('gpgcheck=0', (output / 'cedar.repo').read_text())
            self.assertIn('UNSIGNED', (output / 'index.html').read_text())

    def test_signed_site_requires_package_and_index_signatures(self):
        from subprocess import CompletedProcess
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / 'packages'
            source.mkdir()
            for asset in release('1.9')['assets']:
                (source / asset['name']).write_bytes(b'payload')
            fingerprint = 'A' * 40
            calls = []
            def native(argv, **kwargs):
                argv = [str(arg) for arg in argv]
                calls.append(argv)
                if argv[0] == 'repo-add':
                    directory = Path(argv[1]).parent
                    for name in ('cedar.db', 'cedar.files'):
                        (directory / (name + '.tar.gz')).write_bytes(b'index')
                        (directory / name).symlink_to(name + '.tar.gz')
                elif argv[0] == 'createrepo_c':
                    directory = Path(argv[-1]) / 'repodata'
                    directory.mkdir()
                    (directory / 'repomd.xml').write_text('<repomd/>')
                elif argv[0] == 'rpmsign':
                    path = Path(argv[-1])
                    path.write_bytes(path.read_bytes() + b'signed')
                elif argv[0] == 'gpg':
                    if '--export' in argv:
                        return CompletedProcess(argv, 0, stdout='PUBLIC KEY FIXTURE')
                    suffix = '.asc' if '--armor' in argv else '.sig'
                    Path(argv[-1] + suffix).write_bytes(b'signature')
                else:
                    self.fail('Unexpected signing command')
                return CompletedProcess(argv, 0, stdout='')
            output = root / 'site'
            with patch.object(repositories, 'verify_metadata'), patch.object(repositories, 'run', side_effect=native), patch.dict('os.environ', {'GNUPGHOME': str(root / 'keys')}):
                repositories.build(source, output, 'https://example.com', fingerprint)
            self.assertTrue((output / 'arch/x86_64/cedar.db.sig').is_file())
            self.assertTrue((output / 'arch/x86_64/cedar.files.sig').is_file())
            self.assertTrue((output / 'fedora/noarch/repodata/repomd.xml.asc').is_file())
            self.assertEqual((output / 'cedar-signing-key.asc').read_text(), 'PUBLIC KEY FIXTURE')
            self.assertIn('SigLevel = Required DatabaseRequired', (output / 'cedar-pacman.conf').read_text())
            self.assertIn('repo_gpgcheck=1', (output / 'cedar.repo').read_text())
            manifest = json.loads((output / 'repositories.json').read_text())
            self.assertEqual(manifest['signing_fingerprint'], fingerprint)
            for entry in manifest['packages']:
                self.assertEqual(entry['sha256'], hashlib.sha256((output / entry['path']).read_bytes()).hexdigest())
            self.assertEqual(len([call for call in calls if call[0] == 'rpmsign']), 1)


if __name__ == '__main__':
    unittest.main()
