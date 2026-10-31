# Distribution packaging

Runtime logic never invokes a package manager. Dependency discovery reuses
`data/dependencies.json`; the existing installer asks separately before any
package transaction. No recipe enables a service, changes PAM, rewrites
Hyprland or uninstalls another shell during package installation.

## Arch and derivatives

`packaging/arch/PKGBUILD` is a local source-archive recipe. Build the reviewed
archive with `python3 scripts/package_release.py cedar-0.1.3.tar.gz`, place it
next to the recipe, generate/review its checksum using `updpkgsums`, then run
`makepkg`. `SKIP` is only a local-development placeholder, not a verified
release checksum. Review the dependency plan on the actual distribution.
The recipe installs a command and read-only sources under `/usr/share/cedar`.
Prepare the per-user versioned runtime with `cedar install --source
/usr/share/cedar --plan`, then its explicitly approved install. Preview migration
before activating. System package files are never migration write targets.

First-party CEDAR source/artwork are unlicensed by the owner's existing decision.
The recipe therefore uses `custom:unlicensed`. It is not an AUR submission or
permission to redistribute. Existing third-party notices remain in the archive.
Only recipe syntax/metadata are checked here; no native package was installed.

## Fedora

`packaging/fedora/cedar-shell.spec` builds a project-owned RPM from the same
`cedar-VERSION-x86_64.tar.gz` release archive. It is not an official Fedora
package and there is no hosted dnf repository. The payload is the archive's
`cedar-shell/` tree byte-for-byte under `/usr/share/cedar` (shebangs are not
rewritten and no `.pyc` is added), plus the Task Manager compiled from the
archive's own sources into `/usr/share/cedar/libexec/`, the `cedar` and
`cedar-task-manager` wrappers, the Task Manager desktop entry and icon, and
the third-party license notices. There are no scriptlets, services or login
changes; `cedar installer`, run by the user, does the per-user activation.

Build it on Fedora (or in a disposable `fedora:44` container):

```bash
sudo dnf install rpm-build gcc-c++ pkgconf-pkg-config python3 qt6-qtbase-devel qt6-qtdeclarative-devel desktop-file-utils cpio
python3 scripts/package_release.py --release-assets /tmp/cedar-release
mkdir -p ~/rpmbuild/SOURCES && cp /tmp/cedar-release/cedar-*-x86_64.tar.gz ~/rpmbuild/SOURCES/
rpmbuild -bb packaging/fedora/cedar-shell.spec
python3 tests/check_fedora_package.py ~/rpmbuild/RPMS/x86_64/cedar-shell-*.rpm /tmp/cedar-release/cedar-*-x86_64.tar.gz
```

`tests/check_fedora_package.py` extracts the RPM and checks every archive file
against `/usr/share/cedar` (content and executable bit), that nothing but the
two Task Manager binaries was added there, that the wrappers, desktop entry
and licenses are present and that the package carries no scriptlets.
`tests/test_packaging.py` keeps the spec's `Version`, the PKGBUILD's `pkgver`
and the Nix version equal to `VERSION`, and every `Requires`/`Recommends` a
name from `data/dependencies.json`'s `fedoraPackage` column.
`scripts/publish_version.py` advances the spec with the other recipes.

The `fedora-package` job in `.github/workflows/validate.yml` runs exactly
that build and check in a `fedora:44` container on every push; the
`fedora-rpm` job in `release.yml` attaches the RPM and its `.sha256` to the
GitHub release. The RPM is an unsigned build output and its build is not
guaranteed byte-reproducible; the installed payload is verified against the
archive. `hyprland` is in Fedora's own repositories (dist-git f39–f43).
`quickshell` 0.3 or newer is not: Fedora 42 and 43 ship none and Fedora 44+
ships a 0.2.1 git snapshot below the verified runtime, so the spec carries
`Requires: quickshell >= 0.3`, the dnf backend and `install.sh` compare the
candidate version (`dnf repoquery --qf %{version}`) with the manifest's
`versionFloors` before installing, and the `cedar` CLI's dnf plan does the
same. `hypridle` (Fedora 40/41 only) and `hyprsunset` (never packaged) are
`fedoraPackage: null` with a `fedoraNote`: reported absent, installed only
when a repository the user enabled provides them, weak dependencies in the
spec. rpm-ostree hosts (`/run/ostree-booted`) are refused everywhere. Package
names were checked against Fedora's package database (mdapi/dist-git,
Fedora 43). No native Fedora desktop session or clean-machine package
installation has been certified by these checks.

Fedora runtime paths beside the Arch ones (Arch behaviour unchanged):
`scripts/distribution.py` reads `fedoraPackage` on dnf hosts and runs
`sudo dnf install` without a system upgrade (`--approve-system-upgrade` is
pacman's consent only); Station's update check runs `dnf check-update`
(exit 100 = updates) where `checkupdates` is absent; updater guidance says
`sudo dnf install …` with Fedora names; Proton VPN's install opens Proton's
own Fedora steps instead of `pacman`; Topgrade falls back to `cargo install`.

## Nix (optional)

The root flake exports a package and `homeManagerModules.default`. Nix is not
required on Arch. No flake lock is invented; generate/review one with Nix when
adopting the input. The derivation uses the same explicit source inventory as
release archives, supplies runtime command and Qt paths, and marks the package
unfree because no redistribution license has been selected.

```nix
{
  imports = [ inputs.cedar.homeManagerModules.default ];
  programs.cedar.enable = true;
  # Optional only after a reviewed kept migration with login selected:
  # programs.cedar.resumeAtLogin = true;
}
```

The module installs tools only by default. It never adds imperative activation
hooks, disables someone else's service or writes through Home Manager symlinks.
`resumeAtLogin` resumes an already approved session through CEDAR's existing
recovery helper; it cannot initialize a migration unattended. Ensure the user
manager receives WAYLAND_DISPLAY and HYPRLAND_INSTANCE_SIGNATURE via the session
manager. Avoid enabling both this service and an imperative login hook without
reviewing the startup plan; CEDAR's runtime remains singleton-guarded.

Generated Hyprland files require a declarative user include or a separately
reviewed adapter. CEDAR reports these ownership boundaries rather than replacing
Nix store links. A Nix build, Home Manager evaluation and native NixOS session
handoff have **not** been run here (Nix is unavailable); the integration remains
experimental and requires those checks on a Nix runner.
