# Update channels: System package, Stable and Development

Open **CEDAR → Field Station → Update CEDAR**.

| Choice | Source | Purpose |
| --- | --- | --- |
| System package | `/usr/share/cedar` | Apply the CEDAR version installed by pacman or dnf to your per-user copy |
| Stable Branch | `main` | Follow the stable source branch on GitHub |
| Development Branch | `dev` | The latest integrated work before promotion to main |

The update screen offers **Development Branch** when Stable is selected,
**Stable Branch** when Development or System package is selected, and
**System package** when either branch is selected. Clicking a choice checks
it immediately. The choices remain available when up to date and after a
failed check; **Try again** retries the selected channel.
The window distinguishes the installed channel from a new selection until
installation succeeds.

Normal updates follow the last successfully installed channel. A failed
fetch or a canceled installation does not record a successful switch.
Returning to main is supported even when its commit or version is older
than the development build. CEDAR settings are retained through the existing
installer and migration rules.

Terminal equivalents:

```sh
cedar installer --update --channel package
cedar installer --update --channel development
cedar installer --update --channel stable
```

Add `--no-gui` to use the terminal installer. Installation still requires
the existing plan approval; choosing a channel does not bypass it.

## System package

A first successful installation started with `cedar installer` from the
system package records the package channel. Adding a package beside an
existing branch installation does not switch its remembered channel; use the
explicit command above to switch.
If the existing installer predates package-channel support, use the
[direct package-installer migration command](INSTALLATION.md#native-packages-arch-and-fedora)
once.

Package delivery and per-user installation are separate steps:

1. Update the `cedar-shell` system package: `sudo pacman -Syu` on Arch/CachyOS,
   `omarchy update` on Omarchy, or `sudo dnf upgrade cedar-shell` on Fedora.
2. Run `cedar installer --update` as your normal desktop user, review the
   plan, and apply the system copy to your own installed CEDAR.

The check reads `/usr/share/cedar`, validates its inventory, copies a verified
snapshot into CEDAR's private update store, and compares actual contents with
`~/.local/share/cedar/current`. It does not run a package manager, download a
release, fetch Git, or modify the system package. A missing or incomplete
package stops the check with guidance. “Up to date” means the per-user copy
matches the system package, not that the package manager has checked for a
newer release. Missing runtime dependencies can still require a package
transaction during the later approved installation stage.

On the remembered package channel, `cedar update` is shorthand for the same
installer update flow. The existing
`cedar update ARCHIVE --signature SIGNATURE --trusted-key PUBLIC_KEY` command
still uses the signed local-archive path. Use `cedar installer --update` for
branch updates.

Switching to Stable or Development changes only the per-user installation;
pacman or dnf continues to own `/usr/share/cedar`. Switch back to **System
package** to use that copy again, even if its version is older. See
[Packages and repositories](PACKAGING.md) for repository setup and the
distinction between a package upgrade and desktop activation.

## Stable and Development checks

The updater fetches an allowlisted branch from the CEDAR repository into
its own Git store and prepares a source snapshot for the resolved commit.
It does not switch branches, reset, stash or merge in your personal checkout.
This also works when the installed CEDAR came from an extracted archive.
Git is required for branch updates.

“Up to date” compares the candidate's actual release contents with the
installed contents. A shared `VERSION` value alone is not sufficient:
development commits can change without a version bump. The selected channel
and commit travel with the installer handoff and are recorded only after
verification, with the installed release they describe.

The updater checks source integrity again before handoff. Fetch failures,
missing branches and changed source snapshots produce actionable errors.
The desktop is changed only by the existing approved installation stage.
If that stage fails after changing the runtime, read its recovery report;
a failed overall installation is not reported as a successful channel switch.

## Branch maintenance

`dev` is the integration branch. Start it from the latest main, merge reviewed
feature work into it, and bring subsequent main changes into it with normal
merges. Promote reviewed changes back to main through pull requests. Merely
opening a pull request does not place its changes in dev.

The branch-selector update is independent of the Strata bar redesign. It must
land on main as well as dev so returning to Stable retains the selector.
Keep visual work in its own draft until its live desktop checks are complete.

The download bootstrap remains distinct: its default installs a published
release with its published checksum. `CEDAR_CHANNEL=development` downloads
the `dev` source archive over HTTPS without a release checksum;
`CEDAR_BRANCH` can explicitly override that bootstrap source branch.
