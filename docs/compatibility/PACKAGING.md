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
