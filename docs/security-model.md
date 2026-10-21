# CEDAR security model and audit record

Audit date: 2026-10-20. This records the inspected implementation and changes
on `audit/security-performance-2026-10-20`. It supplements the existing
[IPC/lock policy](SECURITY.md), [privacy model](PRIVACY.md),
[recovery design](RECOVERY.md), and [Task Manager contract](TASK-MANAGER.md).
Passing fixture tests is not proof that the entire desktop is secure.

## Authority and ownership

CEDAR's shell, installer, CLI, and native Task Manager run as the desktop user.
The public installer/distribution entry points and native task daemon reject
root execution. User QML, menu expressions, plugins, and source checkouts are
trusted executable code. CEDAR does not sandbox them or defend against a
compromised process with the same UID.

| Boundary | Implementation and limitations |
| --- | --- |
| UI to Python helpers | `ServiceRequest` uses argument vectors and JSON stdin. This avoids shell interpolation and putting request secrets in argv. Individual providers still need bounded input/output and lifecycle review. |
| Desktop IPC | Existing settings, lock, menu, and feature guards are described in `SECURITY.md`. Authentication of the desktop user does not mean every message is valid; size/schema/lock checks remain necessary. |
| Task Manager IPC | `native/taskmanager/backend.cpp` listens on a private per-user Unix socket; `sameUserPeer()` validates `SO_PEERCRED`. Version/build handshake, 8-client cap, 8 KiB requests, 20 requests/second, and outgoing-queue limits bound clients. No TCP listener is introduced. |
| Task Manager process controls | `collector.cpp` checks UID, PID/start time, executable identity, protected session ancestors/components, and explicit force-stop confirmation. Signals use pidfds. Priority changes use a short-lived tracer to hold identity; kernel tracing restrictions cause refusal rather than a numeric-PID fallback. |
| Privileged installation | `installer/providers/privilege.py` delegates package operations through polkit or terminal sudo. It does not grant persistent privilege or change sudo policy. |
| Shield | User-requested changes use NetworkManager/resolved or a selected firewall manager. Firewall/Avahi operations use polkit. UFW currently uses a **fixed** `/bin/sh -c` expression under pkexec; it does not interpolate request data. This is an exception to the older broad statement that helpers never use shell commands. |
| Files and recovery | `distribution.py` checks private stores, refuses managed symlink parents, writes atomically, inventories release files, journals integrations, and restores only when expected state matches. Installed paths, public entry points, and release ownership were preserved. |
| Updates | The three update paths below have different trust guarantees. A SHA-256 digest detects changed bytes; it does not establish publisher identity. |

## Update trust paths

1. **Standalone bootstrap:** the script itself is trusted code obtained by the
   user. Stable release archive and checksum arrive from the same configured
   HTTPS GitHub repository. The checksum must now name exactly the downloaded
   asset. Development explicitly uses HTTPS source with no release signature.
   `CEDAR_REPO`/`CEDAR_BRANCH` overrides are deliberate user trust choices;
   their syntax is checked, not treated as proof of publisher authorization.
2. **Managed stable/development update:** `installer/engine/update.py` fetches
   the selected allowlisted `main`/`dev` branch from the default fixed repository
   into a private bare cache. It ignores inherited Git overrides and global/system
   Git configuration, exports the exact commit, and rechecks source digests at
   handoff/install. Channel provenance is written after installation verification.
   This trusts the repository and HTTPS; commits are not publisher-signature
   verified. Programmatic repository injection remains available to local tests.
3. **Explicit signed archive update:** `distribution.update()` requires an
   explicitly chosen trusted public key and detached signature. OpenSSL verifies
   a private archive snapshot; extraction reads the same snapshot. CEDAR does
   not currently provision an independent publisher signing identity.

Compromising the release repository or its publishing credentials remains a
supply-chain risk. Checksums downloaded beside an archive, Git commit hashes,
and installed source digests do not eliminate that risk. There is no claim of
independently authenticated automatic security updates.

## Implemented corrections

