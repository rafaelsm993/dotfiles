# Copilot Instructions

## Repository Overview

Personal dotfiles for **kanoah** targeting Arch Linux (CachyOS native + WSL2). Contains configurations for: Neovim, Fish shell, FastFetch, WezTerm, Hyprland, Noctalia, and mise.

## Bootstrap scripts

A fresh machine is provisioned by `./bootstrap.sh` (POSIX shim that installs fish, then hands off to `bootstrap.fish`). `bootstrap.fish` runs nine idempotent phases: `packages wslconf stow mise npm omp shell git verify`.

```bash
./bootstrap.sh --dry-run        # preview, changes nothing
./bootstrap.fish --only stow    # run one phase
./bootstrap.fish --skip packages
```

Supporting files — edit these rather than the script:
- `scripts/packages.txt` — pacman packages
- `scripts/npm-globals.txt` — global npm packages
- `scripts/wsl.conf.template` — `/etc/wsl.conf`; `__USER__` is replaced with `whoami` at run time
- `scripts/lib.fish` — logging, `--dry-run` plumbing, and `pkg_installed` (group-aware: `pacman -Qq` fails on groups like `base-devel`, so it falls back to `pacman -Sqg` membership)

Full setup walkthrough: `docs/FRESH-INSTALL.md`.

**No username is hardcoded** anywhere in the bootstrap path — it uses `whoami`/`$HOME` throughout.

## GNU Stow

