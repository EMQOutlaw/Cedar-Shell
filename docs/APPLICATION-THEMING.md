# Application Theming

CEDAR's working application appearance engine is opt-in. Open **Settings → Application Theming**, enable synchronization, select integrations, choose a palette, then **Preview → Apply**. Preview lists the actual paths/preferences and blocked integrations. A changed file invalidates its preview. No application configuration is changed merely by opening Settings.

This is an implemented integration foundation with extended adapters, not a certification that every listed application renders identically. Native format, transaction, and settings UI checks are distinguished below from application visual testing. No external application's rendered appearance has yet been certified across supported distributions. The live Foot capture attempt was obscured by the session lock screen; it is deliberately not counted as visual verification.

## Implementation map

| Existing architecture | Integration |
| --- | --- |
| `Theme.qml`, live `cedar/theme.json` | Shared default `themes/palettes/cedar.json`; compiled runtime colors and semantic tokens; existing fallback colors retained |
| `scripts/export-themes.py` | Legacy assets now use the shared JSON palette rather than parsing QML |
| `scripts/theming/tokens.py` | Semantic colors, ANSI 16, dark/light variants, contrast checks, fonts, icons, radius, opacity, independent terminal colors |
| `scripts/theming/registry.py` | Executable, XDG desktop-entry, config and Flatpak discovery, toolkit groups and capability declarations |
| `scripts/theming/adapters.py`, `formats.py` | Explicit native mappings; lossless key edits, theme includes and manual exports |
| `scripts/theming/transaction.py` | Per-user lock, atomic writes, original snapshots, pending journal, recovery, ownership checks, restore/reset |
| `scripts/theming/engine.py`, `scripts/application_theming.py` | JSON service for preview/apply/status/sync/recovery, reload reporting and stale-preview checks |
| Existing `ServiceRequest.qml` | Asynchronous work outside the Quickshell render path |
| `services/ApplicationTheming.qml` | File-change events, 750 ms debounce, existing wallpaper/theme integration; no polling or per-app daemon |
| `modules/ApplicationThemingSettings.qml` | Presets and animated preview, scrollable coverage, app opt-outs, tuning, working actions; existing motion/accessibility primitives |
| `scripts/theming/wallpaper.py` | Bounded first-frame ImageMagick extraction, quantized hue, contrast-aware tokens and content cache |

The UI follows CEDAR's existing palette and reduced-motion preference. External applications retain their native widget rendering, animations and layout.

## Ownership and recovery

- **CEDAR Managed:** explicitly selected adapters receive native settings. Shared KDE/Qt/GTK adapters affect the toolkit, including apps outside the displayed group. They cannot offer independent per-app opt-outs for a global toolkit preference.
- **External Managed:** CEDAR follows a local CEDAR or pywal/wallust-style JSON palette. Application outputs remain with the external manager. No shell-specific arbitrary configuration/code is executed.
- **Independent:** no appearance files are updated. Existing outputs remain as last applied until Restore or Reset is selected.
- Disabling synchronization or opting out freezes the last applied appearance; it does not erase settings.
- **Restore Previous** reverses the latest changing transaction. **Reset CEDAR Overrides** returns all owned files/preferences to their original snapshots. Both pause automatic synchronization until the next Apply, so a wallpaper event cannot immediately undo restoration.
- A later user edit causes a conflict, including an unrelated edit in an owned file. CEDAR refuses to overwrite it. There is no force-overwrite button. Preserve/merge the edit against the snapshots before retrying.
- An interrupted journal is recovered before another apply, or using **Recover interrupted update**. Conflicting later edits stop recovery with an error.
- Existing symlinks, symlinked ancestor directories, non-user-owned and read-only configuration files are refused. CEDAR never replaces a symlink or follows it to rewrite another manager's theme.
- Files use same-directory temporary writes, fsync and atomic replace. Multi-file updates are journaled and rolled back; applications watching files may briefly observe intermediate values because there is no cross-application atomic commit API.
- Private snapshots and ownership records live under `$XDG_STATE_HOME/cedar/theming` (default `~/.local/state/cedar/theming`). They may contain private application settings and are written with restricted permissions. Keep this directory for recovery.

