# Offline recovery

The distribution installs a stable recovery script at `$XDG_DATA_HOME/cedar/recovery/distribution.py` (default `~/.local/share/cedar/recovery/distribution.py`). It needs Python 3, not Quickshell, plugins, internet or a display.

```sh
python3 ~/.local/share/cedar/recovery/distribution.py restore
```

The extracted copy also works: `python3 scripts/distribution.py restore` with the same XDG paths used at installation. `cedar rollback` selects the latest recorded install transaction and restores its previous release pointer. Reinstalling the same candidate creates no extra checkpoint. `cedar uninstall --approve-uninstall` verifies the complete installation history before restoring program entry points to their original state; it retains preferences, release files, backups, stable recovery tooling and all shared packages. No automatic purge is implemented in this development candidate.

Recovery checks every current file against the last recorded CEDAR write before changing anything. Later user edits cause a clear conflict refusal; both the user file and private backup remain. Resolve that conflict deliberately—do not delete the user file blindly. Checksums, original mode, modification timestamp, symlink target and original absence are verified. Journals are under `$XDG_STATE_HOME/cedar/transactions/` with private file permissions. Keep them.

A desktop lock blocks switching/restoration. Unknown lock state also blocks it while a graphical session exists. Recovery does not kill a locker or compositor and does not log out. A TTY is not evidence that another session is unlocked. If an unusable secure lock requires ending a graphical session, unsaved work can be lost; this tool never takes that action automatically.

During an Omarchy trial/session, `cedar restore` restores that desktop integration first. Run it before switching releases or uninstalling. A second restore after the session has been restored applies to the latest program installation transaction. The independent session supervisor and post-boot recovery hook are described in [Omarchy integration](OMARCHY-SESSION.md). The existing Omarchy locker is never stopped by this adapter.

Source rollback does not roll back independently upgraded Qt, Quickshell, GPU drivers or system packages. Package results are recorded separately and never claimed reversible by restoring dotfiles. Omarchy trial/Keep/login startup is implemented experimentally with fixture tests; native device acceptance remains unverified.