[GNU Stow](https://www.gnu.org/software/stow/) manages symlinks from this repo into `~/` (home directory). `.stowrc` is pre-configured so all commands work from the repo root without extra flags.

```bash
stow wezterm       # symlink a package
stow -D wezterm    # remove symlinks
stow -n wezterm    # dry run
```

**Package directory structure**: each top-level folder is a stow package. Files must be nested to mirror `~/`. For example:
- `wezterm/.config/wezterm/wezterm.lua` → `~/.config/wezterm/wezterm.lua`

Stow packages: `wezterm`, `nvim`, `fish`, `fastfetch`, `hypr`, `noctalia`, `mise`.

**In WSL, `bootstrap.fish` stows only `fish nvim fastfetch mise`** (see `STOW_PACKAGES`). `wezterm` runs on the Windows host and `hypr`/`noctalia` are Wayland/GUI-only, so they are excluded there.

> **⚠ Machine-specific paths**: `.stowrc` contains hardcoded `--target` and `--dir` paths, so manual `stow` invocations only work for the user it was written for. Update both when cloning on a new machine. `bootstrap.fish` bypasses `.stowrc` by passing `--target`/`--dir` explicitly.

## WSL gotchas

Two environment quirks that the bootstrap encodes and `verify` asserts:
- **`/mnt/c` must be mounted with `metadata`** (`[automount] options="metadata,umask=22,fmask=11"` in `/etc/wsl.conf`), or every file is mode `777` and the Salesforce CLI rejects `~/.sfdx/key.json`.
- **WSL has no D-Bus secret service**, so `config.fish` exports `SF_USE_GENERIC_UNIX_KEYCHAIN=true`; without it `sf` fails with `secret-tool: The name is not activatable` and no org can be authenticated.

## Lua Formatting (Neovim config)

All Lua files are formatted with **stylua** using `nvim/.config/nvim/.stylua.toml`:
- 2-space indentation, 160 column width
- Single quotes preferred (`AutoPreferSingle`)
- No call parentheses (`call_parentheses = "None"`)
- Collapsed simple statements (`collapse_simple_statement = "Always"`)

```bash
stylua --check nvim/   # lint
stylua nvim/           # format in-place
```

## Neovim Architecture

Built on **kickstart.nvim**. The config is split across:
- `nvim/.config/nvim/init.lua` — single file with all core options, keymaps, and plugin specs
- `nvim/.config/nvim/lua/kickstart/plugins/` — optional kickstart extras; each must be manually uncommented via `require 'kickstart.plugins.<name>'` near the bottom of `init.lua`. Currently enabled: `gitsigns`, `indent_line`. Available but commented out: `autopairs`, `debug`, `lint`, `neo-tree`
- `nvim/.config/nvim/lua/custom/plugins/` — user plugins; every `.lua` file here is **auto-imported** by lazy.nvim (via `{ import = 'custom.plugins' }`) and must return a `LazySpec` table

> **`lazy-lock.json` is gitignored** (kickstart default). To pin plugin versions in your fork, remove `lazy-lock.json` from `nvim/.config/nvim/.gitignore` and commit it.

**JavaScript/TypeScript LSP**: `ts_ls` is enabled in the `servers` table and handles `gd`/hover/references for `.js` and `.ts` files. LWC projects need a `jsconfig.json` at the project root mapping virtual imports (`@salesforce/apex/*`, `@salesforce/schema/*`, `lwc`, etc.) to `[]` to suppress false "module not found" errors — see `tramontina-sf/jsconfig.json` for the template.

**Requires Neovim 0.11+** — `salesforce.lua` uses the `vim.lsp.config()` / `vim.lsp.enable()` API introduced in 0.11.

**Plugin manager**: lazy.nvim  
**LSP**: nvim-lspconfig + Mason (`lua_ls` enabled; `lua_ls` formatting disabled — stylua handles it)  
**Formatter**: conform.nvim — `<leader>f` to format manually; auto-format on save is opt-in per filetype via the `enabled_filetypes` table in `init.lua`  
**Completion**: blink.cmp + LuaSnip + blink-copilot (Copilot inline suggestions via ghost text)  
**Fuzzy finder**: Telescope (`enabled` flag in init.lua can swap it for snacks/fzf-lua)  
**File manager**: yazi.nvim (`<leader>-` to open, `<c-up>` to toggle)  
**Colorizer**: nvim-colorizer.lua — inline virtual text (`■`) showing color previews for all filetypes  
**Treesitter context**: nvim-treesitter-context — sticky top context bar, max 3 lines; `[c` jumps up to context  
**Indentation**: indent-blankline.nvim (static dim guides, `optional = true` — extends kickstart's `indent_line` extra if enabled) + mini.indentscope (animated current-scope highlight, always active)

### Adding an LSP server

Add the Mason tool name to the `servers` table in `init.lua`. For servers with Mason name mismatches (e.g., `apex_ls`), configure manually in a custom plugin using `nvim-lspconfig` with `optional = true` and `init` (not `config`) to avoid overriding kickstart's lspconfig setup.

### Adding a formatter

Add the formatter under `conform.nvim`'s `formatters_by_ft` table in `init.lua`. To enable auto-format on save for a filetype, add it to the `enabled_filetypes` table in the `format_on_save` function. Currently all entries in `enabled_filetypes` are commented out — auto-format on save is disabled for all filetypes by default.

## Key Neovim Conventions

- Leader key: `<space>`
- New plugins go in `lua/custom/plugins/<name>.lua` and must return a `LazySpec` table — annotate the file with `---@module 'lazy'` / `---@type LazySpec` for LSP type checking
- `lua/custom/plugins/init.lua` is a placeholder returning `{}`; do not put plugins there — every other `.lua` file in that directory is auto-imported by lazy.nvim
- Use `opts = {}` shorthand instead of `config = function() require('X').setup({}) end` when no extra logic is needed
- Use `config` (not `opts`) when post-setup work is required: e.g., `bufferline.lua` (palette logic must run after tokyonight loads), `treesitter-context.lua` (custom highlight autocommands after setup)
- Annotate `opts` tables with `---@module 'X'` and `---@type X.Config` for LSP type checking
- Background is transparent (Normal bg = none, set via autocommand on ColorScheme in `init.lua`)
- Augroup names: `kickstart-*` prefix for built-ins; use a distinct prefix for custom groups
- When extending a plugin already defined in `init.lua` (e.g., blink.cmp, nvim-treesitter), use `optional = true` in the custom plugin spec and merge with `opts` functions

### Key keymap reference

**Buffers** (bufferline.nvim):
- `<S-l>` / `<S-h>` — cycle next/prev buffer
- `<M-S-l>` / `<M-S-h>` — move buffer right/left
- `<leader>bx` / `<leader>bX` — close current / close others
- `<leader>bp` — pin/unpin buffer
- `<leader>b1`–`<leader>b5` — jump to buffer by position

**Git** (lazygit.nvim + diffview.nvim — requires `lazygit` binary in PATH):
- `<leader>gg` — open LazyGit
- `<leader>gf` / `<leader>gl` / `<leader>gL` — LazyGit (current file / repo log / file log)
- `<leader>gd` / `<leader>gD` — diff working tree / vs last commit
- `<leader>gh` / `<leader>gH` — file history / repo history
- `<leader>gx` — close diff view

**File manager** (yazi.nvim):
- `<leader>-` — open yazi at current file
- `<leader>cw` — open yazi at nvim's cwd
- `<c-up>` — resume last yazi session

## Custom Treesitter Queries

`nvim/.config/nvim/queries/apex/` contains custom treesitter queries for the Apex language (currently `folds.scm`). Place additional `.scm` files there to extend treesitter behavior for Apex.

## Custom Lua Modules

`nvim/.config/nvim/lua/custom/` holds two kinds of Lua code:
- `plugins/` — lazy.nvim plugin specs (auto-imported, must return a `LazySpec` table)
- standalone modules — plain Lua modules required explicitly; e.g., `apex_foldtext.lua` provides syntax-highlighted fold text for Apex files (referenced via `vim.wo.foldtext = "v:lua.require('custom.apex_foldtext').foldtext()"` in `salesforce.lua`)

## Database UI

**`dadbod.lua`** — SQL database explorer via vim-dadbod + vim-dadbod-ui:
- `<leader>db` / `:DBUI` — toggle the database sidebar
- SQLite connection string format: `sqlite:path/to/file.db3`
- Completions available for `sql`, `mysql`, `plsql` filetypes

## Matugen Dynamic Theming

`nvim/.config/nvim/lua/matugen.lua` + `lua/plugins/base16.lua` — optional dynamic color scheme driven by [matugen](https://github.com/InioX/matugen).
- Sends `SIGUSR1` to the Neovim process to hot-reload colors without restarting
- `lua/plugins/` is **not** auto-imported by lazy.nvim (unlike `lua/custom/plugins/`) — files there must be explicitly required

## Salesforce Plugins

**`salesforce.lua`** — LSP + formatting:
- Filetype detection for `.cls`, `.trigger`, `.apex` → `apex` filetype
- `apex_ls` LSP via Mason (requires Java; Mason name is `apex-language-server`)
- prettier formatting for LWC/Aura files (JS, HTML, CSS, XML) via conform.nvim

**`salesforce_sf.lua`** — `sf` CLI integration (keymaps active only inside an sfdx-project):
- Requires `sf` CLI in PATH
- All keymaps under `<leader>F` (Force/Salesforce group)
- `<leader>Fa` — Execute anonymous Apex (whole file or visual selection)
- `<leader>Fo` — Select & set default org
- `<leader>Fd`/`<leader>FD` — Deploy current file / entire project
- `<leader>Fr`/`<leader>FR` — Retrieve current file / entire project
- `<leader>F=` — Diff current file against org (retrieve to tmp + vimdiff)
- `<leader>Fp`/`<leader>FP` — Preview deploy / retrieve (dry run)
- Output opens in a scratch split buffer; press `q` to close

## Copilot Inline Completions

`lua/custom/plugins/copilot.lua` wires `zbirenbaum/copilot.lua` + `blink-copilot` into blink.cmp.  
**Node version constraint**: requires Node 24 specifically (not 26). Managed via `mise use --global node@24`.

## Shell / Prompt

- **Fish** (`fish/.config/fish/config.fish`): sources CachyOS base config, activates `mise`, then initializes oh-my-posh with the `catppuccin_mocha` theme fetched from the upstream URL
  - `conf.d/` — drop additional `.fish` files here for auto-sourced configs (e.g., tool activations, path additions)
  - `functions/` — custom fish functions; each `<name>.fish` file auto-defines the `<name>` command
  - `completions/` — custom tab-completion scripts

## Color Theme

**Catppuccin Mocha** is used consistently across FastFetch, oh-my-posh, and bufferline. **Tokyo Night** (night variant) is used for WezTerm and Neovim's colorscheme; bufferline derives its palette programmatically from `tokyonight.colors`.

## WezTerm

Tracked at `wezterm/.config/wezterm/wezterm.lua`. Key settings:
- **Color scheme**: `"Tokyo Night"` (matches Neovim's tokyonight-night)
- **Font size**: 14, **line height**: 1.2
- **Tab bar**: plain style (`use_fancy_tab_bar = false`), positioned at bottom, hidden when only one tab open
- **Window**: no decorations except resize handle (`RESIZE`), zero padding, `window_close_confirmation = "NeverPrompt"`
- **Performance**: `max_fps = 120`, `prefer_egl = true`, static cursor (`cursor_blink_rate = 0`)

## FastFetch

Config at `fastfetch/config.jsonc`. The logo source path is hardcoded to a Windows path (`C:/Users/kanoah/.config/fastfetch/ascii.txt`) — update for Linux use.
