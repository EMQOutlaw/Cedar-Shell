# Migration from Foxfire to CEDAR

The old source and its active registration remain untouched during installation. CEDAR uses a separate source checkout. The installer verifies the new QML components before migrating user data. Supported settings schemas are the original unversioned schema (0) and CEDAR schema 1; unknown newer schemas stop migration.

`scripts/migrate.py` takes a private lock, backs up both namespaces, stages missing files, validates settings types, then atomically commits each file. A journal records the whole operation; exceptions roll back newly committed files. Existing CEDAR files are never silently replaced, regardless of modification time. Conflicting originals are retained in the archive and listed by relative path in the private journal. Migration is repeatable. Every run has a separate archive; successful repeated migration creates no duplicate data files.

The one setting-value translation is `barStyle: "foxfire"` → `"cedar"`. Every other preference value, including user commands, URLs, unknown keys and custom asset contents, is retained unchanged. The known timer state file moves from the old configuration directory to CEDAR’s state directory. Whisper anti-spam timestamps are read from the retained legacy preference on first launch, then maintained in the state directory. Normal QML preference saves also retain unknown members. Generated compositor configuration and user overrides are copied without changing monitor geometry, scaling, refresh rate, VRR or HDR. On activation, only exact generated/user configuration source paths are redirected.

Archives default to `~/.local/state/cedar-migration/`, or `$XDG_STATE_HOME/cedar-migration/`. This deliberate separate archive location prevents recursive backup copying. Archives are private (0700 directories, 0600 journals). Do not commit them. The original application directory is already a retained recovery copy; it is not deleted or silently replaced.

## Conflicts and changes after installation

If both namespaces exist, inspect `preservedConflicts` in the printed migration journal. It lists relative filenames without printing their contents. Existing CEDAR settings take precedence. The legacy shell can continue saving its own settings while CEDAR is staged: changes made after the migration snapshot require review before activation, not blind overwrite of the CEDAR copy. `cedar migrate` makes another backed-up pass and reports conflicts. The tool does not attempt to merge arbitrary scripts or two independently customized settings files.

## Activation and IPC

`cedar activate` fails closed if the compositor or any running named shell cannot confirm an unlocked session. It validates QML again, journals startup files, removes only recognized legacy theme-hook symlinks, disables the legacy overlap guard, and installs CEDAR hooks and guard. It stops the exact old configuration through its existing `shell stop` IPC method, selects the new theme, and checks CEDAR IPC readiness. A failed handoff restores startup files and the previous theme when unlocked. If locking intervenes, recovery is deferred with a private activation journal; it never kills the locker to finish rollback.

IPC targets/methods (shell, menu, launcher, hud, settings, lock, osd, media, core, canopy and other existing targets) are preserved; the named configuration is now `cedar`. Use `cedar ipc TARGET METHOD …` or `qs -c cedar ipc call TARGET METHOD …`. Old `qs -c foxfire` commands still refer to the retained old installation; they are not aliases that secretly launch a second shell. Update external custom callers explicitly. All bundled callers use the new namespace.

Intentional old-name references are restricted by `data/legacy-allowlist.json` to migration/startup recovery, regression fixtures, and historical documentation. Branded QML types are now `CedarAtmosphere` and `CedarCore`; registrations/imports are updated together. Bar ID `minimal` still represents the visible Full Width style; it was not renamed.

## Recovery and uninstall

To return to the retained old theme, use `cedar rollback` from an unlocked terminal. It restores the latest successful activation's previous theme, exact hook/configuration files, and legacy guard state. It refuses to overwrite integration files edited after activation. Migration data remains available. For an activation interrupted by a lock, unlock and run the same command; inspect its private activation journal if integration files were subsequently edited.

`cedar recover PATH/TO/journal.json` reverses only files created by that migration run whose checksums still match. It refuses while CEDAR is active or lock state is unknown, and preserves any files edited afterward. It never removes original legacy files. Backups can also be inspected or copied manually while both shells are stopped.

After selecting another theme, `cedar uninstall` removes owned registration and integration entries. It does not remove preferences, source, or archives. Cleanup of the original installation is a separate, explicit user action.
