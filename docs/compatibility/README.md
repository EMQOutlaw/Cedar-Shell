# Shell compatibility and migration

Replace the shell, not the compositor. This engine reuses CEDAR's reviewed
session adapters and recovery store; it does not uninstall another desktop,
replace Hyprland, install packages or overwrite monitor/input settings.

## Compatibility matrix

| Environment | Detection | Automatic activation | Evidence / limitation |
|---|---|---|---|
| Plain/custom Hyprland | Installed/configured/active evidence | Experimental portable adapter | Reviewed standalone providers, ownership and lock checks; fixtures, not fresh-machine certification |
| Waybar with standalone daemons | Process, units, startup and packages | Experimental portable adapter | Retains configured Hyprlock and wallpaper; unknown owners/restarting wrappers refused |
| Omarchy | Package, user config and exact running shell | Experimental existing adapter | Reviewed API hashes; resident authentication retained; optional tested Trailwatch handoff |
| Noctalia v4/v5 | Config, packages and running native/QML paths | Experimental existing adapters | Only pinned interfaces (4.7.7 / 5.2.1); current upstream requires matching checks |
| Caelestia | Dots, packages, QML and caelestia.service | Detection/manual review | Bundled lock/idle and updater-owned Lua |
| HyDE | XDG dots and startup references | Detection/manual review | Configurable provider commands and generated data files |
| end-4 | ii profile, dots and startup references | Detection/manual review | Quickshell lock shortcuts and dependent idle/clipboard watchers |
| DankMaterialShell | Config, executable and dms.service | Detection/manual review | Restarting DBus service bundles multiple desktop roles |
| Unknown Quickshell/custom shell | Explicit unknown evidence | Refused | Never select an arbitrary known profile or terminate every qs process |
| Nix/Home Manager configuration | Symlink/store ownership | Declarative/manual integration | No writes through store-backed paths; package/module build not validated here |

No new environment is labelled fully validated. A detection match is not a
promise that a shell can safely be stopped. Multiple installed and active matches
are retained, including an Omarchy installation with a manually added shell.
State flags mean supporting evidence was observed; a false flag is not proof of
absence when a probe or dynamic configuration could not be resolved.
See [upstream research](UPSTREAM.md) and [architecture](ARCHITECTURE.md).

## Commands and approval

Use the installed candidate's `cedar` command:

```sh
cedar compatibility                  # evidence, health, conflicts and preview
cedar status
cedar doctor
cedar migrate --dry-run              # no backup directories or effects
cedar migrate --dry-run --login      # include persistent startup
cedar migrate --login --approve-plan DIGEST_FROM_PREVIEW
cedar migrate                       # prints the plan, then asks in a terminal
cedar start                         # idempotent when healthy; fresh start uses approval
cedar restart                       # only the managed instance, while unlocked
cedar stop                          # restore the recorded original shell
cedar history
cedar rollback --migration ID
```

Legacy `status --adapter …` and `doctor --source …` diagnostics remain available.

The digest binds source contents, selected options, startup evidence, bindings,
provider identities and service states. If these change, review a new preview.
An existing committed migration is not duplicated. `start` never silently adopts
an unrelated running desktop. `restart` uses the existing session supervisor and
never kills an arbitrary PID. Stop/rollback defer on active or uncertain lock state.
Without a compatibility manifest, existing session recovery remains available;
legacy release rollback still requires restoring the session first.

`--trailwatch` uses CEDAR's existing local password and secure-unlock acceptance
checks. Authentication is entered in its local window, never in CLI arguments.
The default preserves the original lock/idle provider. Package discovery and
`cedar dependencies` remain separate from explicitly approved installation.
Locker handoff and persistent login cannot be combined in one compatibility
plan: the login edit needs a fresh review after authentication changes.

## Keybinding choices

```sh
cedar migrate --dry-run --bindings
cedar migrate --bindings --assignments choices.json --dry-run
```

An assignments file maps action IDs to alternate combinations, or `null` to skip:

```json
{"launcher": "SUPER + ALT + L", "terminal": null}
```

Occupied keys are preserved, never automatically unbound. The separate managed
file contains launcher Super+Space, terminal Super+T, browser Super+W, files
Super+E, close Super+Q, fullscreen Super+F, float Super+Alt+Space, focus/move
arrows, workspace numbers and Super+Shift+numbers, scratchpad Super+S,
send-to-scratchpad Super+Alt+S and quick settings Super+Comma **only where free**.
Super+C/X/V are deliberately absent; universal clipboard editing is unsupported.

Computed Lua, keycode/ignore-modifier ambiguity, package ownership, broken links
and unresolved includes require manual review. The generator never replaces a
configuration manager's files. Bindings and login/locker changes currently must
be separate operations, because independent recovery journals must not overlap
on the main compositor file. Restore the binding-only migration before choosing
a different ownership plan. This is a conservative limitation, not an override.

## Recovery and conflicts

Manifests and exact backups live under `$XDG_STATE_HOME/cedar/transactions/`.
Each compatibility journal links its own file snapshots to the session identity
and the adapter's durable journal. Existing atomic writes, fsync, unique backup
names, hash/mode checks and symlink metadata are reused. A coordinator lock
serializes compatibility mutations; supervisors retain their existing lock.

On startup failure the engine asks the recorded adapter to restore, checks prior
provider readiness, verifies relevant unit active/enabled states, and verifies
file contents and compositor errors. If any check fails the state is
`recovery-required`, never a successful rollback. Unrelated unit changes are
not "restored". No entire user service inventory is restarted.

After interruption, run `cedar history`, then `cedar rollback --migration ID`.
The coordinator can recover a session created before its ID was copied back,
using a durable migration-owner token in the underlying session record. Another
session, even at the same source path, cannot be claimed for cleanup.

If files were edited, compare `journal.json`, its `before`/`after` hashes and
private `file-*` copies with the current files. Save your edits separately and
reconcile deliberately; rerun rollback only when its preconditions match. There
is no force-overwrite flag. For offline recovery after ending the graphical
session, the existing [recovery guide](../RECOVERY.md) applies to the nested
adapter journal. The coordinator retains pending status until it can verify
services in a real session; offline file restoration alone is not desktop health.

## Field Station

Field Station → Desktop environment opens the existing Station window's Desktop
page: current/installed shells, health, migration preview, dependencies, history,
restoration, and expandable evidence/conflicts. Apply/restore/restart require a
specific confirmation. Mutations open an independent terminal so rollback can
outlive its own shell window. Password tests keep using the existing local UI.
Repair means a graceful restart and health check, not a settings reset. The
startup/shortcuts selectors invalidate an earlier preview. Expand diagnostics
to review the full exact plan and enter shortcut assignments as JSON; the same
choices are available through the CLI assignments file.

## Packaging and validation

[Packaging](PACKAGING.md) describes Arch and optional Nix/Home Manager support.
[Test coverage](TESTING.md) separates simulated migration tests, real QML checks
and the native matrix still required. Stable/main and development/dev update
selection are unchanged. This branch is not automatically merged or deployed.
