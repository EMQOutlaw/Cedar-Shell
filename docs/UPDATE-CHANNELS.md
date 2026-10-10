# Stable and Development

Open **CEDAR → Field Station → Update CEDAR**.

| Choice | Git branch | Purpose |
| --- | --- | --- |
| Stable Branch | `main` | The normal update path |
| Development Branch | `dev` | The latest integrated work before promotion to main |

The up-to-date screen still offers **Development Branch** when Stable is
selected, and **Stable Branch** when Development is selected. Clicking the
other branch checks that branch immediately. The same choice remains
available after a failed check; **Try again** retries the selected branch.
The window distinguishes the installed branch from a new selection until
installation succeeds.

Normal updates follow the last successfully installed channel. A failed
fetch or a canceled installation does not record a successful switch.
Returning to main is supported even when its commit or version is older
than the development build. CEDAR settings are retained through the existing
installer and migration rules.

Terminal equivalents:

```sh
cedar installer --update --channel development
cedar installer --update --channel stable
```

Add `--no-gui` to use the terminal installer. Installation still requires
the existing plan approval; choosing a channel does not bypass it.

## How the check works

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
