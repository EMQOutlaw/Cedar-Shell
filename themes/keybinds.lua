-- CEDAR keybinds for Hyprland's Lua configuration.
--
-- Generated from data/keybinds.json by scripts/keybinds.py; edit the
-- definition and run `python3 scripts/keybinds.py --write`. The installer
-- copies this file to ~/.config/cedar/hypr/keybinds.lua and CEDAR's
-- generated.lua loads it. Every bind first unbinds the same keys, so it wins
-- over an earlier binding on that combination and leaves every other binding
-- alone. Personal changes go in user.lua (loaded last) or Settings > Keybinds.
-- The shell actions reach the CEDAR that owns the `cedar` Quickshell profile
-- (release or checkout) over IPC; the app bindings open the terminal, browser
-- and file manager chosen in CEDAR Settings.

local home = os.getenv("HOME") or ""
local data = os.getenv("XDG_DATA_HOME") or (home .. "/.local/share")

-- Quickshell matches a running instance by its config path. The live shell is
-- whatever owns the `cedar` profile (the installed release, or a checkout
-- linked there), so address it by profile, run its scripts, and fall back to
-- the release only when no profile exists. Mirrors shell_selector in
-- scripts/distribution.py.
local config = os.getenv("XDG_CONFIG_HOME") or (home .. "/.config")
local root = data .. "/cedar/current"
local qs = 'qs -p "$(readlink -f ' .. root .. '/shell.qml)"' 
do
  local profile = io.open(config .. "/quickshell/cedar/shell.qml", "r")
  if profile then profile:close(); qs = "qs -c cedar"; root = config .. "/quickshell/cedar" end
end
local runtime = root .. "/scripts/desktop_runtime.py"

local function ipc(args) return hl.dsp.exec_cmd(qs .. " ipc call " .. args) end
local function launch(kind) return hl.dsp.exec_cmd("python3 " .. runtime .. " launch " .. kind) end
local function clipboard(kind) return hl.dsp.exec_cmd("python3 " .. runtime .. " clipboard " .. kind) end

local function bind(keys, action, description, flags)
  local options = {}
  for key, value in pairs(flags or {}) do options[key] = value end
  options.description = description
  hl.unbind(keys)
  hl.bind(keys, action, options)
end

-- Applications
bind("SUPER + SPACE", ipc("menu toggle apps"), "Toggle the application launcher")
bind("SUPER + T", launch("terminal"), "Open the terminal chosen in Settings")
bind("SUPER + W", launch("browser"), "Open the browser chosen in Settings")
bind("SUPER + E", launch("files"), "Open the file manager chosen in Settings")
bind("SUPER + C", clipboard("copy"), "Unified copy (Ctrl+C, or Ctrl+Shift+C in a terminal)")
bind("SUPER + X", clipboard("cut"), "Unified cut where the window supports it (Ctrl+X; nothing in a terminal)")
bind("SUPER + V", clipboard("paste"), "Unified paste (Ctrl+V, or Ctrl+Shift+V in a terminal)")
bind("SUPER + SHIFT + V", ipc("canopy flip clipboard"), "Toggle clipboard history")
bind("SUPER + SHIFT + K", ipc("keymap show"), "Show the searchable active keymap")
bind("SUPER + CTRL + ALT + SPACE", ipc("wallpapers toggle"), "Choose a wallpaper from the rounded preview grid")
bind("SUPER + ALT + N", ipc("notes toggle"), "Toggle Field Notes, the floating sheet for sketches and typed notes")

-- Windows
bind("SUPER + Q", hl.dsp.window.close(), "Close the focused window")
bind("SUPER + F", hl.dsp.window.fullscreen({ mode = "fullscreen" }), "Toggle fullscreen for the focused window")
bind("SUPER + ALT + SPACE", hl.dsp.window.float({ action = "toggle" }), "Toggle the focused window between floating and tiled")
bind("SUPER + left", hl.dsp.focus({ direction = "l" }), "Focus the window to the left")
bind("SUPER + right", hl.dsp.focus({ direction = "r" }), "Focus the window to the right")
bind("SUPER + up", hl.dsp.focus({ direction = "u" }), "Focus the window to the top")
bind("SUPER + down", hl.dsp.focus({ direction = "d" }), "Focus the window to the bottom")
bind("SUPER + SHIFT + left", hl.dsp.window.move({ direction = "l" }), "Move the focused window left")
bind("SUPER + SHIFT + right", hl.dsp.window.move({ direction = "r" }), "Move the focused window right")
bind("SUPER + SHIFT + up", hl.dsp.window.move({ direction = "u" }), "Move the focused window up")
bind("SUPER + SHIFT + down", hl.dsp.window.move({ direction = "d" }), "Move the focused window down")
bind("SUPER + mouse:272", hl.dsp.window.drag(), "Move a window by dragging it with the left button", { mouse = true })
bind("SUPER + mouse:273", hl.dsp.window.resize(), "Resize a window by dragging with the right button", { mouse = true })

