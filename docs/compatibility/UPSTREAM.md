# Upstream implementation research

Inspected 2026-10-11. Revisions below are source observations, not claims of
native integration certification. Sources were downloaded read-only to a temporary
research directory. Repository URLs redirected for Noctalia and Omarchy; current
canonical sources are recorded. No upstream installation scripts were executed.

## Caelestia shell and dots

- Shell revision: [21a75375bb33123e481e796a74965038847c503d](https://github.com/caelestia-dots/shell/tree/21a75375bb33123e481e796a74965038847c503d).
- Dots revision: [158ac301a3ca8f8619e6a506e4d89b00b9a7ea19](https://github.com/caelestia-dots/caelestia/tree/158ac301a3ca8f8619e6a506e4d89b00b9a7ea19).
- `hypr/hyprland/execs.lua` launches `caelestia shell -d` from a
  `hyprland.start` callback. The same file starts keyring, polkit, clipboard
  history, geoclue, gammastep and MPRIS helpers. They must not be removed with the bar.
- The shell's `nix/hm-module.nix` declares `caelestia.service`, `ExecStart`
  via the packaged `caelestia-shell`, `Restart=on-failure`, and a configurable
  Wayland session target. Stopping only a child process would not disable its owner.
- `README.md` documents AUR `caelestia-shell`/`caelestia-shell-git`, manual
  installation and Nix. Quickshell source paths depend on the chosen installation;
  detect the running config path, not a guessed universal directory.
- The shell integrates launcher, notifications, lock/idle and wallpapers;
  `modules/lock/Lock.qml` exposes a lock IPC target. There is no reviewed CEDAR
  permission to shut down all those roles. No shutdown command is invented here.
- The dots README now uses `caelestia install` and `caelestia update`; the old
  `install.fish` is removed. Its updater owns `~/.config/hypr`. User changes
  belong in `~/.config/caelestia/hypr-user.lua` and `hypr-vars.lua`.
  `hypr/hyprland/keybinds.lua` is upstream-owned, not a CEDAR replacement target.
- Detection only. A future adapter must review the CLI version and bundled
  lock/idle handoff, unit ownership and update-safe user includes.

## Noctalia

The requested `noctalia-dev/noctalia-shell` now redirects to
[noctalia-dev/noctalia at 4b4dedef3a92205217efd718f7c5902d57f887dc](https://github.com/noctalia-dev/noctalia/tree/4b4dedef3a92205217efd718f7c5902d57f887dc).

- This is native Wayland/OpenGL ES v5, not the Quickshell v4 implementation.
  `docs/user/getting-started/installation.mdx` says v5 is a fresh install and
  both versions can coexist. They must be detected separately from running evidence.
- `docs/user/getting-started/running-the-shell.mdx` recommends compositor
  startup: `hl.exec_cmd("noctalia")` in `hyprland.start`; `noctalia --daemon`
  returns after initialization. A systemd unit is not assumed for every install.
- `docs/user/getting-started/faq.mdx` and `docs/user/ipc/shell.mdx` describe
  `noctalia msg ...`, TOML configuration, bar/launcher/OSD/notifications,
  wallpaper and the integrated session/idle/lock routes. Suspend without lock
  and lock-and-suspend are distinct operations. Never replace one with the other.
- Handwritten TOML lives in the configuration directory; GUI overrides and
  merged configuration are separate. Existing CEDAR v5 adapter exports full and
  merged configuration before changing selected surfaces.
- Packaging/build instructions are in `BUILDING.md`, `PACKAGING.md` and the
  installation docs; Nix Home Manager can generate configuration. Store-backed
  files remain declaratively owned. Manual installation has no automatic updater.
- Existing CEDAR adapters pin v4 4.7.7 and native 5.2.1 interfaces in
  `integrations/portable/noctalia*.json`. Current HEAD is research evidence,
  not an expansion of those version gates. Resident lock/idle/polkit and
  wallpaper remain preserved unless the existing explicit Trailwatch test passes.

## end-4 / illogical-impulse

Revision [2f2a376fdb2ad738bf55f693dd0b474b64bb0ab8](https://github.com/end-4/dots-hyprland/tree/2f2a376fdb2ad738bf55f693dd0b474b64bb0ab8).

- `setup` and `sdata/` own installation, distribution dependencies and uninstall
  workflows; `sdata/dist-nix/home-manager/quickshell.nix` covers declarative setup.
- `dots/.config/hypr/hyprland/execs.lua` launches `qs -c $qsConfig`, wallpaper
  helpers, keyring, hypridle, DBus environment and clipboard watchers. The
  default QML source is under `dots/.config/quickshell/ii`.
- `dots/.config/hypr/hyprland/keybinds.lua` and the separate `custom/` Lua
  files distinguish shipped bindings from user extensions. Dynamic `$qsConfig`
  is evidence requiring resolution, not a hardcoded `ii` shutdown target.
- `dots/.config/hypr/hypridle.conf` routes locking through Quickshell global
  shortcuts and loginctl, with a Hyprlock fallback and sleep inhibition.
  Clipboard watchers also call `cliphistService update` on the selected shell.
  Killing Quickshell can break idle and history even if the bar disappears.
- Bundled panels, launcher, notifications, wallpaper and authentication require
  role-level inspection. No universal user service or uninstall command is assumed.
  Detection only; no broad `pkill qs` migration.

## HyDE

Revision [fa2fd57afc7203b1b5653d3271f3a57ea3873f97](https://github.com/HyDE-Project/HyDE/tree/fa2fd57afc7203b1b5653d3271f3a57ea3873f97).

- `Scripts/dots/hyprland.toml` describes sync versus preserve ownership:
  shared Lua under XDG data is synchronized, while the user Hyprland entry
  file is preserved. `MIGRATION-LUA.md` documents the configuration transition.
- `Configs/.local/share/hypr/lua/start_up.lua` reads `hyde.config.start` and
  launches each selected provider: bar, wallpaper, notifications, auth dialog,
  idle, clipboard, DBus environment and other applets. These commands are
  configurable, not a universal process list.
- `Configs/.local/share/hypr/lua/hyde/dispatcher.lua`, Waybar module definitions
  and `Configs/.local/lib/hyde` contain the actual `hyde-shell` commands.
  A Waybar process alone does not prove unmanaged standalone ownership.
- `Configs/.config/hypr/hypridle.conf` invokes `hyde-shell lockscreen.sh`,
  routes sleep via loginctl, and sets `inhibit_sleep=3`. Lock and power roles
  must survive a panel replacement. Wallpaper/theme tooling also writes colors.
- Dot manifests specify package and file behavior; Nix is optional upstream.
  No generic HyDE uninstall or systemd unit is guessed. The profile is detected;
  an unbundled standalone setup may pass the portable adapter only after its
  real runtime/startup evidence is independently reviewed.

## Omarchy

Requested `basecamp/omarchy` redirects to
[omacom/omarchy at 9480d1b6a98156314dbabe6bfef08f39f8b9cd07](https://github.com/omacom/omarchy/tree/9480d1b6a98156314dbabe6bfef08f39f8b9cd07).

- `default/hypr/autostart.lua` imports the session environment, calls
  `omarchy-launch-shell` and runs post-boot hooks. `bin/omarchy-launch-shell`
  starts a path-specific Quickshell instance through systemd-cat, disables hot
  reload during package updates and handles unexpected exits.
- `bin/omarchy-restart-shell` checks active/stranded lock state, addresses only
  the configured shell path, then verifies shell and notification IPC readiness.
  CEDAR must not emulate that with a generic process-name kill.
- Shell bar, menu, notifications, OSD, idle and lock are plugins. Clone IDs may
  differ from stock. `shell.json`, plugin manifests and running IPC together
  define current ownership. Omacale is a companion, not a synonym for Omarchy.
- Packaged sources under `/usr/share/omarchy` are read-only integration inputs;
  user Hyprland modules and Omarchy user plugins are separate. Themes, wallpapers,
  app settings, update commands and post-boot hooks are upstream-managed roles.
- CEDAR already retains the authentication host and uses its own bridge and
  private transaction. Lock replacement requires the existing local PAM and
  real unlock tests. `integrations/omarchy/adapter.json` pins the reviewed API
  hashes; upstream HEAD does not automatically satisfy those hashes.

## DankMaterialShell (additional required target)

Revision [6640a943b30d11407bc868469910dcb0800f3254](https://github.com/AvengeMedia/DankMaterialShell/tree/6640a943b30d11407bc868469910dcb0800f3254).

- `assets/systemd/dms.service` runs `/usr/bin/dms run --session`,
  `Type=dbus`, owns `org.freedesktop.Notifications`, restarts on failure,
  and is tied to graphical-session.target. This is stronger evidence than a
  generic Quickshell executable name, but local units can be overridden.
- Go CLI/process management lives in `core/cmd/dms`; QML lives in `quickshell`.
  Hyprland configuration helpers are under `core/internal/config` and keybind
  providers under `core/internal/keybinds`. Inspect their actual generated output.
- `distro/` and the flake contain packaging and Home Manager integration.
  Shell launchers, notifications, lock/idle, power, wallpaper and theme services
  may be bundled. No wholesale stop is approved by this detection profile.
- Detection only. Stopping dms.service without a separately verified lock/idle
  replacement is not an implemented migration path.

## Clipboard and unknown configurations

Wayland selection transfer is not application editing. `wl-copy`/`wl-paste`
(and supported data-control protocols) can read/write clipboard selections;
cut/copy still requires the focused application's semantics. Synthetic global
Ctrl+C/X/V can affect terminals, games, grabs and secure surfaces incorrectly.
This implementation never installs universal Super+C/X/V emulation. Existing
clipboard/history providers are retained; CEDAR's own UI uses normal text controls.
Sources: [wl-clipboard upstream](https://github.com/bugaevc/wl-clipboard) and
the installed `wayland-protocols/staging/ext-data-control/ext-data-control-v1.xml`
([upstream protocol](https://gitlab.freedesktop.org/wayland/wayland-protocols/-/blob/main/staging/ext-data-control/ext-data-control-v1.xml)).
The protocol manages selection offers and sources, not an application's editing
commands. The decision against global key emulation is CEDAR's safety boundary.

An arbitrary Quickshell config may be a small widget rather than a shell. Its
path and session association are reported as unknown until reviewed. Generated
configuration, shell expressions and service wrappers are never executed to
"discover" their meaning.