| ID | Original problem and correction | Compatibility and validation |
| --- | --- | --- |
| SEC-01 | Bootstrap accepted a checksum manifest for an unrelated file, then executed the unverified release archive. Verification now accepts one digest naming exactly the expected asset and hashes that asset. | Stable asset names and `CEDAR_FETCH_ONLY` handoff protocol remain intact. A real-shell fixture reproduced acceptance before the fix and rejection afterward. |
| SEC-02 | Bootstrap followed a cache symlink for chmod/writes, reused mutable version directories, and passed archives directly to tar without CEDAR member/type/size policy. It now validates cache ancestors/ownership/privacy, creates a private unique snapshot, rejects traversal, links, special/duplicate entries and multiple roots, caps member/payload/decompressed sizes, and preserves ordinary executable bits only. | Stable and development fixtures pass. A second invocation keeps a pending installer's source unchanged. Failure removes only its newly created snapshot. The verifier is embedded because downloaded code cannot authenticate itself. |
| SEC-03 | Managed updates retained the entire tar archive in Python memory and had no archive count/payload budget. Git output now streams in 64 KiB blocks into a private temporary file; output, diagnostics, extraction count and payload are bounded. Cancellation/deadline failure reaps Git and its owned helper process group. | Managed branch selection, immutable commit handoff, rollback/provenance, and dirty user checkout preservation pass integration tests. Budget failures leave the installed stable release unchanged and remove temporary snapshots. |
| SEC-04 | Installer `Host.stream()` checked its deadline only after a blocking output iterator ended, and did not always wait/close on exceptions. It now enforces one deadline while reading and waiting, caps unterminated output fragments, and reaps/closes its direct child. Ordinary commands own a process group so their descendants are stopped on failure; sudo/pkexec retain the controlling terminal. | Existing installer tests pass; real silent/noisy subprocess, partial UTF-8, callback failure, and long-line regressions pass with `ResourceWarning` treated as an error. Privileged descendants remain subject to OS permissions and may continue or be interrupted; the package-timeout message requires checking package state/logs before retrying. PTY regression tests preserve terminal authentication semantics. |
| SEC-05 | Shield DNS could persist changed settings if reapply/activation or verification raised before its old rollback branch. The full apply/verify operation now restores captured fields on command/timeouts/I/O failures, reapplies them, checks restored profile fields, and reports restore failure explicitly. | The provider interface and successful result are unchanged. Mocked reapply timeout, resolver failure, rollback timeout and successful update paths pass. No live DNS state was changed during this audit. |
| SEC-07 | Wi-Fi/IPv6/discovery/firewall operations previously skipped recovery on exceptions, omitted live reapply/Avahi state, or restored the opposite firewall toggle rather than captured state. Shared checked NetworkManager apply/restore now verifies profiles; IPv6 verifies restored live state; discovery captures/restores both Avahi units and resolver flags; firewall restores active/boot-enabled/configured states independently. | Stateful fixtures inject partial-write timeouts, verification failures, denied recovery, socket activation and UFW persistence differences. Non-boolean enable requests are rejected. Unknown/transitional/masked/runtime-only unit states refuse before mutation rather than promise unreconstructable recovery. Live privileged acceptance remains outstanding. |
| PERF-SEC-01 | Release inventory detection read each complete asset to inspect an 80-byte LFS header; file and source digests also retained whole files. Prefix checks now read 80 bytes, and SHA-256 reads incrementally. | Existing digest/source identity is byte-for-byte unchanged. A 16 MiB asset regression keeps traced allocation under 2 MiB. Repeated 64 MiB before/after measurements are reproducible with the command below. |

```sh
python3 scripts/benchmark_release_validation.py --reference eb60f2c
```

The recorded three-run isolated benchmark used a 64 MiB zero-filled asset.
Before: 67,110,577–67,110,633 bytes peak traced Python allocations and
87,600–91,568 KiB process peak RSS. After: 395,159 bytes and
22,288–22,432 KiB. Median elapsed time was 26.04 ms before and 17.23 ms after.
All six runs produced the same SHA-256. These are a helper microbenchmark's
allocations/RSS, **not** proof of shell PSS budget compliance or frame performance.

The standalone verifier intentionally duplicates a small subset of archive
validation: importing a validator from an unverified download would cross the
trust boundary before verification. General installed release hashing and
inventory policy remain in the existing distribution module.

Shield actions reserve 120 seconds for application and 120 seconds for recovery.
The shared command deadline also caps capability probes and post-action refresh;
expired budgets stop launching commands and report unresolved recovery. The QML
watchdog is now 300 seconds (60 seconds of exit/IPC margin), so a slow permission
prompt can leave the UI waiting longer than before, but it does not kill the
backend at the old 150-second boundary during ordinary rollback. A timed-out
privileged operation may outlive its wrapper: even if captured flags are observed
again, the result explicitly says elevated work may still run. No completed
rollback is claimed in that case.