Existing matugen, pywal, wallust, Kvantum, KDE and Caelestia/Noctalia/Ryoku/Omarchy configuration is surfaced as possible ownership, not falsely described as proof of an active process. CEDAR does not disable these tools. Review the warning and select external/independent ownership when appropriate. A subsequent conflicting edit blocks synchronization instead of entering an overwrite loop.

## Tokens and controls

The semantic model includes `background.*`, `surface.*`, `text.*`, `accent.*`, `border.*`, `status.*`, and `terminal.{black,red,green,yellow,blue,magenta,cyan,white}` plus `terminal.bright.*`. Primary and secondary text must meet 4.5:1 contrast across base surfaces. Selection on accent uses a separately checked foreground. Contrast is a palette check, not a guarantee for every app's text, compositor blending or wallpaper.

Global settings include inheritance, variant, accent, font family/size, icon theme, supported opacity, wallpaper palettes, and locked accent. The UI provides per-adapter accent, variant and opacity overrides; additional supported overrides (fonts, fontFamily, fontSize, iconTheme and terminalPalette) are accepted by the same service in `overrides[adapterId]`. Shared toolkit overrides still apply to the whole toolkit. `terminalPalette` can independently pin any ANSI token. Font and icon packages must already be installed.

Wallpaper extraction uses ImageMagick if available, reads one image/frame with resource/time limits, and caches its quantized accent by content hash. It is not a Material You implementation. Minor changes within the same hue bucket do not change the result; animated wallpaper frames are not continuously sampled. CEDAR's existing wallpaper action and configured Omarchy wallpaper link produce events. External palette JSON files are watched directly.

## Compatibility matrix

Test labels: **F** = native output generation, repeated apply and exact reset exercised in isolated filesystem fixtures; **P** = preferences adapter exercised with mocked schema/profile and transactional dconf tests; **N** = installed application's native config validator passed; **I** = discovery/inheritance only. None means full application visual certification. Manual exports are explicitly marked and are not automatically active themes.

| Application / integration | Implemented method and capabilities | Reload / activation | Tests |
| --- | --- | --- | --- |
| Hyprland | Native border palette include; preserves window rules and animations (partial) | hypr-reload | F |
| KDE applications | KDE color scheme + owned kdeglobals keys (partial) | restart | F |
| Qt 5 configuration | qt5ct native palette; existing platform plugin required (partial) | restart | F |
| Qt 6 configuration | qt6ct native palette; existing platform plugin required (partial) | restart | F |
| GTK 3 appearance | GTK settings: native light/dark, icons and fonts (partial) | restart | F |
| GTK 4 / libadwaita | GSettings + desktop portal preferences, no CSS injection (light-dark) | portal | P |
| Alacritty | Owned native TOML appearance keys (full) | watch | F |
| Kitty | Native include + separate palette (full) | signal | F + N (Kitty parser) |
| Ghostty | Native config-file include (full) | manual-reload | F |
| Foot | Owned INI appearance keys (full) | restart | F + N (Foot 1.28) |
| Konsole | Native color scheme + selected profile appearance (full) | restart | F |
| WezTerm | Native TOML color scheme; select CEDAR in Lua config (requires-integration) | manual-select | F |
| GNOME Terminal | GSettings default terminal profile (full) | live | P |
| Tilix | GSettings default terminal profile (full) | live | P |
| XFCE Terminal | Owned INI color keys (full) | restart | F |
| Terminator | ConfigObj default profile palette file; manual import (requires-integration) | manual-select | F |
| xterm | Xresources palette; explicit xrdb merge required (requires-integration) | manual-select | F |
| VS Code | Owned JSONC workbench/terminal color customizations (partial) | watch | F |
| VSCodium | Owned JSONC workbench/terminal color customizations (partial) | watch | F |
| Neovim | Native runtime colorscheme; :colorscheme cedar (requires-integration) | manual-select | F |
| Helix | Native theme and theme selection (partial) | manual-reload | F |
| Emacs | Native deftheme file; load-theme cedar (requires-integration) | manual-select | F |
| Zed | Native theme file and JSONC theme selection (partial) | watch | F |
| Sublime Text | Native color scheme and selection (partial) | watch | F |
| JetBrains IDEs | Editor color scheme import; IDE chrome uses native settings (requires-integration) | manual-select | F |
| Rofi | Native Rasi theme include (partial) | next-launch | F |
| Wofi | Managed CSS import (partial) | next-launch | F |
| Fuzzel | Owned native INI appearance keys (full) | next-launch | F |
| Waybar | Managed CSS import; no layout changes (partial) | manual-reload | F |
| Eww | SCSS palette variables; widget integration required (requires-integration) | manual-select | F |
| Yazi | Owned native TOML theme keys (partial) | restart | F |
| Ranger | Terminal ANSI palette inheritance (partial) | terminal | I |
| Btop | Native theme file and color_theme selection (partial) | restart | F |
| Fastfetch | Terminal ANSI palette inheritance; preserves custom modules (partial) | terminal | I |
| Lazygit | Native YAML theme fragment; merge manually (requires-integration) | manual-select | F |
| Zathura | Native include for UI colors; document recoloring stays off (partial) | restart | F |
| SwayNotificationCenter | Native CSS import (partial) | reload | F |
| Mako | Owned appearance section (partial) | reload | F |
| Dunst | Owned global INI appearance keys (partial) | manual-reload | F |
| Firefox | System appearance; custom browser theme via supported extension (light-dark) | portal | I |
| Chromium browsers | Native GTK/system theme when selected in browser settings (light-dark) | portal | I |
| Thunderbird | System appearance when System theme is selected (light-dark) | portal | I |
| LibreOffice | Toolkit/system appearance; in-app theme selection may be needed (light-dark) | restart | I |
| OBS Studio | OBS native theme import is version-specific; not generated (unsupported) | none | Unsupported |
| VLC | Qt palette where its native widget UI supports it (partial) | restart | I |
| MPV | Owned native OSD color keys (partial) | restart | F |
| Spotify clients | Client-native appearance only; no Spicetify or binary patches (unsupported) | none | Unsupported |
| Discord clients | Client-native appearance only; no injected CSS/plugins (unsupported) | none | Unsupported |

