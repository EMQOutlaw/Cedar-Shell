# Development verification — 2026-10-04

These checks ran against the private distribution candidate. They do not certify a public release or native desktop activation.

- Existing and new Python unit suite: 180 tests passed after the Omarchy adapter changes.
- Distribution and recovery suite: 21 tests passed, including failure injection, backup verification, restoration conflicts, repeated-install idempotence, full uninstall-chain preflight, concurrency, archive rejection, private defaults, and custom XDG paths.
- QML syntax parsing: 136 files passed.
- Real offscreen Quickshell import, navigation, identity, and Trailwatch component checks passed. Component loading does not prove authentication or session-lock security.
- Desktop UI fixture checks passed for 16 Settings pages at narrow and wide dimensions and three legacy control tabs.
- Public-file privacy scanner reported no matches. This is a heuristic scan, not proof of absence; staged files and commit metadata still require review before upload.
- Archive contents, hashes, all built-in bundle/integration inventories, Bash entry-point syntax, and extracted distribution/session tests passed. The archive's generated inventory records its exact file count and checksums.
- That exact archive installed successfully into disposable custom XDG locations containing spaces and non-ASCII characters, with actual offscreen QML validation. The active desktop and user preferences were untouched.

The final repository/archive must be rebuilt and rechecked after subsequent changes. No GitHub upload or remote CI result is recorded by these local checks.

The Omarchy adapter adds 23 controlled fixture tests, including timeout/crash recovery, lock-state deferral, protected services, trial → Keep → login → restore transactions, interruption, stale supervisor generations, explicit all-config discovery and upstream API mismatch. Actual offscreen Quickshell validates the bridge and fails closed for missing/stale/invalid external lock status. Production lock-wiring and consolidated navigation regressions also pass. No native handoff was performed against the active desktop to obtain these results.

Not tested here: clean-machine package bootstrapping, Zsh/Fish entry behavior, live desktop takeover, login/reboot, native lock/PAM behavior, real suspend/hotplug, GPU compatibility, external integration acceptance, or measured local-only outbound traffic. See RELEASE-READINESS.md for implementation gaps and release gates.

Development candidate 3 adds eight provider-validation fixtures and an offscreen test of the actual Omacale coordinator against controlled handovers, including in-flight work and binding restoration. The coordinator also loaded against the reviewed real Omacale 0.45.0 QML plus Omarchy Commons in a disposable offscreen environment with external commands unavailable. Reviewed source and a generated Omarchy 4.0.4 lock clone passed the provider check; this did not run authentication. Standalone installed-style CLI refusals, nested-clone/private-file exclusion and interrupted second-stage recovery passed.

Development candidate 4: three additional provider regressions plus the revised inactive-installation regression passed. Enabled lock clones are discovered independently of the selected bar, with the same source/contract validation. This corrects the skipped detection path in candidate 3; it does not certify a native handoff.
