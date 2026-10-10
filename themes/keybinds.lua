-- CEDAR keybinds, Caelestia layout, for Hyprland's Lua configuration.
--
-- The installer copies this file to ~/.config/cedar/hypr/keybinds.lua and
-- CEDAR's generated.lua loads it; that copy is yours to edit. Every bind
-- here first unbinds the same keys, so it wins over an earlier binding on
-- the same combination and leaves every other binding alone. The shell
-- actions reach the CEDAR that owns the `cedar` Quickshell profile (release
-- or checkout) over IPC; the app bindings open the terminal, browser, editor and file manager chosen in
-- CEDAR Settings (imported from your previous setup when it had them).

local home = os.getenv("HOME") or ""
local data = os.getenv("XDG_DATA_HOME") or (home .. "/.local/share")
local cedar = home .. "/.local/bin/cedar"

-- Quickshell matches a running instance by its config path. The live shell is
-- whatever owns the `cedar` profile (the installed release, or a checkout
-- linked there), so address it by profile, run its scripts, and fall back to
-- the release only when no profile exists. Mirrors shell_selector in
-- scripts/distribution.py.
local config = os.getenv("XDG_CONFIG_HOME") or (home .. "/.config")
local root = data .. "/cedar/current"
local qs = "qs -p " .. root .. "/shell.qml"
do
  local profile = io.open(config .. "/quickshell/cedar/shell.qml", "r")
  if profile then profile:close(); qs = "qs -c cedar"; root = config .. "/quickshell/cedar" end
end
local runtime = root .. "/scripts/desktop_runtime.py"

local function ipc(args) return hl.dsp.exec_cmd(qs .. " ipc call " .. args) end
local function launch(kind) return hl.dsp.exec_cmd("python3 " .. runtime .. " launch " .. kind) end
local function command(args) return hl.dsp.exec_cmd(cedar .. " " .. args) end

local function bind(keys, action, description, flags)
  local options = {}
  for key, value in pairs(flags or {}) do options[key] = value end
  options.description = description
  hl.unbind(keys)
  hl.bind(keys, action, options)
end
local function each(list, action, description, flags)
  for _, keys in ipairs(list) do bind(keys, action, description, flags) end
end

local locked = { locked = true }
local repeating = { repeating = true }
local locked_repeating = { locked = true, repeating = true }
local mouse = { mouse = true }
local release = { release = true }

-- CEDAR
bind("SUPER + SUPER_L", ipc("menu toggle apps"), "CEDAR applications", release)
bind("SUPER + SPACE", ipc("menu toggle apps"), "CEDAR applications")
bind("SUPER + SHIFT + SPACE", ipc("menu toggle root"), "CEDAR Go menu")
bind("SUPER + N", ipc("control toggle"), "Quick Controls")
bind("SUPER + K", ipc("hud toggle"), "Field Station")
bind("SUPER + SHIFT + N", ipc("notifications toggle"), "Notifications")
bind("CTRL + ALT + C", ipc("notifications dismissAll"), "Clear notifications", locked)
bind("CTRL + ALT + Delete", ipc("power toggle"), "Power")
bind("SUPER + L", ipc("lock lock"), "Lock")
bind("SUPER + ALT + L", command("lock"), "Lock (session locker)")
bind("SUPER + SHIFT + L", command("lock --suspend"), "Lock and suspend", locked)
bind("SUPER + ALT + P", ipc("settings toggle"), "CEDAR Settings")
bind("SUPER + G", ipc("gaming toggle"), "Gaming Mode")
bind("SUPER + SHIFT + P", ipc("profiles open"), "Desktop Profiles")
bind("SUPER + SHIFT + F", ipc("focus open"), "Focus")
bind("SUPER + SHIFT + H", ipc("station open"), "Station (health)")
bind("SUPER + TAB", ipc("canopy flip workspaces"), "Workspace overview")
bind("SUPER + V", ipc("canopy open clipboard"), "Clipboard")
bind("SUPER + ALT + V", ipc("canopy open clipboard"), "Clipboard")
bind("CTRL + ALT + V", ipc("canopy open audio"), "Audio")

-- Applications
bind("SUPER + T", launch("terminal"), "Terminal")
bind("SUPER + W", launch("browser"), "Browser")
bind("SUPER + C", launch("editor"), "Editor")
bind("SUPER + E", launch("files"), "Files")

-- Capture
bind("Print", ipc("menu toggle capture"), "Capture", locked)
each({ "SUPER + SHIFT + S", "SUPER + SHIFT + ALT + S" }, ipc("menu toggle capture"), "Capture")
each({ "CTRL + ALT + R", "SUPER + ALT + R", "SUPER + SHIFT + ALT + R" }, ipc("menu toggle capture"), "Record")
bind("SUPER + SHIFT + C", hl.dsp.exec_cmd("hyprpicker -a"), "Color picker")

-- Workspaces
for i = 1, 10 do
  local key = tostring(i % 10)
  bind("SUPER + " .. key, hl.dsp.focus({ workspace = i }), "Workspace " .. i)
  bind("SUPER + ALT + " .. key, hl.dsp.window.move({ workspace = i }), "Move window to workspace " .. i)
  bind("CTRL + SUPER + " .. key, hl.dsp.focus({ workspace = i + 10 }), "Workspace " .. (i + 10))
  bind("CTRL + SUPER + ALT + " .. key, hl.dsp.window.move({ workspace = i + 10 }), "Move window to workspace " .. (i + 10))