KDE coverage includes Dolphin, Kate, KWrite, Okular, Gwenview, Ark, Spectacle, KCalc, KDE Partition Manager and KDE Connect through the shared color scheme. GTK 3 covers native GTK appearance for Thunar, Mousepad, Geany, GIMP, Inkscape and Transmission according to the toolkit used by the installed version. GTK preference consumers include Nautilus, GNOME Text Editor, Calculator, Disks, System Monitor and File Roller. Detection is evidence only, and does not certify a toolkit version or successful rendering.

### Native limitations

- KDE color roles and icon/font selection are available without installing a complete Plasma session. KDE Frameworks/style plugins still determine whether an application consumes them. qt5ct/qt6ct need their matching existing platform plugin; CEDAR reports an integration requirement if it is not selected. CEDAR does not globally set `QT_QPA_PLATFORMTHEME` or `QT_STYLE_OVERRIDE`, install a style plugin, or replace existing Kvantum SVG/config themes. These mechanisms are not interchangeable.
- GTK 3 uses Adwaita light/dark plus optional fonts/icons. It does not yet generate a custom full GTK 3 widget theme. Existing XSettings/theme overrides can take precedence. GTK 4/libadwaita receives supported color-scheme and, when exposed by the installed schema, the nearest available accent preference. No GTK 3 CSS is injected into libadwaita. Portal propagation requires a compatible running portal/settings backend; a successful preference write does not prove portal delivery.
- Flatpak apps are detected. Host native palette files are not written into sandboxes; no broad permissions or overrides are added. GTK appearance preferences may reach supported apps through their portal. Sandboxed app-specific native palette editing and theme package installation remain unsupported.
- Browsers, Thunderbird, LibreOffice and VLC use their existing system/toolkit appearance selection. No browser extension is installed and no `userChrome.css`, binary modification or Electron CSS injection is performed. Ranger and Fastfetch inherit terminal colors only; custom truecolor content is unchanged.
- WezTerm: select `color_scheme = 'CEDAR'` in existing Lua configuration. Neovim: `:colorscheme cedar` (native runtime export). Emacs: add the exported theme location to `custom-theme-load-path` and load `cedar`. Terminator, xterm, JetBrains, Eww and Lazygit exports need explicit native import/merge. Export paths appear in Preview, under the application's native directory or `~/.config/cedar/theming/exports`.
- Alacritty edits individual TOML appearance scalars because top-level user values can override imported palettes. Inline/dotted representations that cannot be edited unambiguously are refused. Kitty/Ghostty use separate includes. Existing behavior, bindings and extensions are preserved. Custom command-line config locations are not automatically inferred.
- Foot detects its installed version: 1.26+ uses `colors-dark`/`colors-light`; older configurations use `colors`. When installed, `foot --check-config` validates the complete proposed configuration. Existing obsolete or invalid Foot settings may need manual migration.
- Hyprland integrates only border colors using the existing Lua or conf file. It preserves rounding, blur, opacity, window rules, keybinds and animation settings. Ambiguous dual configurations require `CEDAR_HYPR_CONFIG`. Reload is requested and config errors are reported; no session restart is performed.
- CSS integrations are partial and existing application CSS can override the imported colors. Mako criteria sections and ambiguous parser constructs are deliberately refused. Full native parser validation is currently available for Foot; INI/TOML/JSONC are structurally validated. Generated Rasi/CSS/Lua/SCSS/export files still need application-specific graphical validation.
- Fonts/opacity may take effect only in new windows despite live color support. Reload acceptance is reported separately from observed visual success. No application is killed or automatically restarted.
- OBS, Spotify and Discord client internals remain unsupported. They are discovery rows, not placeholder adapters claiming to work.

