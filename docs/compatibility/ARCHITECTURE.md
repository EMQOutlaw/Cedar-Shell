# Compatibility engine implementation plan

## Existing architecture and risks (inspection before implementation)

`scripts/distribution.py` owns versioned releases, atomic/fsync writes, private
file snapshots, hashes, symlink metadata, operation locking and recovery journals.
`portable_session.py` and `omarchy_session.py` already supervise trial/keep/login
handoffs, protect locks, validate shell IPC and restore providers. Reuse them.
`startup_graph.py` inspects bounded includes without evaluating Lua or shell.
`installer/engine/host.py` provides injectable machine access. Existing installer
facts choose a single environment; compatibility must report simultaneous matches.
The stable/development update resolver in `installer/engine/update.py` stays intact.

Risks: a bundled shell can own authentication and idle; stopping it can strand a
lock or remove sleep protection. An owning service can restart a killed process.
Generated Lua, symlinked Home Manager files and package-owned files are not ordinary
editable files. Unknown IPC, another display, missing facts and changed upstream
versions must block automatic takeover. A process existing is not health evidence.

## Implementation sequence

1. Record pinned upstream research and support matrix.
2. Declarative detection profiles; independent installed/configured/active/
   autostarted/managed evidence, unknowns and multiple matches.
3. Add a coordinator around existing transactions and reviewed session adapters.
   Preview is read-only; approval binds the exact fresh plan digest. Snapshot
   service states and startup evidence before any mutation. Persist intent before
   handoff so a killed coordinator can reconcile the underlying session journal.
4. Add optional conflict-preserving shortcut generation in a separate file.
5. Integrate CLI and Field Station using the existing ServiceRequest pattern.
6. Add optional native Arch and Nix packaging without package installation effects.
7. Fixture failure tests, existing regression suites, QML/offscreen validation,
   release inventory checks and documentation. Do not deploy this branch.

## Responsibilities

`compatibility/profiles/*.json`: data, never arbitrary commands to execute.
`compatibility/detection.py`: evidence collection through Host and startup_graph.
`compatibility/keybindings.py`: desired bindings, conflict decisions and renderers.
`compatibility/adapters.py`: bridge to existing guarded session machinery.
`compatibility/engine.py`: approval, migration manifest, interruption reconciliation,
verified rollback, history and diagnostics. Reuses distribution.Transaction.
`compatibility/cli.py`: user-facing commands, JSON report and explicit approval.
`scripts/compatibility_service.py`: read-only GUI requests and detached terminal
handoff for changes (restoration must survive closing its own shell).

Automatic activation remains version/ownership gated. A declarative detection
signature never grants authority to stop a provider. Unsupported configurations
produce manual-intervention actions. They are not called supported.

Existing installed-session commands and recovery stay available. `rollback` selects
the compatibility manifest only when one is pending/committed; otherwise legacy
release rollback semantics remain. Compatibility never rewrites monitors, input,
application preferences, authentication files or upstream dotfile trees.
