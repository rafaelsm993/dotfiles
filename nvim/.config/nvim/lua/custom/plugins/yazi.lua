---@type LazySpec
return {
  "mikavilpas/yazi.nvim",
  version = "*", -- use the latest stable version
  event = "VeryLazy",
  dependencies = {
    { "nvim-lua/plenary.nvim", lazy = true },
  },
  keys = {
    -- 👇 in this section, choose your own keymappings!
    {
      "<leader>-",
      mode = { "n", "v" },
      "<cmd>Yazi<cr>",
      desc = "Open yazi at the current file",
    },
    {
      -- Open in the current working directory
      "<leader>cw",
      "<cmd>Yazi cwd<cr>",
      desc = "Open the file manager in nvim's working directory",
    },
    {
      "<c-up>",
      "<cmd>Yazi toggle<cr>",
      desc = "Resume the last yazi session",
    },
  },
  ---@type YaziConfig | {}
  opts = {
    -- if you want to open yazi instead of netrw, see below for more info
    open_for_directories = false,
    keymaps = {
      show_help = "<f1>",
    },
  },
  -- 👇 if you use `open_for_directories=true`, this is recommended
  init = function()
    if vim.fn.has "win32" == 1 then
      local paths = {
        vim.fn.expand "$LOCALAPPDATA" .. "\\Microsoft\\WinGet\\Packages\\sxyazi.yazi_Microsoft.Winget.Source_8wekyb3d8bbwe\\yazi-x86_64-pc-windows-msvc",
        "C:\\Program Files\\Git\\usr\\bin", -- provides file.exe, required by yazi MIME detection on Windows
      }
      for _, path in ipairs(paths) do
        if vim.fn.isdirectory(path) == 1 and not vim.env.PATH:find(path, 1, true) then
          vim.env.PATH = path .. ";" .. vim.env.PATH
        end
      end
    end

    -- mark netrw as loaded so it's not loaded at all.
    --
    -- More details: https://github.com/mikavilpas/yazi.nvim/issues/802
    vim.g.loaded_netrwPlugin = 1
  end,
}