## Validation and maintenance

Run:

```sh
python3 -m unittest discover -s tests -p test_theming.py
python3 tests/check_theming_ui.py
python3 tests/check_desktop_ui.py
```

The unit suite covers semantic contrast/variants, independent terminal tokens, every file adapter, native fixture preservation, missing apps/directories, Flatpak boundaries, overrides, invalid formats, stale preview, read-only paths, symlinks, later user edits, failed/interrupted transactions, restore/reset, preferences/profile schema checks, wallpaper caching and inherited theme events. Foot's installed parser is used when available. GUI checks render Settings in wide/narrow layouts and run the actual asynchronous Preview/Apply/Reset service against isolated settings.

Repository regression tests and release archive validation are additional gates. These tests do not certify full desktop handoff, portal propagation, KDE/GTK application screenshots, all application versions, or every distribution listed in the mission. CEDAR/Omarchy/CachyOS and other shell configurations use the same XDG/native engine, but distribution-wide visual qualification remains outstanding.

The service accepts one JSON request on stdin. `status`, `preview`, `apply` (with `options` and the exact `previewId`), `sync`, `restore`, `reset`, and `recover` return a JSON envelope. Public previews contain changed destinations, capability reports and palette tokens; backup contents are never returned to the settings UI.

## Native references

- [Alacritty configuration and import precedence](https://alacritty.org/config-alacritty.html)
- [Kitty configuration and reload](https://sw.kovidgoyal.net/kitty/conf/)
- [Ghostty configuration](https://ghostty.org/docs/config/reference)
- Foot installed `foot.ini(5)` and `/usr/share/doc/foot/CHANGELOG.md`; [upstream](https://codeberg.org/dnkl/foot)
- [libadwaita StyleManager](https://gnome.pages.gitlab.gnome.org/libadwaita/doc/main/class.StyleManager.html)
- [XDG desktop portals](https://flatpak.github.io/xdg-desktop-portal/docs/)
- [qt5ct appearance settings](https://github.com/desktop-app/qt5ct/blob/master/src/qt5ct/appearancepage.cpp), [qt6ct appearance settings](https://github.com/trialuser02/qt6ct/blob/master/src/qt6ct/appearancepage.cpp)
- [Helix themes](https://docs.helix-editor.com/master/themes.html), [Yazi themes](https://yazi-rs.github.io/docs/configuration/theme/), [Zed themes](https://zed.dev/docs/themes)
- [Tilix native schema](https://github.com/gnunn1/tilix/blob/master/data/gsettings/com.gexperts.Tilix.gschema.xml)
