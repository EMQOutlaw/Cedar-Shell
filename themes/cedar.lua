-- Generated from Theme.qml. Standalone Neovim colorscheme.
vim.cmd("highlight clear")
vim.o.background = "dark"
vim.g.colors_name = "cedar"
local c = {
  background = "#080F0D",
  surface = "#101E19",
  elevated = "#192D25",
  border = "#315C4D",
  green = "#9DFFB0",
  brightGreen = "#4DFF9A",
  teal = "#3FE0C5",
  amber = "#F2C879",
  ember = "#E58B73",
  text = "#E3F2E9",
  muted = "#A0B9AD",
  blue = "#89BFCB",
  violet = "#BBA9D6",
  brightEmber = "#FFAB91",
  brightAmber = "#FFE0A0",
  brightBlue = "#B4DEEA",
  brightViolet = "#D7C6EF",
  brightTeal = "#9AF4E1",
  white = "#F4FFF8",
}
local function hi(name, spec) vim.api.nvim_set_hl(0, name, spec) end
hi("Normal", {fg = c.text, bg = c.background})
hi("NormalFloat", {fg = c.text, bg = c.surface})
hi("FloatBorder", {fg = c.teal, bg = c.surface})
hi("FloatTitle", {fg = c.green, bg = c.surface})
hi("Comment", {fg = c.muted})
hi("Constant", {fg = c.amber})
hi("String", {fg = c.green})
hi("Number", {fg = c.amber})
hi("Boolean", {fg = c.amber})
hi("Identifier", {fg = c.text})
hi("Function", {fg = c.teal})
hi("Statement", {fg = c.green})
hi("Keyword", {fg = c.green})
hi("Operator", {fg = c.teal})
hi("PreProc", {fg = c.violet})
hi("Type", {fg = c.blue})
hi("Special", {fg = c.amber})
hi("Delimiter", {fg = c.muted})
hi("Error", {fg = c.ember, bg = c.surface})
hi("ErrorMsg", {fg = c.ember})
hi("WarningMsg", {fg = c.amber})
hi("Todo", {fg = c.amber, bg = c.surface})
hi("LineNr", {fg = c.muted})
hi("CursorLineNr", {fg = c.amber})
hi("CursorLine", {bg = c.surface})
hi("Cursor", {fg = c.background, bg = c.amber})
hi("Visual", {fg = c.text, bg = c.border})
hi("Search", {fg = c.background, bg = c.amber})
hi("IncSearch", {fg = c.background, bg = c.green})
hi("StatusLine", {fg = c.green, bg = c.surface})
hi("StatusLineNC", {fg = c.muted, bg = c.background})
hi("WinSeparator", {fg = c.border})
hi("Pmenu", {fg = c.text, bg = c.surface})
hi("PmenuSel", {fg = c.background, bg = c.green})
hi("PmenuSbar", {bg = c.border})
hi("PmenuThumb", {bg = c.teal})
hi("Directory", {fg = c.teal})
hi("Title", {fg = c.green})
hi("MatchParen", {fg = c.amber, bg = c.elevated})
hi("DiagnosticError", {fg = c.ember})
hi("DiagnosticWarn", {fg = c.amber})
hi("DiagnosticInfo", {fg = c.teal})
hi("DiagnosticHint", {fg = c.blue})
hi("DiffAdd", {fg = c.green, bg = c.elevated})
hi("DiffDelete", {fg = c.ember, bg = c.surface})
hi("DiffChange", {fg = c.amber, bg = c.surface})
hi("DiffText", {fg = c.text, bg = c.border})
hi("GitSignsAdd", {fg = c.green})
hi("GitSignsChange", {fg = c.amber})
hi("GitSignsDelete", {fg = c.ember})
hi("@variable", {fg = c.text})
hi("@function", {fg = c.teal})
hi("@keyword", {fg = c.green})
hi("@type", {fg = c.blue})
hi("@string", {fg = c.green})
vim.g.terminal_color_0 = c.background
vim.g.terminal_color_1 = c.ember
vim.g.terminal_color_2 = c.green
vim.g.terminal_color_3 = c.amber
vim.g.terminal_color_4 = c.blue
vim.g.terminal_color_5 = c.violet
vim.g.terminal_color_6 = c.teal
vim.g.terminal_color_7 = c.text
vim.g.terminal_color_8 = c.muted
vim.g.terminal_color_9 = c.brightEmber
vim.g.terminal_color_10 = c.brightGreen
vim.g.terminal_color_11 = c.brightAmber
vim.g.terminal_color_12 = c.brightBlue
vim.g.terminal_color_13 = c.brightViolet
vim.g.terminal_color_14 = c.brightTeal
vim.g.terminal_color_15 = c.white
