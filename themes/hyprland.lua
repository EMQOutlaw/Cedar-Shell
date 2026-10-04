-- CEDAR palette for Hyprland with Lua configuration support.
-- Optional: include from your own configuration. Does not change startup or keys.
hl.config({
  general = { border_size = 1, col = {
    active_border = { colors = { "#9DFFB0", "#3FE0C5" }, angle = 45 },
    inactive_border = "#315C4D",
  } },
  decoration = { rounding = 3, blur = { enabled = true, size = 6, passes = 2 } },
})
hl.layer_rule({ match = { namespace = "^cedar-.*$" }, blur = true, ignore_alpha = 0.1 })
