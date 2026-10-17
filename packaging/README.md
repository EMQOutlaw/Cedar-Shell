# Project-owned Arch and Fedora packages

These are CEDAR's own packages and repositories, **not official Arch Linux or
Fedora repository inclusion**. The workflows are implementation, not evidence
that a hosted repository is already enabled or a desktop installation is tested.

## Payload and activation

Both packages are built from the same `cedar-VERSION-x86_64.tar.gz` release
archive. They install its complete `cedar-shell/` tree byte-for-byte under
`/usr/share/cedar`, including `ARTIFACT-CONTENTS.json`. The only additions are:

- `/usr/bin/cedar`, which executes
  `python3 /usr/share/cedar/scripts/distribution.py "$@"`;
- `/usr/share/licenses/cedar-shell/Omarchy-MIT.txt` and `LICENSES.md`.

There are no install/remove hooks, RPM scriptlets, system services, desktop
entries, login changes, or user configuration writes. Installing or updating a
native package refreshes the system's seed copy; it does not activate or replace
an existing per-user installation. Run `cedar installer` as the desktop user for
explicit per-user setup. See the main installation documentation for lifecycle,
review, recovery, and update-channel choices.

The payload is architecture-independent (`any`/`noarch`); the historical archive
filename still says `x86_64`. The published pacman repository currently targets
x86_64 desktop systems only. Runtime dependencies must be available in the user's
enabled distro repositories. These packages do not install third-party repository
configuration or add COPR/AUR providers. In particular, confirm availability of
Hyprland and Quickshell on the Fedora release you use before installing.

## Release automation

`publish-main.yml` advances `VERSION`, Arch `pkgver/pkgrel`, Fedora
`Version/Release/%changelog`, and the Nix version together, then pushes the
version commit and tag atomically. It calls the reusable `release.yml` directly:
a tag created using `GITHUB_TOKEN` does not start a second push workflow.
Human-created `v*` tags and a manual workflow dispatch also run that pipeline.
Only canonical stable `vMAJOR.MINOR` tags matching `VERSION` are accepted.

The pipeline:

1. Checks source inventory, recipe consistency, tests and the exact shared archive.
2. Builds Arch with `makepkg` in `archlinux:base-devel` and Fedora with `rpmbuild`
   in `fedora:43`, using an unprivileged builder in each disposable container.
   Runtime desktop dependencies are not needed to build this data-only payload.
3. Extracts each native binary package and verifies every payload hash, file list,
   executable bit, wrapper and copied license against the archive manifest.
4. Attaches the archive/checksum, Arch package/checksummed PKGBUILD/SRCINFO,
   binary RPM/source RPM/spec and `native-packages.sha256` to the GitHub release.
5. Collects every published, non-prerelease `vMAJOR.MINOR` release containing
   exactly one Arch package and one binary noarch RPM. Older releases without
   both packages are skipped; the release being processed must be complete.
6. Rebuilds pacman and dnf indexes and deploys the fresh Pages tree. Old package
   payloads remain available for clients using cached indexes. Numeric version
   ordering means retrying an old release cannot downgrade the current index.

Repository collection, indexing and deployment share one concurrency group.
Rerun a failed workflow or dispatch `release.yml` with its existing `release_tag`.
No force-push or tag movement is performed. Rebuilding a tag may replace that
release's asset bytes (native build timestamps/toolchains are not guaranteed
reproducible), but the installed source payload must still match the shared
archive. Historical releases without this workflow are not backfilled
implicitly. Native release assets remain unsigned build outputs; when signing
is enabled, the **repository copies** are signed separately, and their SHA-256
checksums are recorded in `repositories.json`.

## Maintainer setup required before deployment

A repository administrator must enable GitHub Pages with **GitHub Actions** as
its source. The workflow reads that setting with `enablement: false`; it does
not create or enable a site. The `github-pages` environment must permit deployment
from both `main` and the intended `v*` tag contexts. Grant the workflow
`contents: write`, `pages: write` and `id-token: write`; branch rules must also
permit the authorized publication commit/tag push. No Pages settings, secrets,
branch protections or remote releases are changed merely by adding these files.

Set the repository Actions secret `CEDAR_PACKAGE_SIGNING_KEY` to a dedicated
ASCII-armored, **unencrypted** private OpenPGP signing key/subkey export to enable
repository signing. Passphrase-protected keys are not supported by this
noninteractive workflow. Import happens only inside a temporary `GNUPGHOME`,
which is removed after indexing. Never commit the secret. Publish the full
fingerprint independently so users can verify the public key before trusting it.
All packages are re-signed into the new site snapshot: Arch package signatures
and both database signatures, RPM package signatures and `repomd.xml.asc`.
The public key is exported as `cedar-signing-key.asc`.