Live NetworkManager changes now recheck the captured connection UUID before
reapplying. Recovery always attempts the saved profile fields, but refuses to
reconnect an old profile over an independently changed active connection. The
old automatic `connection up` fallback was removed from these transactions to
avoid undoing a user's profile switch. A switch at the OS call boundary remains
a race without a NetworkManager checkpoint; it is not claimed atomically isolated.

## Validation performed

All commands below use fixture homes/remotes or disposable children. These
counts are the backend audit runs, separate from the complete repository checks.

| Suite | Result |
| --- | --- |
| `test_bootstrap_security.py` | 9 tests pass; baseline had 9 failing assertions/subtests. Stable/development source, checksum substitution, mismatched checksum, traversal, private cache/symlink refusal, unsafe members, member budget and concurrent handoff preservation. |
| `test_installer_stream.py` | 8 tests pass, with ResourceWarnings promoted to errors. Baseline did not enforce read deadlines and emitted resource warnings. |
| `test_installer.py` | 51 tests pass. |
| `test_distribution*.py` | 30 tests pass, including release installation/restoration fixtures and bounded allocation. |
| `test_update_channels.py` | 23 tests pass, including source tamper, branch selection, exact revision, interrupted update, budget rejection and cleanup. |
| `test_update_checkout.py` | 20 tests pass. |
| `test_security_hardening.py` | 9 tests pass. |
| `test_shield*.py` | 33 tests pass, including stateful Wi-Fi/IPv6/discovery/firewall recovery, profile-switch guards, deadline reserve/exhaustion and input validation; three earlier DNS recovery cases failed before its fix. |
| Shell syntax | `sh -n installer/bootstrap/install.sh` passes. |

This is not evidence of real firewall/DNS transitions, a live privileged package
transaction, PAM authentication, a live lock/suspend cycle, a remote GitHub
download, different-UID IPC denial, or all backend failure/recovery scenarios.
See the aggregate performance/audit documents for additional tests and limits.

## Unresolved findings and release gates

| ID / priority | Evidence and next required work |
| --- | --- |
| SEC-06 / high | Automatic bootstrap/managed updates lack an independently provisioned publisher verification key and signature policy. Choose and document publisher key distribution, protected publication and rotation/revocation, then enforce signatures for security-sensitive releases. This blocks claiming the full authenticated-update objective. Do not infer trust from a checksum downloaded with the archive. |
| SEC-08 / medium | Successful bootstrap snapshots are retained to protect pending installer handoffs. They have no age/size pruning policy yet. Define source ownership/lease expiry before deleting them; repeated successful bootstraps can consume disk. Managed branch snapshots already have a separate age-based pruning policy. |
| SEC-09 / medium | Archive budgets bound accepted bytes/members, but are not a universal disk/network quota. Bootstrap download size is rejected after transfer; network timeouts are not a byte quota. Git fetch pack/cache growth is separate from exported archive limits. Add download/pack limits without weakening completeness or signature verification. |
| SEC-10 / verification | Native PAM, suspend coverage, cross-UID IPC enforcement, real privileged recovery and distribution-specific behavior require controlled sessions. Existing guards and unit tests do not substitute for these acceptance checks. |
| SEC-11 / high | Firewall recovery verifies the captured manager/service active, enabled and configured flags, not arbitrary runtime-only firewall rules. Restarting a manager can rebuild from permanent configuration and lose runtime-only rules. Recovery now explicitly reports this limitation rather than claiming all prior settings restored. Provider-specific capture/restore/verification of runtime rules remains required before claiming complete firewall rollback. |

Do not label all critical workflows hardened while these gates remain open.
The audit did not find or introduce a need for broad passwordless sudo, an
always-root shell, firewall/DNS changes without user intent, or weakened kernel
security policy.

## Rules for future changes

Reuse the existing provider and its state owner before adding a helper. Each
long-lived process needs an owner, cancellation and cleanup; each timer needs a
purpose and inactive behavior. Keep command arguments structured, validate
inputs before side effects, bound retained data, preserve installation layouts,
and test interrupted/failed recovery. Changes to privileged controls need
failure-injection evidence, and optimizations need comparable before/after
measurements with their accounting limits stated.