end
each({ "CTRL + SUPER + Right", "SUPER + Page_Down" }, hl.dsp.focus({ workspace = "+1" }), "Next workspace", repeating)
each({ "CTRL + SUPER + Left", "SUPER + Page_Up" }, hl.dsp.focus({ workspace = "-1" }), "Previous workspace", repeating)
bind("SUPER + mouse_down", hl.dsp.focus({ workspace = "+1" }), "Next workspace")
bind("SUPER + mouse_up", hl.dsp.focus({ workspace = "-1" }), "Previous workspace")
bind("CTRL + SUPER + mouse_down", hl.dsp.focus({ workspace = "+10" }), "Next workspace group")
bind("CTRL + SUPER + mouse_up", hl.dsp.focus({ workspace = "-10" }), "Previous workspace group")
each({ "SUPER + ALT + Page_Down", "CTRL + SUPER + SHIFT + Right" }, hl.dsp.window.move({ workspace = "+1" }), "Move window to next workspace", repeating)
each({ "SUPER + ALT + Page_Up", "CTRL + SUPER + SHIFT + Left" }, hl.dsp.window.move({ workspace = "-1" }), "Move window to previous workspace", repeating)
bind("SUPER + ALT + mouse_down", hl.dsp.window.move({ workspace = "+1" }), "Move window to next workspace")
bind("SUPER + ALT + mouse_up", hl.dsp.window.move({ workspace = "-1" }), "Move window to previous workspace")

-- Special workspaces
bind("SUPER + S", hl.dsp.workspace.toggle_special("special"), "Special workspace")
each({ "SUPER + ALT + S", "CTRL + SUPER + SHIFT + Up" }, hl.dsp.window.move({ workspace = "special:special" }), "Move window to special workspace")
bind("CTRL + SUPER + SHIFT + Down", hl.dsp.window.move({ workspace = "e+0" }), "Move window out of special workspace")
bind("SUPER + M", hl.dsp.workspace.toggle_special("music"), "Music workspace")
bind("SUPER + D", hl.dsp.workspace.toggle_special("communication"), "Communication workspace")
bind("SUPER + R", hl.dsp.workspace.toggle_special("todo"), "Todo workspace")
bind("CTRL + SHIFT + Escape", ipc("hud toggle"), "System monitor (Field Station)")

-- Windows
for _, direction in ipairs({ "left", "right", "up", "down" }) do
  bind("SUPER + " .. direction, hl.dsp.focus({ direction = direction }), "Focus " .. direction)
  bind("SUPER + SHIFT + " .. direction, hl.dsp.window.move({ direction = direction }), "Move window " .. direction)
end
local function resize(x, y)
  return hl.dsp.window.resize({ x = x, y = y, relative = true })
end
each({ "SUPER + Minus", "SUPER + ALT + Left" }, resize(-40, 0), "Narrower", repeating)
each({ "SUPER + Equal", "SUPER + ALT + Right" }, resize(40, 0), "Wider", repeating)
each({ "SUPER + SHIFT + Minus", "SUPER + ALT + Up" }, resize(0, -40), "Shorter", repeating)
each({ "SUPER + SHIFT + Equal", "SUPER + ALT + Down" }, resize(0, 40), "Taller", repeating)
each({ "SUPER + Z", "SUPER + mouse:272" }, hl.dsp.window.drag(), "Move window", mouse)
each({ "SUPER + X", "SUPER + mouse:273" }, hl.dsp.window.resize(), "Resize window", mouse)
bind("CTRL + SUPER + Backslash", hl.dsp.window.center(), "Center window")
bind("SUPER + P", hl.dsp.window.pin(), "Pin window")
bind("SUPER + F", hl.dsp.window.fullscreen({ mode = "fullscreen" }), "Fullscreen")
bind("SUPER + ALT + F", hl.dsp.window.fullscreen({ mode = "maximized" }), "Maximize")
bind("SUPER + ALT + Space", hl.dsp.window.float({ action = "toggle" }), "Float window")
bind("SUPER + Q", hl.dsp.window.close(), "Close window")

-- Groups
bind("ALT + Tab", hl.dsp.window.cycle_next(), "Next window", repeating)
bind("SHIFT + ALT + Tab", hl.dsp.window.cycle_next({ next = false }), "Previous window", repeating)
bind("CTRL + ALT + Tab", hl.dsp.group.next(), "Next in group", repeating)
bind("CTRL + SHIFT + ALT + Tab", hl.dsp.group.prev(), "Previous in group", repeating)
bind("SUPER + Comma", hl.dsp.group.toggle(), "Toggle group")
bind("SUPER + SHIFT + Comma", hl.dsp.group.lock_active(), "Lock group")
bind("SUPER + U", hl.dsp.window.move({ out_of_group = true }), "Leave group")

-- Media and volume
each({ "CTRL + SUPER + Space", "XF86AudioPlay", "XF86AudioPause" }, ipc("media toggle"), "Play / pause", locked)
each({ "CTRL + SUPER + Equal", "XF86AudioNext" }, ipc("media next"), "Next track", locked)
each({ "CTRL + SUPER + Minus", "XF86AudioPrev" }, ipc("media previous"), "Previous track", locked)
each({ "CTRL + SUPER + Backspace", "XF86AudioStop" }, ipc("media pause"), "Stop", locked)
each({ "SUPER + SHIFT + M", "XF86AudioMute" }, ipc("osd mute"), "Mute", locked)
bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), "Mute microphone", locked)
bind("XF86AudioRaiseVolume", ipc("osd volume 5"), "Volume up", locked_repeating)
bind("XF86AudioLowerVolume", ipc("osd volume -5"), "Volume down", locked_repeating)
bind("XF86MonBrightnessUp", ipc("osd brightness 5"), "Brightness up", locked_repeating)
bind("XF86MonBrightnessDown", ipc("osd brightness -5"), "Brightness down", locked_repeating)
