# Community themes

Open **Settings → Appearance → Themes**, choose a tile to preview it, then
**Apply theme**. **Cancel preview** leaves the desktop unchanged.
**Restore previous theme** restores the previous palette exactly.

CEDAR ships these palettes without a download or external theme manager:

| Family | Variants | Palette source |
|---|---|---|
| Catppuccin | Mocha, Macchiato, Frappé, Latte (light) | [Catppuccin palette](https://github.com/catppuccin/palette) |
| Rosé Pine | Rosé Pine, Moon, Dawn (light) | [Rosé Pine palette](https://github.com/rose-pine/rose-pine-palette) |
| Tokyo Night | Night, Storm, Day (light) | [TokyoNight](https://github.com/folke/tokyonight.nvim) |
| Nord | Dark | [Nord](https://github.com/nordtheme/nord) |
| Decay Green | Dark Decay with green accents | [Decay](https://github.com/decaycs/decaycs) |
| Gruvbox | Dark, Light | [Gruvbox](https://github.com/morhetz/gruvbox) |
| Dracula | Dark | [Dracula](https://github.com/dracula/dracula-theme) |
| Everforest | Dark, medium background | [Everforest](https://github.com/sainnhe/everforest) |

These are CEDAR adaptations of the upstream color palettes. The shell's primary
accent follows each family's character: mauve for Catppuccin, rose for Rosé
Pine, blue for Tokyo Night, frost for Nord, and green for Decay and Everforest.
The historical `green` token is the primary accent and need not be green.
The Colors tab offers four accent choices from the selected palette.

Every palette defines all 27 shell tokens, including charts, bright accents and
Field Notes paper. Paper stays light, with a tint matching the palette family.
Foregrounds are adjusted where needed to keep normal and secondary text at
least 4.5:1 against all three opaque shell surfaces. CEDAR's surface layering and
paper colors are adaptations, not additional official upstream colors.

The same collection appears under **Application Theming** presets. That page's
existing preview/apply and per-application controls govern application files;
selecting a shell theme alone changes CEDAR's palette.

## Personal palettes

Place a JSON file in `$XDG_CONFIG_HOME/cedar/themes/` (normally
`~/.config/cedar/themes/`). Use any subset of the tokens in [PALETTE.md](PALETTE.md):

```json
{
  "name": "My evening palette",
  "mode": "dark",
  "colors": {
    "background": "#181a24",
    "green": "#c5a6ed",
    "blue": "#89b4fa"
  }
}
```

Names in the picker come from `name`; the filename without `.json` is its ID.
Missing tokens use CEDAR's defaults. A valid personal file with the same ID as
a bundled palette replaces that entry. Invalid files are ignored. `cedar` is
reserved as the reset to CEDAR's original palette.

Colors must be six-digit hex values and `mode`, when provided, must be `dark`
or `light`. Bundled palettes are in `themes/palettes/`; each records its source.
Upstream license notices are in `themes/licenses/`. Decay's repository provides
the color reference without a license file; only its palette values are used,
not its code or artwork. Gruvbox declares MIT/X11 in its upstream README.
