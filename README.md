# dotfiles

Personal dotfiles for Arch Linux (CachyOS desktop + Arch on WSL2), managed with GNU Stow.

Configs: Neovim (kickstart-based), Fish, WezTerm, Herdr, FastFetch, Hyprland, Noctalia, mise.

Machines:

| Machine | Repo path | Stowed packages |
|---|---|---|
| CachyOS desktop (Hyprland) | `/mnt/FILES/Projects/dotfiles` | `fastfetch fish wezterm nvim noctalia hypr herdr` |
| Windows + Arch WSL2 | `~/Code/dotfiles` (inside WSL) | `fish nvim fastfetch mise herdr` (WezTerm config is copied to Windows, see below) |

---

## Quick start on a fresh WSL Arch install

```sh
git clone https://github.com/rafaelsm993/dotfiles.git ~/Code/dotfiles
cd ~/Code/dotfiles
./bootstrap.sh --dry-run     # preview - changes nothing
./bootstrap.sh               # do it
```

Full walkthrough, including the Windows-side steps: **[docs/FRESH-INSTALL.md](docs/FRESH-INSTALL.md)**

Then do **[WezTerm + Herdr on Windows/WSL](#wezterm--herdr-on-windowswsl)** below to get
the terminal and tmux-style setup.

---

## Bootstrap

`bootstrap.sh` is a tiny POSIX shim that installs fish (a fresh Arch box doesn't
have it), then hands off to `bootstrap.fish`, which does the real work in nine
idempotent phases.

| Phase | Action |
|---|---|
| `packages` | `pacman -S --needed` from `scripts/packages.txt` |
| `wslconf` | installs `/etc/wsl.conf` (automount `metadata` — required by the Salesforce CLI) |
| `stow` | symlinks `fish`, `nvim`, `fastfetch`, `mise` |
| `mise` | installs the java + node runtimes |
| `npm` | installs globals from `scripts/npm-globals.txt` |
| `omp` | installs oh-my-posh into `~/.local/bin` |
| `shell` | sets fish as the login shell |
| `git` | applies global git config |
| `verify` | asserts the resulting environment is sane |

### Options

```sh
./bootstrap.fish --dry-run          # print actions, change nothing
./bootstrap.fish --only stow        # run a single phase (repeatable)
./bootstrap.fish --skip packages    # skip a phase (repeatable)
./bootstrap.fish --force            # redo steps normally skipped when present
./bootstrap.fish --help
```

Every phase is **idempotent** — running it twice is safe and mostly a no-op.

### Safety behaviour

- **`--dry-run` first.** Nothing is executed; each action is printed instead.
- **`/etc/wsl.conf` is never blind-overwritten.** If it exists and differs, the
  script prints a diff and leaves it alone unless you pass `--force`.
- **Stow conflicts are backed up, not clobbered.** A pre-existing real
  `~/.config/<pkg>` is moved to `<pkg>.pre-stow.<timestamp>` before linking.
- **No hardcoded username.** `/etc/wsl.conf` is rendered from
  `scripts/wsl.conf.template` using `whoami` at run time.

### What it does NOT do

- Create the WSL distro or your user account
- Run `wsl --shutdown` for you after `/etc/wsl.conf` changes
- Authenticate Salesforce orgs (`sf org login web`)
- Set your git identity (`user.email`)
- Generate SSH keys or log into GitHub
- Install Windows-side apps (WezTerm, Neovim for Windows, Nerd Fonts)
- Install Herdr (see below)

---

## Data files

Edit these rather than the script:

| File | Purpose |
|---|---|
| `scripts/packages.txt` | pacman packages (`#` comments allowed) |
| `scripts/npm-globals.txt` | global npm packages |
| `scripts/wsl.conf.template` | `/etc/wsl.conf`, `__USER__` is substituted |
| `scripts/lib.fish` | shared logging / dry-run / package helpers |

Check for drift between the declared list and what's actually installed:

```sh
diff (fish -c 'source scripts/lib.fish; read_list scripts/packages.txt' | sort | psub) (pacman -Qqe | sort | psub)
```

---

## GNU Stow

[GNU Stow](https://www.gnu.org/software/stow/) symlinks each top-level folder
into `~/`. Files mirror the home layout, e.g.
`wezterm/.config/wezterm/wezterm.lua` → `~/.config/wezterm/wezterm.lua`.

`.stowrc` is portable (no usernames or absolute paths):

```
--target=~
--no-folding
```

So always run stow **from the repo root**:

```sh
cd /mnt/FILES/Projects/dotfiles     # or ~/Code/dotfiles in WSL
stow -n -v herdr     # dry run
stow herdr           # link
stow -D herdr        # unlink
```

Why `--no-folding`: without it stow links a whole folder (`~/.config/herdr ->
repo`), so the app's runtime files (herdr's logs, sockets and session state, fish's
`fish_variables`) get written into the repo. With it, stow links files one by one
and the folder stays a real directory. Before stowing a package for the first
time, create the folder yourself (`mkdir -p ~/.config/herdr`).

CachyOS desktop:

```sh
cd /mnt/FILES/Projects/dotfiles
stow -n -v fastfetch fish wezterm nvim noctalia hypr herdr
stow -v fastfetch fish wezterm nvim noctalia hypr herdr
```

Stowed by bootstrap in WSL: `fish`, `nvim`, `fastfetch`, `mise`. Stow `herdr`
by hand (see below).

**Not** stowed in WSL — `wezterm` (runs on the Windows host, its config is copied),
`hypr` and `noctalia` (Wayland/GUI, no compositor in WSL).

---

## Herdr (terminal multiplexer)

[Herdr](https://herdr.dev) is a tmux-style multiplexer built for coding agents.
Config: `herdr/.config/herdr/config.toml` → `~/.config/herdr/config.toml`.

WezTerm no longer defines a leader key. Herdr owns `CTRL+Space` as its prefix,
so the old WezTerm `<leader>` keys now work inside Herdr instead.

| Bind | Action |
|---|---|
| `CTRL+Space` then `?` | Show all active bindings |
| `CTRL+Space` then `\` or `v` | Split side by side |
| `CTRL+Space` then `-` | Split stacked |
| `CTRL+Space` then `h/j/k/l` | Focus pane |
| `CTRL+Space` then `f` or `z` | Zoom pane |
| `CTRL+Space` then `x` | Close pane |
| `CTRL+Space` then `r` | Resize mode (`h/j/k/l`, `Esc` to exit) |
| `CTRL+Space` then `[` | Copy mode (`/` searches, `v` selects, `y` copies) |
| `CTRL+Space` then `t` or `c` | New tab |
| `CTRL+Space` then `n` / `p` | Next / previous tab |
| `CTRL+Space` then `1`-`9` | Jump to tab |
| `CTRL+Space` then `,` | Rename tab |
| `CTRL+Space` then `w` | Close tab |
| `CTRL+Space` then `a` | Workspace picker |
| `CTRL+Space` then `Shift+1`-`9` | Jump to workspace |
| `CTRL+Space` then `g` | Goto picker (all agents/terminals) |
| `CTRL+Space` then `Alt+1`-`9` | Jump to agent N |
| `CTRL+Space` then `o` | Jump to the agent that just notified |
| `CTRL+Space` then `Alt+g` | lazygit popup (review agent diffs) |
| `CTRL+Space` then `Alt+y` | yazi popup |
| `CTRL+Space` then `Alt+s` | Scratch fish shell popup |
| `CTRL+Space` then `q` | Detach (everything keeps running; `herdr` reattaches) |

WezTerm itself keeps only direct chords: `CTRL+SHIFT+C/V` copy/paste,
`CTRL+SHIFT+L` debug overlay, `CTRL+SHIFT+O` transparency toggle.

Useful commands:

```sh
herdr config check             # validate config.toml -> "config: ok"
herdr server reload-config     # apply config edits to a running server
herdr server stop              # stop the server and every pane in it
herdr status                   # client/server versions
```

### Install (any Arch box, desktop or WSL)

```sh
curl -fsSL https://herdr.dev/install.sh | sh     # installs ~/.local/bin/herdr (no root)
herdr --version

cd <repo root>
mkdir -p ~/.config/herdr
stow -n -v herdr && stow -v herdr
herdr config check                               # expect: config: ok
```

The popups need `lazygit` and `yazi` (`sudo pacman -S --needed lazygit yazi`;
both are already in `scripts/packages.txt`).

### Coding-agent integration

Each integration lets Herdr track an agent's state and session, so after
`herdr server stop` or a reboot every agent pane reopens the same conversation.
Install one only for agents that are installed (its config dir must exist):

```sh
herdr integration install claude      # ~/.claude/hooks + SessionStart hook in settings.json
herdr integration install copilot     # ~/.copilot/hooks + SessionStart hook in settings.json
herdr integration install codex       # only if codex is installed
# Hermes: target the profile you actually run, not the default ~/.hermes
env HERMES_HOME=$HOME/.hermes/profiles/<profile> herdr integration install hermes
herdr integration status              # each one should say: current
```

Undo with `herdr integration uninstall <agent>`. These hooks live in each agent's
own config dir, not in this repo, because the agents edit those files themselves.

The **Herdr agent skill** teaches an agent running inside a Herdr pane to split
panes, run commands in other panes, read their output and coordinate other agents:

```sh
npx -y skills add herdrdev/herdr --skill herdr -g -a claude-code github-copilot -y
ls ~/.claude/skills/herdr/SKILL.md
```

(For a Hermes profile, copy `~/.agents/skills/herdr/SKILL.md` to
`~/.hermes/profiles/<profile>/skills/autonomous-ai-agents/herdr/SKILL.md`;
`-a hermes-agent` only targets the default profile.)

Test it: inside Herdr start `claude` and ask *"run `echo hi` in a new Herdr pane to
the right and tell me the output"*. A pane should appear and Claude should report `hi`.

---

## WezTerm + Herdr on Windows/WSL

WezTerm runs on **Windows**. Herdr, fish, nvim and the agents run **inside Arch WSL**.
`wezterm.lua` detects Windows and opens straight into the `archlinux` distro.

**1. Windows (PowerShell):** install WezTerm and a Nerd Font.

```powershell
winget install --id wez.wezterm
winget install --id DEVCOM.JetBrainsMonoNerdFont
wsl -l -v          # note the distro NAME; wezterm.lua assumes "archlinux"
```

If the distro isn't called `archlinux`, change the `default_prog` line in
`wezterm/.config/wezterm/wezterm.lua` to use the right name.

**2. Inside WSL:** copy the WezTerm config to the Windows home. WezTerm on Windows
reads `%USERPROFILE%\.config\wezterm\wezterm.lua`. It's a copy, not a symlink, so
re-run this after pulling changes:

```sh
cd ~/Code/dotfiles
set WINHOME (wslpath (cmd.exe /c 'echo %USERPROFILE%' 2>/dev/null | tr -d '\r'))
mkdir -p $WINHOME/.config/wezterm
cp -r wezterm/.config/wezterm/. $WINHOME/.config/wezterm/
ls $WINHOME/.config/wezterm
```

**3. Inside WSL:** install and stow Herdr and its agent integrations. Follow
[Install](#install-any-arch-box-desktop-or-wsl) and
[Coding-agent integration](#coding-agent-integration) above. `npx` comes from the
mise-managed node set up by bootstrap.

**4. Check:** open WezTerm. You should land in fish inside Arch, then:

```sh
herdr                  # starts the session
# CTRL+Space then ?    -> the help panel lists the binds above
# CTRL+Space then \    -> a pane splits to the right
```

If `CTRL+Space` does nothing, WezTerm is still claiming it: check that the copied
`wezterm.lua` has no `config.leader` line. If the `Alt+…` popups don't fire, the
terminal isn't passing Alt through. The help panel still lists them; rebind them in
`config.toml`.

---

## WSL notes

Two non-obvious things that cost real debugging time:

1. **`/mnt/c` needs the `metadata` mount option**, set via
   `[automount] options="metadata,umask=22,fmask=11"` in `/etc/wsl.conf`.
   Without it every file under `/mnt/c` is mode `777`, and the Salesforce CLI
   refuses to read `~/.sfdx/key.json` with *"Invalid file permissions for secret
   file"*.

2. **WSL has no D-Bus secret service**, so `libsecret`/`secret-tool` fails with
   *"The name is not activatable"* and the Salesforce CLI cannot decrypt any auth
   file. `config.fish` exports `SF_USE_GENERIC_UNIX_KEYCHAIN=true` to force the
   CLI's file-based keychain. The `verify` phase asserts this is present.
   **Do not** set it on the CachyOS desktop, which has a real keychain: there it
   causes `AuthDecryptError` on deploy.

Also note WSL and Windows have **separate home directories**. Auth done in
Windows (`C:\Users\<you>\.sfdx`) is invisible to WSL. Run `sf org login web`
from inside WSL.

---

## Hyprland keybinds (hypr/.config/hypr/hyprland.lua) — desktop only

Config uses the Hyprland Lua API (`hl.*`), scrolling (Niri-style) layout.

### Scroll wheel (mainMod = Super)

| Bind | Action |
|---|---|
| `Super + Scroll Down` | Focus window to the right |
| `Super + Scroll Up` | Focus window to the left |
| `Super + LMB drag` | Move/drag window |
| `Super + RMB drag` | Resize window |

### Screenshots (Flameshot)

Requires `~/Pictures/Screenshots` to exist (`mkdir -p ~/Pictures/Screenshots`).

| Bind | Action |
|---|---|
| `Print` | Flameshot GUI capture, saved to `~/Pictures/Screenshots` + copied to clipboard |
| `Ctrl + Print` | Wait 3s, then Flameshot GUI capture, saved + clipboard |
| `Shift + Print` | Full (all-monitor) screenshot, saved + clipboard |
| `Ctrl + Shift + Print` | Full (all-monitor) screenshot, clipboard only (not saved) |

These are native Hyprland Lua binds (`{ locked = true }`), not KDE/GNOME
shortcuts.

---

## Neovim

Built on kickstart.nvim. See `.github/copilot-instructions.md` for the full
architecture notes (plugin layout, LSP, formatting, Salesforce integration).

Requires Neovim 0.11+ (`salesforce.lua` uses `vim.lsp.config()` / `vim.lsp.enable()`).

## Lua formatting

```sh
stylua --check nvim/   # lint
stylua nvim/           # format
```
