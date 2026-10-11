# Branches and publishing

- `Outlaw`: personal work and experiments.
- `dev`: integrated changes for testing; selected by Development Branch in the updater.
- `main`: published stable updates; selected by Stable Branch in the updater.

Merge personal changes into dev, test, then merge dev into main to publish.
Every ordinary first-parent commit on main advances the two-part version:
1.3 → 1.4 → 1.5. A merge counts as one publication change, rather than counting
all of its development commits. Release bookkeeping commits do not increment it.
The Publish main workflow validates the source, updates VERSION and package
versions, tags the exact version, and uploads the release archive and checksum.
The desktop still updates only when requested.

If validation or a concurrent push interrupts publishing, rerun Publish main
from Actions. Versions are calculated from the baseline so reruns cannot
increment the same change twice. Archived branch tips are kept under
`archive/2026-10-11/` tags; they are history snapshots, not update channels.
