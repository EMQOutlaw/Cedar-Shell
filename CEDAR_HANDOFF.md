# CEDAR Work Handoff — living pin file

**Read this first if you are an AI (or human) resuming CEDAR work cold.**
Updated at every milestone by cedarbot. Owner: Ethan (EMQOutlaw).

**Everything below is COMMITTED and PUSHED to `origin/dev` (b42b0f0, 2026-11-01).** The live shell still runs this tree; the next dev-channel update builds from the pushed dev and keeps all of it. Remaining steals: fastfetch, Graphics & Power.

## ✅ COMMITTED & PUSHED 2026-11-01 — commit b42b0f0 on origin/dev

Owner authorized the push ("go ahead and commit it to dev"). Rebased the single program commit onto origin/dev (b090a20, which was 9 commits ahead — Fedora backend, glyph fallbacks, inventory-on-any-host), resolving two additive conflicts (CHANGELOG bullets; tests/test_desktop.py dev's `needs_lua` helper kept alongside our WindowsValues suite). Merged tree verified: inventory matches, 873 tests (only the 6 environmental default-apps errors), desktop_ui + settings_responsive PASS. Pushed b090a20..b42b0f0 → dev; ls-remote confirms. The live shell still runs the same content.

## Owner-approved host change — monitor manager disabled

Ethan authorized finishing the Display Settings repair from Discord after being told hyprmoncfgd was overriding CEDAR. The default agent ran `systemctl --user disable --now hyprmoncfgd.service` and verified ActiveState=inactive, SubState=dead, UnitFileState=disabled, with no hyprmoncfgd process remaining. No monitor profiles or user display configuration were deleted. Undo: `systemctl --user enable --now hyprmoncfgd.service` (would restore the competing manager). Before final completion/push report, re-check daemon state and verify CEDAR's safe display trial/apply persists beyond the previously observed override window, restoring the original display settings afterward. The old 'running daemon' limitation below describes the pre-change state, not the current host.

## ⚡ RESUME POINT 3 — 2026-11-02, fastfetch round 3 in gate + Displays root cause FIXED

**Owner authorization (Discord, 2026-11-02): finish Fastfetch + Displays, commit and push origin/dev. No force-push, no scope expansion.**

### Fastfetch (steal item 1) — code complete, securitybot round 3 running
- Page/service/helper complete and live-installed several times; live preview verified by screenshot (real fastfetch output).
- securitybot round 1: 3 P1 + 4 P2 + functional defects → ALL fixed (helper rewritten: preserve-by-replay with model.orig + per-row orig; baseline sha256 conflict refusal; mkstemp 0600 private writes + os.replace; symlinked config refused; helper-level legacy test-mode save refusal; get() strictly read-only, no --gen-config; string-aware JSONC trailing commas).
- securitybot round 2: 6 more findings → ALL fixed (named accent preserved via accentOriginal; colors row + string logo replayed; dedupe REMOVED; untouched padding dict replays, edited padding written as object (fastfetch requires object); Image kind REMOVED from UI (terminal-graphics dependent, other kinds preserved verbatim); page freezes all editing controls while busy; discard() added for the nav guard; save stops preview timers, errors cleared only by superseding replies; flock-serialized save with commit-boundary hash re-check; previewBusy = queued!==null).
- tests/test_fastfetch.py: 19 tests, one per finding. Full discover 895 — only the 6 environmental default-apps errors. Real-config round-trip (get→preview→save→restore) byte-identical by sha256.
- reviewbot: NOT YET RUN (after securitybot round 3).

### Displays bug (owner: "resolution, scale and refresh changes do not apply") — ROOT CAUSED + FIXED, live-proven
Two stacked causes:
1. **Ordering (fixed):** a `hyprmoncfg` block appended to ~/.config/hypr/hyprland.lua AFTER CEDAR's loader re-pinned both monitors (mode/position/scale=1/vrr) on every reload — CEDAR's monitor rules never won. Fix: `scripts/desktop.py ensure_loader_last()` repositions CEDAR's loader to the very end of MAIN on every install (idempotent, backed up; restore() cleans the repositioned loader without eating user edits). Tests: test_loader_is_moved_behind_a_later_monitor_pinning_block, test_rollback_cleans_a_repositioned_loader_without_eating_edits. Live: loader now after the hyprmoncfg block; a real scale trial applied (DP-1 1.25 seen via hyprctl) and auto-reverted.
2. **Live daemon (surfaced honestly, NOT fightable):** `hyprmoncfgd` (Omarchy plugin crmne.hyprmoncfg, running) re-applies its saved profile — observed live overriding a CEDAR trial between +3s and +10s. CEDAR cannot win while it runs. Fix: desktop.py snapshot() reports `displayManager` (pgrep hyprmoncfgd); Displays page shows an amber warning naming it, its behavior and the options (screenshot-verified live 2026-11-02). Do NOT stop the user's service to "prove" things (blocked, and user-files rule).
- displayManager test: test_snapshot_reports_a_running_monitor_manager.

### Next steps (in order)
1. securitybot round 3 verdict (running) → fix or proceed.
2. reviewbot (one combined handoff: fastfetch + displays) → fix until MERGE.
3. Commit ALL intended changes (fastfetch set + desktop.py ensure_loader_last/displayManager + DisplaySettings banner + tests + legacy-allowlist + inventory + handoff), fetch/merge origin/dev if moved, rerun inventory+discover on the result, push origin/dev WITHOUT force, verify `git ls-remote origin refs/heads/dev`.
4. hermes send --to discord:1566340910613274686 --json ... (default profile creds) with SHA/link, completed tasks, test limitations (daemon limitation + environmental default-apps errors). Verify delivery if possible.
5. Update ~/.hermes/profiles/cedarbot/cedar-resume-result.md (push SHA, remote readback, delivery message id, tests, remaining issues).



### Done and live-proven (both in this tree, UNCOMMITTED):
1. **Windows editor** — COMPLETE, reviewbot round 7 verdict MERGE (zero findings).
2. **Appearance trim (IA revamp item 1)** — code done, tests green, bots PENDING:
   - modules/AppearanceSettings.qml: 6 tabs → 3 (Themes/Surfaces/Typography); Colors merged into Themes (accents render under the grid with a "Theme accents" heading); the Living Edge and Grain placeholder tabs (whose only content was "no control exists") deleted with an explanatory comment.
   - check_desktop_ui PASS (63 shots incl. new layout, verified visually), check_settings_responsive PASS (8 sizes × 27 pages; the intermittent dictation overflow did not recur).
   - Review handoff staged: `~/.hermes/profiles/cedarbot/cache/scratch/appearance-handoff.md` — securitybot launch failed twice with runtime_draining.

### Appearance trim (IA item 1): ✅ COMPLETE through the gate, installed live
- securitybot: 1 P2 (test_settings_remaster still required the deleted placeholder route) → FIXED by removing the obsolete test exception (25 tests OK with PYTHONPATH=scripts).
- reviewbot round 2: MERGE WITH CHANGES, 1 minor (search anchor "theme" lives in Schema.extras, so search didn't switch tabs) → FIXED (explicit map in onHighlightKeyChanged). Round 3: MERGE, zero findings.
- Installed live 2026-11-01 ~03:1x EDT; isLocked answers; zero QML errors; trimmed page confirmed in the installed release.
### Shell & Bar one-page merge (IA item 2): ✅ COMPLETE through the gate, installed live
- 6 tabs removed; one page: preview map → geometry/material → modules (objectName "modules") → pop-outs/behavior → Core (dynamic island) → Understory (objectName "understory"). Duplicate canopy toggles removed (schema-rendered Core controls are the one home). "core" removed from the env nav group; standalone core page stays for search deep-links (shared CoreSettings, securitybot-accepted).
- securitybot: 2 P2 (search anchors lost after tab removal; duplicate canopy controls) → both fixed + regression test (test_bar_page_search_anchors_exist). securitybot PASS; reviewbot MERGE, zero findings.
- Installed live ~03:3x EDT; isLocked answers; zero QML errors.
### Windows page bunch-up (IA item 3): ✅ COMPLETE through the gate, installed live
- Top Apply section REMOVED (owner rule); sticky bar is now a floating pill over the page area's bottom edge (never consumes viewport; compact single-row at narrow while merely dirty). Sections bunched 2-column (>980px): Tiling|Behaviour, Gaps|Shape & motion, Border full, Opacity|Blur, Shadows|Glow, Live workspaces + bottom Reset row full. Bar spacer grows the scroll content while dirty so the Reset row clears the bar.
- securitybot round 1: 4 findings (leftover bar Reset with wrong cancel text, staggered cards, dirty-state viewport 60px, Shape caption) — all fixed. securitybot PASS. reviewbot round 2: 2 P2 (overlay obscures 100px minimum + covers Reset; harness measured the wrong thing) — fixed with the spacer + honest unobscured/reset-clearance assertions. reviewbot round 3: MERGE, zero findings (measured 108px unobscured at 480x360 dirty, 60px Reset clearance at all sizes).
- Installed live ~04:0x EDT; isLocked answers; zero QML errors.
### Audio — Cava spectrum removed from the Audio Canopy (IA item 4): ✅ COMPLETE through the gate, installed live
- AudioCanopy spectrum toggle + instance removed; SettingsSchema field + advancedKeys entry removed; audioSpectrum config key KEPT (pinned re-add restores the user's setting).
- securitybot P1 (correct): spectrum.py is NOT dead — the bar's Canopy Pulse consumes it via Pulse.qml. spectrum.py + AudioSpectrum.qml + lifecycle test + qmldir + plugins.json/source-files.json restored byte-identical to HEAD. Removal stays scoped to the Audio UI. Docs updated (CANOPY.md, STATUS.md).
- securitybot round 2: 1 P2 (releaseArtifacts omission) → fixed + staged. securitybot PASS; reviewbot round 2 confirmed the staged manifest and gave MERGE, zero findings.
- Tests: full discover 864 tests — only the 6 known-environmental default-apps errors (venv python3 lacks PyGObject `gi`; pass under /usr/bin/python3; files untouched). Schema tests updated for the core search-only design; WindowsSettings hex placeholders replaced with live Theme tokens (test_only_theme_defines_qml_colors).
- Installed live ~04:3x EDT; isLocked answers; zero QML errors.
### Desktop Profiles removed (IA item 5): ✅ COMPLETE through the gate, installed live
- Removed: settings page + ProfileSettings.qml, the standalone editor app (ProfilesApp/ProfilesPages/ProfileHud/ProfileHudCard + qmldir + cedar-profiles.desktop/icon), schema page + menu entry, Overview card, QuickControls tile, Understory rail button + STANCE selector, the dead window/HUD machinery in services/Profiles.qml (windowOpen/openApp/closeApp/hud*), menu entry, and the open/close CLI+IPC routes (headless activate/deactivate/toggle/status KEPT — the transaction stack is shared with Gaming).
- securitybot caught a P1 the harnesses missed: shell.qml still instantiated the deleted types (startup blocker) — fixed; round 2 caught my announce() deletion (Core-pill regression) — restored. securitybot "current worktree passes"; reviewbot MERGE after the two style cleanups + live reinstall.
- 864 discover tests: only the 6 known-environmental default-apps errors. check_profiles (service-level now), understory, canopy, controls, desktop_ui, responsive, lifecycle, inventory: PASS.
### Item 6 — Gaming Mode: ALREADY SHIPS (verified, no change)
Gaming Mode exists in this lineage: full "Gaming Mode" section in Power & Idle (Super+G, enter/leave, GameMode integration pill), services/Gaming.qml, gaming* schema keys, Gaming tile in Quick Controls. The owner's "does not ship" impression came from an older install. Verified present in the installed release. No code change made.
### VPN consolidation (IA item 7): ✅ COMPLETE through the gate, installed live
- modules/ConnectionSettings.qml: Proton, Tailscale and NetworkManager VPN profiles consolidated behind ONE collapsed drop-down ("▸ VPN — <live summary>"); the summary elides and the kill-switch warning is a dedicated StatusPill that never disappears (Accessible.name carries everything). Tailscale's installation guard preserved. securitybot rounds: Tailscale guard override + 480px overflow + kill-switch disappearance all caught and fixed; PASS. reviewbot MERGE (indentation-only style note).
- Installed live ~05:0x EDT; isLocked answers; zero QML errors.
### Lock Screen standalone + Security → Privacy & Shield (IA item 8): ✅ COMPLETE through the gate, installed live
- Page "security" relabeled "Lock Screen" (id stable — 4 lock-screen fields reference it); its page now carries an honest "pinned for future consideration" note. The "Trailwatch & session security" surface moved to PrivacySettings.qml (above the Shield embed) with search entry sessionSecurity + objectName anchor. DesktopSettingsPage screensavers text updated. securitybot: search-probe P2 + anchor P2 both fixed → PASS; reviewbot MERGE.
- Installed live ~05:3x EDT; isLocked answers; zero QML errors.
### Advanced genuinely advanced (IA item 9): ✅ COMPLETE through the gate, installed live
- Hub trimmed to Desktop Setup + Application Theming (the two dangerous pages); the whole "advanced" page is now advanced:true — hidden from nav until "Show advanced" is on. Time & Date/Field Notes/Dictation/Dynamic Island links removed (each reachable via its own group: TopBar link, Input tab, DefaultApps tab, Shell & Bar embed).
- securitybot round 1: P2 Field Notes lost its browseable entry → fixed with a "Field Notes" tab in InputSettings (cross-page-tab pattern, draft-guarded navigate) + allowlisted route in test_settings_remaster; P3 Simple-mode setup highlight decided: no rail row highlights while its parent is hidden (securitybot concurred, no fallback). securitybot PASS; reviewbot MERGE.
- Installed live ~06:0x EDT; isLocked answers; zero QML errors.
### About compaction (IA item 10) + weekly update check/alert (IA item 12): ✅ COMPLETE through the gate, installed live
- About: five sections pair two-wide (>980px), Christian Foundation full-width, hero compacted; EVERY word preserved. securitybot's P1 (zero-width GridLayout collapse at ≤980 from an invalid columnSpan) fixed structurally; collapse regression covered by measured geometry.
- Item 11 needed NO code: Settings is already a FloatingWindow (movable/resizable/size-remembering, landed in db5b2ad; verified in the installed release).
- Weekly check/alert: SettingsInfo snapshot results arm the cadence — network check runs only when 5 minutes past shell start, an hour past the last attempt (attemptedAt persisted BEFORE the updater runs, surviving helper termination), and the last verified check is >7 days old. Alert = CoreService integration row ("CEDAR update available", Open Updates → openPage("system")); deferred by DND/Focus without consuming the marker; re-announces per session until applied; check() preserves announcement metadata for the same release. 'checking' state surfaced on the Overview card.
- Review chain: securitybot rounds 1–5 (P1 About collapse; arming/durability/dispatch/insertion≠delivery/markers) all fixed → PASS; reviewbot MERGE with all repros re-run. Real end-to-end check executed against the stable channel during verification (state: available, checkedAt persisted).
- Installed live ~06:4x EDT; isLocked answers; zero QML errors.
### PROGRAM STATUS: IA items 1–12 COMPLETE (each per-item entry above). Then the owner's original steal list.

### Dictation revamp (steal item 2): ✅ COMPLETE through the gate, installed live
- modules/DictationSettings.qml: model click-to-select cards grouped installed/downloadable (Ryoku DictationPage pattern; download unchanged — voxtype exposes no size/percent data, so Ryoku's >1GB confirm and progress track are not reproduced); sections bunched 2-column; the long-standing pre-existing 480px dictation overflow FIXED; live mic-level meter added (gated: active && visible && unlocked && meterEnabled && !testMode — securitybot drove the gate through 3 rounds and 32 state combinations), explicitly labeled as system-default (not the selector's device); Accessible names/roles on all model cards; notifications toggles kept.
- SettingsPanel passes `active` into the dictation page. No service/helper/schema changes.
- Review chain: securitybot 3 rounds (meter lifetime P1, wrong-device P2, a11y P2, toggle-off P1) all fixed → PASS; reviewbot MERGE after caption/comment cleanup.
- 864 discover tests (6 environmental only); desktop_ui, responsive (dictation 480 overflow FIXED), frontend_lifecycle, service_lifecycle PASS. Installed live ~07:1x EDT; isLocked answers; zero QML errors.
### REMAINING STEALS (owner's original list): fastfetch; Graphics & Power. Pinned: the rest per backlog.

The full Windows editor change set passed securitybot + 7 reviewbot rounds (round 7 MERGE, zero findings).

## Current state (2026-11-01, ~02:15 EDT)

**Live lineage:** this tree, `~/Work/cedar-morph` (branch feat/blob-morph, 1.17 Caelestia-styled bar). NEVER install live from any other tree — doing so twice silently reverted the user's shell. Live-install command:

```bash
cd ~/Work/cedar-morph && CLEAN_PATH=$(env -i bash -lc 'echo $PATH') && \
env -i HOME=$HOME USER=$USER XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-1 \
HYPRLAND_INSTANCE_SIGNATURE=$(ls /run/user/1000/hypr/ | head -1) PATH="$CLEAN_PATH" \
CEDAR_SKIP_PACKAGES=1 /usr/bin/python3 installer/cedar_install.py --no-gui --yes
```

Verify after install: `env -u XDG_CONFIG_HOME XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-1 qs -c cedar ipc call shell isLocked` (must answer, not error) and `tail -20 ~/.local/state/cedar/shell.log` (zero QML errors).

**Everything in this tree is UNCOMMITTED.** A dev-channel update will silently drop it until it is committed and pushed to `dev` on EMQOutlaw/Cedar-Shell. That is the single most important open risk. Get the owner's explicit go-ahead before pushing.

## Just finished: Settings › Windows editor (Ryoku port 1 of 5)

- 50 Hyprland options (layout/gaps/border/resize/snap/tearing/rounding/opacity/dim/blur/shadow/glow/animations) through `scripts/desktop.py` (WINDOWS map, strict typed live reads, exact-byte 0xAARRGGBB colours, gradient tables, transactional apply with verify + rollback).
- `services/DesktopSettings.qml`: draft/apply lifecycle + `windowsReconciling` lock + bounded read retries (4) + `inFlightWasApply` ownership.
- `modules/WindowsSettings.qml`: the page. `modules/SettingsPanel.qml`: sticky apply bar (`windowsApplyBar`) pinned below the scroll viewport.
- 6 reviewbot rounds done: rounds 4–5 findings all closed (unrelated-op unlock, bounded retries with sticky-bar Retry button, viewport collapse, trial-timer bound, bar text wrap — all reproduced-and-verified by the reviewer). Round 6 found 1 P2, FIXED AND LIVE-PROVEN:
  - Frozen companion axis: with one shadow-offset axis owned, the unowned axis is now resolved AT LOAD TIME via a do-block in generated.lua (`hl.get_config("decoration.shadow.offset") or {0, 0}`), so upstream changes to it survive. Proven live: apply x=4 → vec2 [4,0], do-block in generated.lua, restore [0,0].
  - LATENT BUG fixed en route: this Hyprland's vec2 requires POSITIONAL arrays {4, 9} — named keys {x=4,y=9} are REJECTED. All vec2 emission is positional now; one test pins the exact line.
- test_desktop 23 run, all pass except the pre-existing environmental touchpad test (fails at HEAD too). check_desktop_ui / check_settings_responsive(windows) / check_service_lifecycle PASS. Inventory matches. Installed live ~02:05 EDT, zero QML errors, sticky bar verified on-screen wide+narrow.
- Tests: `tests.test_desktop` 23 run (1 pre-existing env failure, fails at HEAD too); `check_desktop_ui` / `check_service_lifecycle` PASS; responsive: windows passes all sizes, dictation 480px overflow is PRE-EXISTING (verified at HEAD).

## Next: Settings IA revamp (owner direction 2026-11-01, verbatim priorities)

Ordered program — see CODEX_BACKLOG.md "Settings IA revamp" entry for the full breakdown:

1. **Appearance** — strip placeholder settings (surfaces/grain/living-edge/typography/accent that don't actually control anything); revamp to real controls only. START HERE.
2. **Shell & Bar** — merge bar geometry/material/placements/modules/dynamic island/popouts into ONE simple page with location indicators.
3. **Windows & Workspaces** — remove the top Apply section (sticky bar covers it); two-column bunch-up so it doesn't scroll forever.
4. **Audio** — more real tweaking; dedicated EQ planned; REMOVE the Cava visual bar (pinned for possible return).
5. **Desktop Profiles** — remove the page entirely.
6. **Power & Idle** — Gaming Mode does not ship with CEDAR; bring it back (broken/missing — investigate).
7. **Network & Bluetooth** — consolidate Proton VPN + Tailscale + VPN into ONE dropdown section.
8. **Privacy & Shield** — absorb Security; Lock Screen becomes its own page (more options pinned for later).
9. **Advanced** — truly advanced only, hidden behind the Show advanced toggle, dangerous-but-understandable.
10. **About CEDAR** — keep ALL text, consolidate layout for small screens.
11. **Settings window** — convert from full-screen layer to a movable floating window (Steam-style).
12. **Updates** — weekly GitHub update check with user alert.
13. Pinned (explicitly later): screensavers, Lock Screen extra options, Nursery work, audio EQ, Cava return.
14. Also owner-approved keepers: Wallpapers, Displays, Input & Keybinds, Notifications, Privacy/Shield core, Updates & Recovery. App theming stays but needs a plain-English explainer.

Also queued from earlier (dux steals): dictation menu revamp, recording, fastfetch, Graphics & Power.

## Gotchas (hard-won)

- Shell env for IPC: prefix qs with `env -u XDG_CONFIG_HOME XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-1` (the bot session's XDG_CONFIG_HOME points at a sandbox).
- `hyprctl keyword` is DISABLED on this Lua-build Hyprland ("use eval") — writes go through `hl.config` / `hyprctl eval`.
- Colour forms this compositor accepts: solids `0xAARRGGBB` (exact bytes) or `rgba(r,g,b,a)` (float-loses-alpha — avoid); gradients ONLY as `{colors={"0x.."},angle=N}` tables. `rgba(RRGGBBAA)` reads channels R,G,B,A (NOT A first).
- vec2 options REQUIRE positional arrays `{4, 9}`; named-key `{x=4,y=9}` is rejected. `hl.get_config` returns a positional table too. `hyprctl keyword` is disabled on this Lua build; writes are `hyprctl eval 'hl.config(...)'` only.
- `hermes -p <bot> chat -q "<file text>"` is the one-shot reviewer invocation. `hermes --resume <id> -z "..."` HANGS (interactive); if the gateway disconnects, just re-run fresh with `chat -q`.
- Bool options report as JSON `bool` in getoption, not `int`.
- QML: never bind height→implicitHeight on wrapping text in Flow/Layouts (hangs offscreen harness). Never two same-named signal handlers. Pages need `import "../services"` for singletons.
- Standards live in the `cedar-standards` skill; review gate (securitybot → reviewbot until MERGE) is a standing owner order.
- Reviewer handoffs and logs: `~/.hermes/profiles/cedarbot/cache/scratch/`.