Without the secret, the generated site is explicitly **unsigned**. Its pacman
stanza uses `SigLevel = Never`; its dnf stanza uses `gpgcheck=0` and
`repo_gpgcheck=0`. HTTPS and checksums do not replace package authentication.
Enable signing before advertising the repository for normal use. Do not change
the generated stanza to require signatures until a signed deployment exists.
Changing or removing a signing key requires communicating the trust change to
users; downloading a key alone does not authenticate its owner.

## Repository URLs and user configuration

For the current GitHub project the default Pages root is:

`https://emqoutlaw.github.io/Cedar-Shell`

A custom Pages domain changes that root automatically through
`actions/configure-pages`'s `base_url`. Check that the deployment exists before
using the URLs; they are not claimed to be live by this document.

| Purpose | Path under the Pages root |
| --- | --- |
| pacman packages/index | `/arch/x86_64/` |
| dnf packages/index | `/fedora/noarch/` |
| Reviewed pacman stanza | `/cedar-pacman.conf` |
| Reviewed dnf repository file | `/cedar.repo` |
| Versions, checksums, signing fingerprint | `/repositories.json` |
| Public key (signed deployments only) | `/cedar-signing-key.asc` |

For a signed deployment, first obtain the public key and verify its fingerprint
against the maintainer's independently published fingerprint. Arch users import
and locally trust the verified key with `pacman-key --add` and
`pacman-key --lsign-key FULL_FINGERPRINT`; Fedora users import it with
`rpm --import`. Then inspect and add the generated pacman stanza to
`/etc/pacman.conf`, or inspect and save `cedar.repo` under
`/etc/yum.repos.d/cedar.repo`. Those are administrator actions, never performed by
the package itself. Use `sudo pacman -Syu cedar-shell` or
`sudo dnf install cedar-shell` after the repository and required runtime providers
are configured. Subsequent distro updates refresh the system seed package only.

For direct downloads, inspect `native-packages.sha256` alongside the release's
native package; the published checksum is not an independent signature.
Arch uses `sudo pacman -U ./cedar-shell-VERSION-1-any.pkg.tar.zst`; Fedora uses
`sudo dnf install ./cedar-shell-VERSION-1.fc43.noarch.rpm`. Dependency availability
and per-user activation requirements still apply.

## Local verification and repository construction

```sh
python3 scripts/build_packages.py check
python3 -m unittest discover -s tests -p test_packaging.py
python3 -m unittest discover -s tests -p test_publish_version.py
python3 scripts/package_release.py --release-assets /tmp/cedar-release
python3 scripts/build_packages.py arch /tmp/cedar-release/cedar-VERSION-x86_64.tar.gz --out /tmp/cedar-arch
python3 scripts/build_packages.py rpm /tmp/cedar-release/cedar-VERSION-x86_64.tar.gz --out /tmp/cedar-rpm
```

Build commands need the native distro tooling (`makepkg`, `fakeroot`, `bsdtar`,
`zstd`, or `rpmbuild` plus an RPM extractor). They do not install dependencies or
modify the host desktop. Use temporary directories or disposable distro
containers; `makepkg` must not run as root.

To construct an unpublished site from a directory containing only complete
native package pairs, with `repo-add`, `bsdtar`, `rpm` and `createrepo_c` available:

```sh
python3 scripts/build_repositories.py --packages /tmp/cedar-native-pairs \
  --out /tmp/cedar-site --base-url https://emqoutlaw.github.io/Cedar-Shell
```

The output path must not already exist. `--github OWNER/REPOSITORY --required-tag
vMAJOR.MINOR` instead downloads the complete published release history using
`gh`. `--signing-key FULL_FINGERPRINT` signs the repository using a key already
imported into an isolated `GNUPGHOME`; this additionally needs `gpg` and
`rpmsign`. These commands produce local files, not an external publication.

Primary references: [GitHub token event semantics](https://docs.github.com/en/actions/how-tos/writing-workflows/choosing-when-your-workflow-runs/triggering-a-workflow),
[reusable workflows](https://docs.github.com/en/actions/how-tos/sharing-automations/reuse-workflows),
[Pages workflow requirements](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages),
[PKGBUILD options](https://man.archlinux.org/man/PKGBUILD.5.en),
[repo-add](https://man.archlinux.org/man/repo-add.8.en), and
[Fedora packaging policy](https://docs.fedoraproject.org/en-US/packaging-guidelines/).
