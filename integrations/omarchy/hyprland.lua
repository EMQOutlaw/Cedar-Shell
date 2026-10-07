-- Generated palette; theme-scoped bindings. Hyprland 0.55+ / Omarchy.
hl.config({
  general = { border_size = 1, col = {
    active_border = { colors = { "#9DFFB0", "#3FE0C5" }, angle = 45 },
    inactive_border = "#315C4D",
  } },
  decoration = { rounding = 3, blur = { enabled = true, size = 6, passes = 2 } },
})
hl.layer_rule({ match = { namespace = "^cedar-.*$" }, blur = true, ignore_alpha = 0.1 })
local function bind(key, description, command, flags)
  hl.unbind(key)
  o.bind(key, description, command, flags)
end
bind("SUPER + ALT + F", "CEDAR HUD", "qs -c cedar ipc call hud toggle")
-- Go menu: Omarchy's menu tree rendered by CEDAR, with apps merged in.
bind("SUPER + SPACE", "CEDAR Go menu", "qs -c cedar ipc call menu toggle root")
bind("SUPER + SHIFT + code:201", "CEDAR Go menu", "qs -c cedar ipc call menu toggle root")
bind("SUPER + ALT + SPACE", "CEDAR apps", "qs -c cedar ipc call menu toggle apps")
bind("SUPER + CTRL + C", "CEDAR capture menu", "qs -c cedar ipc call menu toggle capture")
bind("SUPER + CTRL + O", "CEDAR toggle menu", "qs -c cedar ipc call menu toggle toggle")
bind("SUPER + CTRL + H", "CEDAR hardware menu", "qs -c cedar ipc call menu toggle hardware")
bind("SUPER + CTRL + S", "CEDAR share menu", "qs -c cedar ipc call menu toggle share")
bind("SUPER + ALT + P", "CEDAR settings", "qs -c cedar ipc call settings toggle")
bind("SUPER + G", "CEDAR Gaming Mode", "qs -c cedar ipc call gaming toggle")
-- Omarchy helpers that prompt through the shell menu run with CEDAR's stand-in on PATH.
local with_shim = '"${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/cedar/scripts/with-shim" '
bind("SUPER + K", "Keybindings", with_shim .. "omarchy-menu-keybindings")
bind("SUPER + ALT + K", "Tmux keybindings", with_shim .. "omarchy-menu-tmux-keybindings")
bind("SUPER + CTRL + K", "Herdr keybindings", with_shim .. "omarchy-menu-herdr-keybindings")
bind("SUPER + CTRL + R", "Set reminder", with_shim .. "omarchy-reminder -i")
bind("SUPER + ESCAPE", "CEDAR power", "qs -c cedar ipc call power toggle")
bind("XF86PowerOff", "CEDAR power", "qs -c cedar ipc call power toggle", { locked = true })
bind("SUPER + ALT + L", "CEDAR lock", "qs -c cedar ipc call lock lock")
bind("SUPER + SHIFT + CTRL + SPACE", "CEDAR themes", "qs -c cedar ipc call themes toggle")
bind("SUPER + CTRL + SPACE", "CEDAR wallpaper picker", "qs -c cedar ipc call wallpapers toggle")
bind("SUPER + CTRL + L", "CEDAR lock", "qs -c cedar ipc call lock lock")
bind("SUPER + SHIFT + ALT + comma", "CEDAR history", "qs -c cedar ipc call notifications toggle")
bind("XF86AudioRaiseVolume", "Volume up", "qs -c cedar ipc call osd volume 5", { repeating = true })
bind("XF86AudioLowerVolume", "Volume down", "qs -c cedar ipc call osd volume -5", { repeating = true })
bind("XF86AudioMute", "Mute", "qs -c cedar ipc call osd mute")
bind("XF86MonBrightnessUp", "Brightness up", "qs -c cedar ipc call osd brightness 5", { repeating = true })
bind("XF86MonBrightnessDown", "Brightness down", "qs -c cedar ipc call osd brightness -5", { repeating = true })
bind("XF86AudioPlay", "Media toggle", "qs -c cedar ipc call media toggle")
bind("XF86AudioPause", "Media pause", "qs -c cedar ipc call media pause")
bind("XF86AudioNext", "Media next", "qs -c cedar ipc call media next")
bind("XF86AudioPrev", "Media previous", "qs -c cedar ipc call media previous")
-- The theme-set and post-boot hooks manage the shell's lifetime.
-- Never add an unconditional CEDAR exec-once to the global configuration.
