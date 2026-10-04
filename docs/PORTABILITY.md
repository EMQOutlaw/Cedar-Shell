# Portable Hyprland integration

CEDAR runs its own Quickshell profile and local services. Neither Omarchy nor Noctalia is a dependency. This candidate supports automatic package preparation on Arch Linux from already configured repositories; other distributions may use install-only/preview with dependencies provided by the user. A working Hyprland session must already exist. No compositor or display manager is installed.

## What changed

`bash ./install.sh` now checks prerequisites, offers a separately approved package plan, installs a versioned copy, and offers Install Only, Preview or a full trial. A successful trial can be kept and separately enabled at login. Declining any step stops that action. The installer does not depend on its download folder after installation. Bash is the documented entry point regardless of the user's preferred shell.

The portable profile uses CEDAR's own Go menu, JSON palettes, wallpaper state and runtime helper. It discovers the selected browser/editor/files handler through desktop associations. Terminal launching prefers xdg-terminal-exec and existing installed terminals. Nothing installs Zen/Zed or changes associations without a user action. Night Light uses an existing Hyprsunset provider; unavailable providers remain unavailable.

Ordinary optional palette snippets live in `themes/hyprland.conf` and `themes/hyprland.lua`; they do not launch anything, unbind keys, change monitors or call distribution-specific functions. Settings writes its own generated `.conf` or `.lua` plus a separate editable user override, using the actual detected main file. Symlinked/managed or ambiguous targets are refused. These snippets are optional and are not silently sourced by installation.

The existing Omarchy menu overlay, palette/keybind snippets, legacy migration helpers and session adapter are retained under explicit compatibility paths. Portable dependency checks exclude the Omarchy-only scope. No Omarchy executable, PAM service, background link, menu file, installation tree or shell is needed for the portable profile. Runtime unit tests and the standalone QML harness check this distinction.

## Stock Hyprland adapter

The adapter inspects processes, explicit Quickshell source paths, notification ownership and the compositor lock indicator. It accepts known standalone Waybar, Mako and Dunst providers. It stops only recorded process identities or their dedicated user units after approval; shared services and unknown notification owners are refused. A provider that unexpectedly restarts causes restoration instead of another broad stop.

Existing Hyprlock is used when its configuration is present. Existing idle handling is preserved; an unidentified locker/idle combination is refused. Without an existing locker, the candidate requires a local PAM test against the system `login` service before starting Trailwatch. This test is not proof of native session-lock coverage, hotplug or suspend safety. Authentication files are never altered. Trial activation requires positively unlocked compositor state.

CEDAR provides its own background only when no recognized background provider is running. It does not replace an existing swww/awww/hyprpaper/swaybg setup. In retained-background sessions, the picker explains that the existing provider owns wallpaper changes.

## Noctalia adapter

Noctalia 4.7.7 is QML/Quickshell; Noctalia 5.2.1 is a native application. They have distinct versioned adapters. `integrations/noctalia/adapter.json` records reviewed commits and the v4 API source hashes. Version/source mismatch stops a handoff; it does not upgrade, patch or terminate Noctalia.

After approval, the adapter privately backs up Noctalia's settings, disables only the overlapping bar/dock/notifications/OSD surfaces, and starts CEDAR after notification ownership is released. It keeps the host and existing lock/idle/authentication services running. v4 auto-hide modes are temporarily normalized before hiding every bar, so transparent hover targets do not reintroduce it. v5 writes narrow boolean overrides in the native state TOML; unsupported table spellings are refused rather than rewritten broadly. Existing user settings, comments and unknown keys are preserved where the format allows.

The resident locker remains the lock target. CEDAR hides unlocked controls whenever the supervisor mirror is locked, stale, absent or invalid. Lock-before-suspend requires compositor lock coverage on every reported display. Privacy or provider errors never count as an unlocked state.

The current candidate does not remap Noctalia shortcuts. A shortcut that re-enables its bar triggers restoration rather than keeping two competing bars. Existing external wallpaper controls remain with Noctalia. Custom Noctalia sources, additional independent Quickshell surfaces, and releases outside the reviewed interfaces need further review.

## Login and recovery

`cedar keep` confirms the session. `cedar activate` separately approves one owned startup block in the detected main Hyprland `.conf` or `.lua`. All original startup commands remain. On the next login, the supervisor waits for the recorded providers, revalidates Noctalia's API, then coordinates the same reviewed surfaces. It does not silently accept a different provider after an update.

The stable Python recovery tool and journal live outside the current release pointer. Private backups record contents, permissions, timestamps, symlinks and original absence. Restoration verifies hashes and checks every target for later edits before stopping CEDAR. Semantic-only reserialization by Noctalia is accepted only if the entire decoded configuration is equal; actual changed preferences remain conflicts. Package upgrades are not reversed by dotfile restoration.

If an external authentication host has crashed, changed version or cannot report its state, CEDAR defers restoration inside that session. Do not kill a locker to bypass this. Recover after safely unlocking or after explicitly ending the graphical session yourself; ending a session risks unsaved work. The recovery tool also works without Qt/display/internet from a text console after the graphical session has ended. See [offline recovery](RECOVERY.md).

## Evidence and limitations

Automated fixtures exercise no-Omarchy dependencies, local themes/wallpapers/menu, both configuration formats, pending-lock refusal, source/version mismatches, interrupted pauses, supervisor timeout, exact settings restoration, changed process IDs and manual edit conflicts. Actual CEDAR QML is tested offscreen with missing Omarchy paths. These are source/component tests, not native Noctalia handoff or fresh-system acceptance.

The reviewed runtime is Quickshell 0.3.1 / Qt 6.11.2 on x86_64. The compositor must expose the reviewed `solitaryBlockedBy` lock indicator. Other combinations are inspected conservatively. Native login/reboot, Noctalia handoff, stock-session locking, fractional scaling/hotplug, package bootstrapping on a clean machine and the GPU matrix remain unverified. No environment in this candidate is certified for public distribution.
