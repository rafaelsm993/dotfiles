 local M = {}

function M.setup()
  require('base16-colorscheme').setup({
    base00 = '#162127',
    base01 = '#243842',
    base02 = '#21323b',
    base03 = '#616b70',
    base04 = '#afb4b6',
    base05 = '#f2f2f3',
    base06 = '#f2f2f3',
    base07 = '#f2f2f3',
    base08 = '#fd4663',
    base09 = '#8966cc',
    base0A = '#5c6fd6',
    base0B = '#67bae4',
    base0C = '#b296e9',
    base0D = '#93ceec',
    base0E = '#96a3e9',
    base0F = '#bec6f4',
  })

  local hi = function(group, opts)
    vim.api.nvim_set_hl(0, group, opts)
  end

  -- telescope.nvim
  hi('TelescopeNormal',         { fg = '#f2f2f3',          bg = '#162127' })
  hi('TelescopeBorder',         { fg = '#616b70',             bg = '#162127' })
  hi('TelescopePromptNormal',   { fg = '#f2f2f3',          bg = '#162127' })
  hi('TelescopePromptBorder',   { fg = '#616b70',             bg = '#162127' })
  hi('TelescopePromptPrefix',   { fg = '#67bae4',             bg = '#162127' })
  hi('TelescopePromptCounter',  { fg = '#afb4b6',  bg = '#162127' })
  hi('TelescopePromptTitle',    { fg = '#162127',             bg = '#67bae4' })
  hi('TelescopePreviewTitle',   { fg = '#162127',             bg = '#5c6fd6' })
  hi('TelescopeResultsTitle',   { fg = '#162127',             bg = '#8966cc' })
  hi('TelescopeSelection',      { fg = '#f2f2f3',          bg = '#21323b' })
  hi('TelescopeSelectionCaret', { fg = '#67bae4',             bg = '#21323b' })
  hi('TelescopeMatching',       { fg = '#67bae4',             bold = true })

  -- mini.pick
  hi('MiniPickNormal',         { fg = '#f2f2f3',          bg = '#162127' })
  hi('MiniPickBorder',         { fg = '#616b70',             bg = '#162127' })
  hi('MiniPickPrompt',   { fg = '#f2f2f3',          bg = '#162127' })
  hi('MiniPickPromptPrefix',   { fg = '#67bae4',             bg = '#162127' })
  hi('MiniPickBorderText',    { fg = '#162127',             bg = '#67bae4' })
  hi('MiniPickMatchCurrent',      { fg = '#f2f2f3',          bg = '#21323b' })
  hi('MiniPickPromptCaret', { fg = '#67bae4',             bg = '#21323b' })
  hi('MiniPickMatchRanges',       { fg = '#67bae4',             bold = true })
end

-- Register a signal handler for SIGUSR1 (matugen updates).
-- The handler re-requires this module, which re-runs the code below, so the
-- previous handle is stopped first; otherwise handlers double on every signal.
if _G.__matugen_signal then
  _G.__matugen_signal:stop()
  _G.__matugen_signal:close()
end

local signal = vim.uv.new_signal()
_G.__matugen_signal = signal
signal:start(
  'sigusr1',
  vim.schedule_wrap(function()
    package.loaded['matugen'] = nil
    require('matugen').setup()
  end)
)

return M
