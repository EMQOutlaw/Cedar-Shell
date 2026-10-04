-- Omarchy / LazyVim adapter; applied only when this theme is selected.
return {
  { "LazyVim/LazyVim", opts = { colorscheme = function()
      dofile((os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")) .. "/quickshell/cedar/themes/cedar.lua")
  end } },
}
