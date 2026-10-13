# Frontend audit handoff to Claude — 2026-10-13

No backend-owned file was edited by this audit. Existing backend work in the dev
checkout was preserved. Frontend corrections and validation are in
`FRONTEND-STABILITY-AUDIT.md`.

## Confirmed: polkit agent instantiated despite disabled policy

`services/Permission.qml` computes `enabled` from test mode, stage and the Omarchy
adapter, but its `PolkitAgent` object is instantiated unconditionally. The policy
controls the prompt Loader; it does not control registration itself.

Reproduction: start a disposable full `shell.qml` with `CEDAR_TEST=1` while the
existing desktop polkit agent is running. The new shell logs:

```text
failed to register listener: ... An authentication agent already exists for the given subject
failed to register listener on path "/org/cedar/PolkitAgent"
```

The same warning was present in the installed CEDAR session's baseline log. The
temporary full-shell test requested no privileged actions. This is an ownership
contract defect even though the duplicate registration was refused on this desktop.

Required contract: when `Permission.enabled` is false, do not create/register an
agent; `registered` and `active` remain false and no authentication prompt is
claimed. When enabled, retain the existing flow/cancellation/unlock behavior.
Please own the service lifecycle correction and validate both standalone CEDAR
and Omarchy/test-mode ownership, including reload. The existing prompt presentation
suite passes but does not prove this registration contract.

Evidence: local `/tmp/cedar-frontend-audit/native-smoke/runtime.log`; baseline
installed log was read through `qs log --id o1nb1xq6vmt --no-color -t 300`.

## Observed: portal app-ID registration warning

The installed baseline also logged `Could not register app ID: Connection already
associated with an application ID`. No frontend failure was tied to it, and it did
not appear in the disposable full-shell smoke log. Investigate process/application
identity and portal ownership if reproducible; do not infer a frontend redesign
from this warning.

## Contract to clarify: ServiceRequest pending work

`components/ServiceRequest.qml` keeps one pending request behind a running one;
another request replaces that pending request. Latest-value coalescing may be right
for refreshes, but mutations need an explicit caller guarantee or a refusal/queue
contract. No visible failure was reproduced during this frontend audit, so the
request implementation was left untouched. Please distinguish coalescible reads
from must-complete mutations before changing it.

## Integration notes

- The audio visualizer fixes are in the frontend consumers. `services/Pulse.qml`
  is unchanged; each visible/active consumer now acquires and releases once.
- The native full-shell preview needs a fresh external-session status fixture when
  `CEDAR_EXTERNAL_LOCK=1`. Missing status correctly locks out panel access; the
  audit supplied a disposable status file instead of weakening that behavior.
- The existing Settings › System signed-archive workflow and installer branch
  update workflow both remain present. Their trust-policy copy should be reviewed
  by the backend owner if channel semantics change; this audit did not change it.
- Stage the new frontend test and audit documents with the eventual change, then
  regenerate `data/source-files.json` before packaging. No publication was attempted.
