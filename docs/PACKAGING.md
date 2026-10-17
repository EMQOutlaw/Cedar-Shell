# Packages and repositories

CEDAR's `cedar-shell` packages and repositories are project-owned. They are
not official Arch Linux or Fedora repository inclusion.

**Activation status:** the build and deployment workflow is implemented, but
GitHub Pages has not been enabled or deployed by this work. The URLs below
are for use once the maintainer activates the repository. Package-content
checks do not certify a clean-machine installation or native desktop session.
The existing [release bootstrap and source checkout](INSTALLATION.md#published-release-or-source-checkout)
remain available.

## What installing a package does

Both the Arch package and Fedora RPM contain the same release archive tree
under `/usr/share/cedar`, with `/usr/bin/cedar` and upstream license notices
under `/usr/share/licenses/cedar-shell`. The wrapper runs the system tree's
`scripts/distribution.py`. There are no package hooks or RPM scriptlets to
change your home directory, desktop, services or login configuration.

After installing the package, run `cedar installer` as your desktop user, or
`cedar installer --no-gui` for the terminal flow. The installer shows its plan,
backs up affected files and creates a per-user copy under
`~/.local/share/cedar`. A later package upgrade changes only the system copy;
the [System package update channel](UPDATE-CHANNELS.md#system-package) applies
it to each user's copy through the same installer.

The payload uses Arch's `any` and RPM's `noarch` architecture labels because
it contains QML, Python and assets. The published repository layout and
reviewed package backends currently target x86_64 systems. Runtime availability
still depends on the distribution and enabled repositories; CEDAR never adds
runtime providers automatically. For Fedora, check Hyprland and Quickshell
availability for your release before proceeding. The RPM build uses Fedora
43, not a claim of native runtime certification.

## Configure a repository once it is activated

The default GitHub Pages root is
`https://emqoutlaw.github.io/Cedar-Shell/`. A configured custom Pages domain
changes the root used by the generated configuration.

| Resource | URL under that root |
| --- | --- |
| Arch repository | `arch/x86_64/` |
| Fedora repository | `fedora/noarch/` |
| pacman stanza | `cedar-pacman.conf` |
| dnf repository file | `cedar.repo` |
| Versions, checksums and signing fingerprint | `repositories.json` |
| Public signing key, on signed deployments | `cedar-signing-key.asc` |

### Signing and trust

Use the generated configuration, which reflects whether signing was enabled
for that deployment. For signed repositories, obtain the public key and
compare its **full fingerprint** with the maintainer's independently
published fingerprint before importing it:

```bash
curl -fLO https://emqoutlaw.github.io/Cedar-Shell/cedar-signing-key.asc
gpg --show-keys --with-fingerprint cedar-signing-key.asc
```

After checking the fingerprint, use the commands for your distribution:

```bash
# Arch: replace FULL_FINGERPRINT with the verified fingerprint
sudo pacman-key --add cedar-signing-key.asc
sudo pacman-key --lsign-key FULL_FINGERPRINT

# Fedora
sudo rpm --import cedar-signing-key.asc
```

Without the signing secret, the site is explicitly **unsigned**: the pacman
stanza uses `SigLevel = Never`, and dnf uses `gpgcheck=0` and
`repo_gpgcheck=0`. Adding that configuration accepts unauthenticated packages
from this repository; HTTPS and published checksums do not replace package
signatures. Keep this exception scoped to CEDAR, never disable signature
checks globally. Do not run the key-import commands for an unsigned deployment.

### Arch Linux and CachyOS

Download and inspect the generated stanza before installing it:

```bash
curl -fLO https://emqoutlaw.github.io/Cedar-Shell/cedar-pacman.conf
cat cedar-pacman.conf
sudo install -m 644 cedar-pacman.conf /etc/pacman.d/cedar.conf
```

Add this line once at the end of `/etc/pacman.conf`:

```ini
Include = /etc/pacman.d/cedar.conf
```

Then install and open the per-user installer:

```bash
sudo pacman -Syu cedar-shell
cedar installer
```

On Omarchy, use `omarchy update` for the system update, then
`sudo pacman -S --needed cedar-shell`; its guard reserves system upgrades for
Omarchy's own updater. Run `cedar installer` afterwards as your normal user.

### Fedora

Configure the runtime providers appropriate to your Fedora release first.
Then download and inspect CEDAR's generated repository file:

```bash
curl -fLO https://emqoutlaw.github.io/Cedar-Shell/cedar.repo
cat cedar.repo
sudo install -m 644 cedar.repo /etc/yum.repos.d/cedar.repo
sudo dnf install cedar-shell
cedar installer
```

dnf uses your enabled repositories for dependencies; CEDAR's repository does
not include Hyprland or Quickshell. A missing dependency needs a suitable
provider, not a forced installation that ignores dependencies.

### Direct release downloads

Once the release workflow has produced native assets, download the package
for your distribution and `native-packages.sha256` from the same
[GitHub release](https://github.com/EMQOutlaw/Cedar-Shell/releases). In that
download directory:

```bash
sha256sum --ignore-missing --check native-packages.sha256
```

Install the exact filename you downloaded, for example:

```bash
# Replace VERSION with the release version
sudo pacman -U ./cedar-shell-VERSION-1-any.pkg.tar.zst
# Fedora 43 build
sudo dnf install ./cedar-shell-VERSION-1.fc43.noarch.rpm
```

Release assets are unsigned build outputs. Their checksum verifies the
download against the release's published bytes, not an independent signing
identity. Optional signing applies to the repository copies separately;
normal local-package signature policy may require a signed package instead.
Direct installation does not add a repository for future updates. Run
`cedar installer` after the package transaction.

## Maintainer activation

Before the first deployment:

1. Enable GitHub Pages for this repository with **GitHub Actions** as its
   source. The workflow uses `actions/configure-pages` with `enablement:
   false`; it does not enable Pages itself.
2. Allow deployment through the `github-pages` environment from `main` and
   the intended `v*` tag contexts. Workflow permissions are `contents: write`,
   `pages: write` and `id-token: write`; branch rules must permit the authorized
   release commit and tag push.
3. To sign the repositories, set the Actions secret
   `CEDAR_PACKAGE_SIGNING_KEY` to a dedicated ASCII-armored, **unencrypted**
   private signing key/subkey export. Passphrase-protected keys are not
   supported by this noninteractive workflow. Publish the full fingerprint
   independently for users to verify. Without the secret the deployment is
   unsigned, with the settings described above.
4. Run the release pipeline from an eligible stable tag containing these
   workflows, then check the deployed repository files and a controlled
   package installation before advertising availability.

The signing key is imported into a temporary `GNUPGHOME` on the disposable
runner and removed after indexing. Signing covers Arch packages and both
pacman databases, RPM packages and `repodata/repomd.xml`. The public key is
exported as `cedar-signing-key.asc`. Signed RPM bytes differ from the unsigned
release assets; `repositories.json` records the repository-copy checksums.

## Automatic release synchronization

The workflows accept canonical stable `vMAJOR.MINOR` tags matching `VERSION`.
A push to `main` runs [Publish main](../.github/workflows/publish-main.yml):
it advances the version and Arch, Fedora and Nix recipes together, verifies
the release archive, and pushes the version commit and tag atomically.
It directly calls the reusable [release workflow](../.github/workflows/release.yml)
because a tag pushed with `GITHUB_TOKEN` does not start another push workflow.
Human-pushed tags and a manual dispatch with `release_tag` also use that pipeline.

The release pipeline:

1. Checks the inventory, package versions and selected test suites; builds
   one release archive and verifies its complete contents.
2. Builds the Arch package in `archlinux:base-devel` with `makepkg` and the
   RPM in `fedora:43` with `rpmbuild`, as unprivileged builder users.
3. Extracts the binary packages and checks their file lists, payload hashes,
   executable bits, command wrapper and copied notices against that archive.
4. Attaches the archive/checksum, Arch package/checksummed PKGBUILD/SRCINFO,
   binary RPM/source RPM/spec and `native-packages.sha256` to the release.
5. Collects all published, non-prerelease stable releases with exactly one
   Arch package and one binary noarch RPM. Older incomplete releases are
   skipped; the current release must contain both packages.
6. Rebuilds pacman and dnf metadata, optionally signs the repository copies,
   and deploys the complete site through GitHub Pages.

Collection, indexing and deployment share a concurrency group. Numeric
version ordering keeps an old-tag retry from downgrading the current index;
older payloads remain available for clients with cached metadata. Failed
deployments can be retried by rerunning the workflow or manually dispatching
it with the existing `release_tag`. A rebuild may replace that release's
asset bytes; native build timestamps/toolchains are not promised reproducible.
Historical tags without these workflows are not automatically backfilled.

For local build commands, prerequisites and repository construction without
publishing, see [packaging/README.md](../packaging/README.md). Source checks,
archive checks and fixture tests are separate from the outstanding native
runtime gates in [Release readiness](RELEASE-READINESS.md).