-- Workspaces
bind("SUPER + 1", hl.dsp.focus({ workspace = "1" }), "Switch to workspace 1")
bind("SUPER + 2", hl.dsp.focus({ workspace = "2" }), "Switch to workspace 2")
bind("SUPER + 3", hl.dsp.focus({ workspace = "3" }), "Switch to workspace 3")
bind("SUPER + 4", hl.dsp.focus({ workspace = "4" }), "Switch to workspace 4")
bind("SUPER + 5", hl.dsp.focus({ workspace = "5" }), "Switch to workspace 5")
bind("SUPER + 6", hl.dsp.focus({ workspace = "6" }), "Switch to workspace 6")
bind("SUPER + 7", hl.dsp.focus({ workspace = "7" }), "Switch to workspace 7")
bind("SUPER + 8", hl.dsp.focus({ workspace = "8" }), "Switch to workspace 8")
bind("SUPER + 9", hl.dsp.focus({ workspace = "9" }), "Switch to workspace 9")
bind("SUPER + 0", hl.dsp.focus({ workspace = "10" }), "Switch to workspace 10")
bind("SUPER + SHIFT + 1", hl.dsp.window.move({ workspace = "1" }), "Send the focused window to workspace 1 and follow it")
bind("SUPER + SHIFT + 2", hl.dsp.window.move({ workspace = "2" }), "Send the focused window to workspace 2 and follow it")
bind("SUPER + SHIFT + 3", hl.dsp.window.move({ workspace = "3" }), "Send the focused window to workspace 3 and follow it")
bind("SUPER + SHIFT + 4", hl.dsp.window.move({ workspace = "4" }), "Send the focused window to workspace 4 and follow it")
bind("SUPER + SHIFT + 5", hl.dsp.window.move({ workspace = "5" }), "Send the focused window to workspace 5 and follow it")
bind("SUPER + SHIFT + 6", hl.dsp.window.move({ workspace = "6" }), "Send the focused window to workspace 6 and follow it")
bind("SUPER + SHIFT + 7", hl.dsp.window.move({ workspace = "7" }), "Send the focused window to workspace 7 and follow it")
bind("SUPER + SHIFT + 8", hl.dsp.window.move({ workspace = "8" }), "Send the focused window to workspace 8 and follow it")
bind("SUPER + SHIFT + 9", hl.dsp.window.move({ workspace = "9" }), "Send the focused window to workspace 9 and follow it")
bind("SUPER + SHIFT + 0", hl.dsp.window.move({ workspace = "10" }), "Send the focused window to workspace 10 and follow it")

-- Scratchpad
bind("SUPER + S", hl.dsp.workspace.toggle_special("special"), "Show or hide the scratchpad")
bind("SUPER + ALT + S", hl.dsp.window.move({ workspace = "special:special", follow = false }), "Send the focused window to the scratchpad and stay on this workspace")

-- Capture
bind("SUPER + P", ipc("menu toggle capture"), "Open the screenshot menu")
bind("Print", ipc("menu toggle capture"), "Open the screenshot menu (Print Screen key)", { locked = true })

-- Session
bind("SUPER + L", ipc("lock lock"), "Lock the session with Trailwatch")
bind("SUPER + Escape", ipc("power toggle"), "Toggle the power and session menu")
bind("SUPER + Comma", ipc("settings toggle"), "Toggle CEDAR Settings")
bind("SUPER + K", ipc("canopy flip keybinds"), "Toggle this keybind reference")

-- Media and hardware
bind("XF86AudioPlay", ipc("media toggle"), "Play or pause", { locked = true })
bind("XF86AudioPause", ipc("media toggle"), "Play or pause", { locked = true })
bind("CTRL + SUPER + SPACE", ipc("media toggle"), "Play or pause", { locked = true })
bind("XF86AudioNext", ipc("media next"), "Next track", { locked = true })
bind("CTRL + SUPER + Equal", ipc("media next"), "Next track", { locked = true })
bind("XF86AudioPrev", ipc("media previous"), "Previous track", { locked = true })
bind("CTRL + SUPER + Minus", ipc("media previous"), "Previous track", { locked = true })
bind("XF86AudioStop", ipc("media pause"), "Stop playback", { locked = true })
bind("CTRL + SUPER + Backspace", ipc("media pause"), "Stop playback", { locked = true })
bind("XF86AudioMute", ipc("osd mute"), "Mute or unmute the output", { locked = true })
bind("SUPER + SHIFT + M", ipc("osd mute"), "Mute or unmute the output", { locked = true })
bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), "Mute or unmute the microphone", { locked = true })
bind("XF86AudioRaiseVolume", ipc("osd volume 5"), "Volume up", { locked = true, repeating = true })
bind("XF86AudioLowerVolume", ipc("osd volume -5"), "Volume down", { locked = true, repeating = true })
bind("XF86MonBrightnessUp", ipc("osd brightness 5"), "Brightness up", { locked = true, repeating = true })
bind("XF86MonBrightnessDown", ipc("osd brightness -5"), "Brightness down", { locked = true, repeating = true })
