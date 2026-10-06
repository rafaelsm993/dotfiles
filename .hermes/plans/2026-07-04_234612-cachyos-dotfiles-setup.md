# CachyOS Dotfiles Fresh Install Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Safely apply the dotfiles from `/home/user/Projects/dotflies` onto the fresh CachyOS install, preserving any existing fresh-install configs and fixing stale paths before stowing.

**Architecture:** Treat the dotfiles repo as a GNU Stow package repository. First audit and back up the fresh `$HOME` configs, then fix repo metadata that still points to the old machine/user path, install required packages, stow one package at a time, and validate each application separately before logging into the full Hyprland session.

**Tech Stack:** CachyOS / Arch Linux, GNU Stow, Git, Fish, WezTerm, Neovim, Hyprland Lua config, Noctalia Shell, Fastfetch, mise, oh-my-posh.

---

## Current Context / Assumptions

- The user said the dotfiles are in `/home/user/Projects/dotfiles`, but the actual repository found on disk is `/home/user/Projects/dotflies`.
- Git remote is `https://github.com/rafaelsm993/dotflies.git`.
- The repository has these Stow packages:
  - `/home/user/Projects/dotflies/hypr`
  - `/home/user/Projects/dotflies/noctalia`
  - `/home/user/Projects/dotflies/wezterm`
  - `/home/user/Projects/dotflies/fish`
  - `/home/user/Projects/dotflies/nvim`
  - `/home/user/Projects/dotflies/fastfetch`
- Existing `.stowrc` is stale and currently contains:
  - `--target=/home/kanoah`
  - `--dir=/home/kanoah/Code/dotfiles`
- Existing `hypr/.config/hypr/hyprland.conf` is stale and sources:
  - `/home/kanoah/.config/hypr/noctalia/noctalia-colors.conf`
- Main Hyprland config is Lua-based:
  - `/home/user/Projects/dotflies/hypr/.config/hypr/hyprland.lua`
- Important Hyprland assumptions currently encoded:
  - Monitor: `DP-3`, `3440x1440@180`, scale `1`
  - Browser: `vivaldi`
  - Terminal: `wezterm`
  - File manager: `dolphin`
  - Layout: `scrolling`
  - Keyboard layout likely `br` later in the file, based on the local Hyprland setup reference.
- Fish config expects:
  - CachyOS fish config at `/usr/share/cachyos-fish-config/cachyos-config.fish`
  - `mise`
  - `oh-my-posh`
- This plan intentionally does not mutate the system yet.

---

## Proposed Approach

1. Confirm the real repo path and current user/home.
2. Create a backup of every config path that Stow would manage.
3. Fix stale absolute paths in the repo before using Stow.
4. Install required system packages and AUR packages.
5. Run `stow --simulate` first for every package.
6. Stow packages one by one, validating after each package.
7. Only after terminal/shell/editor configs validate, validate Hyprland and Noctalia.
8. Keep the old fresh-install configs in a timestamped backup until the full desktop session is confirmed working.

---

## Files Likely To Change

Repository files:

- Modify: `/home/user/Projects/dotflies/.stowrc`
- Modify: `/home/user/Projects/dotflies/hypr/.config/hypr/hyprland.conf`
- Possibly modify: `/home/user/Projects/dotflies/hypr/.config/hypr/hyprland.lua`
  - only if monitor name/resolution, keyboard layout, browser, or installed apps differ from the fresh install
- Possibly create: `/home/user/Projects/dotflies/README.md`
  - optional, to document the bootstrap process after the install succeeds

User home paths affected by Stow:

- `~/.config/hypr/hyprland.lua`
- `~/.config/hypr/hyprland.conf`
- `~/.config/hypr/hyprtoolkit.conf`
- `~/.config/noctalia/settings.json`
- `~/.config/noctalia/plugins.json`
- `~/.config/wezterm/wezterm.lua`
- `~/.config/wezterm/colors/Noctalia.toml`
- `~/.config/fish/config.fish`
- `~/.config/fish/conf.d/fish_frozen_key_bindings.fish`
- `~/.config/fish/completions/copilot.fish`
- `~/.config/fish/functions/lutris.fish`
- `~/.config/fish/fish_variables`
- `~/.config/nvim/**`
- `~/.config/fastfetch/config.jsonc`
- `~/.config/fastfetch/ascii.txt`

---

## Task 1: Confirm Repository Path and Baseline State

**Objective:** Avoid applying the wrong directory or stale path assumptions.

**Files:**
- Read-only: `/home/user/Projects/dotflies/.stowrc`
- Read-only: `/home/user/Projects/dotflies/.git/config`

**Step 1: Confirm the real repo path**

Run:

```bash
pwd
printf 'HOME=%s\nUSER=%s\n' "$HOME" "$USER"
test -d /home/user/Projects/dotflies && echo 'repo exists: /home/user/Projects/dotflies'
test -d /home/user/Projects/dotfiles && echo 'also exists: /home/user/Projects/dotfiles' || echo 'not found: /home/user/Projects/dotfiles'
```

Expected:

```text
/home/user/Projects/dotflies
HOME=/home/user
USER=user
repo exists: /home/user/Projects/dotflies
not found: /home/user/Projects/dotfiles
```

**Step 2: Check Git status**

Run:

```bash
git -C /home/user/Projects/dotflies status --short --branch
git -C /home/user/Projects/dotflies remote -v
```

Expected:

```text
## main...origin/main
origin  https://github.com/rafaelsm993/dotflies.git (fetch)
origin  https://github.com/rafaelsm993/dotflies.git (push)
```

If there are uncommitted changes, stop and inspect them before touching repo files.

**Step 3: List Stow packages**

Run:

```bash
cd /home/user/Projects/dotflies
printf '%s\n' hypr noctalia wezterm fish nvim fastfetch | while read -r package; do
  test -d "$package" && echo "OK: $package" || echo "MISSING: $package"
done
```

Expected:

```text
OK: hypr
OK: noctalia
OK: wezterm
OK: fish
OK: nvim
OK: fastfetch
```

**Step 4: Commit**

No commit. This task is inspection only.

---

## Task 2: Create a Backup of Fresh-Install Configs

**Objective:** Preserve any existing CachyOS-generated configs before Stow replaces paths with symlinks.

**Files:**
- Create outside repo: `~/dotfiles-backup-YYYYMMDD-HHMMSS/`

**Step 1: Create backup directory**

Run:

```bash
backup_dir="$HOME/dotfiles-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$backup_dir/.config"
printf 'BACKUP_DIR=%s\n' "$backup_dir"
```

Expected: prints a backup path such as:

```text
BACKUP_DIR=/home/user/dotfiles-backup-20260704-235000
```

**Step 2: Copy only config paths that exist**

Run:

```bash
backup_dir="$(find "$HOME" -maxdepth 1 -type d -name 'dotfiles-backup-*' | sort | tail -n 1)"
for path in \
  "$HOME/.config/hypr" \
  "$HOME/.config/noctalia" \
  "$HOME/.config/wezterm" \
  "$HOME/.config/fish" \
  "$HOME/.config/nvim" \
  "$HOME/.config/fastfetch"
do
  if test -e "$path" || test -L "$path"; then
    cp -a "$path" "$backup_dir/.config/"
    echo "backed up: $path"
  else
    echo "not present: $path"
  fi
done
```

Expected: each path prints either `backed up:` or `not present:`.

**Step 3: Verify backup contents**

Run:

```bash
backup_dir="$(find "$HOME" -maxdepth 1 -type d -name 'dotfiles-backup-*' | sort | tail -n 1)"
find "$backup_dir" -maxdepth 3 -type f -o -type l | sort
```

Expected: lists copied config files, or only the empty backup directory if none existed.

**Step 4: Commit**

No commit. Backup is outside the repo.

---

## Task 3: Fix `.stowrc` for the New Home Directory

**Objective:** Make GNU Stow target `/home/user` and use the actual repo path `/home/user/Projects/dotflies`.

**Files:**
- Modify: `/home/user/Projects/dotflies/.stowrc`

**Step 1: Replace stale `.stowrc` content**

Set `/home/user/Projects/dotflies/.stowrc` to exactly:

```text
--target=/home/user
--dir=/home/user/Projects/dotflies
```

Command to apply when executing:

```bash
cat > /home/user/Projects/dotflies/.stowrc <<'EOF'
--target=/home/user
--dir=/home/user/Projects/dotflies
EOF
```

**Step 2: Verify `.stowrc`**

Run:

```bash
cat /home/user/Projects/dotflies/.stowrc
```

Expected:

```text
--target=/home/user
--dir=/home/user/Projects/dotflies
```

**Step 3: Verify Stow sees the expected packages**

Run:

```bash
cd /home/user/Projects/dotflies
stow --simulate --verbose fastfetch
```

Expected:

- If there are no conflicts, output shows planned links or no errors.
- If `stow` is missing, install it in Task 5 before continuing.
- If conflicts are reported, do not use `--adopt`; resolve by backing up/removing the conflicting fresh-install files first.

**Step 4: Commit**

Only commit later after the whole repo path cleanup is complete. Do not commit after this task yet unless requested.

---

## Task 4: Fix Stale Hyprland Absolute Path

**Objective:** Remove the old `/home/kanoah` source path so Hyprland can load on this fresh install.

**Files:**
- Modify: `/home/user/Projects/dotflies/hypr/.config/hypr/hyprland.conf`

**Step 1: Replace the stale source path**

Current file contains:

```conf
source = /home/kanoah/.config/hypr/noctalia/noctalia-colors.conf
```

Replace it with a path that works for the current user:

```conf
source = /home/user/.config/hypr/noctalia/noctalia-colors.conf
```

Command to apply when executing:

```bash
python - <<'PY'
from pathlib import Path
path = Path('/home/user/Projects/dotflies/hypr/.config/hypr/hyprland.conf')
text = path.read_text()
text = text.replace('/home/kanoah/.config/hypr/noctalia/noctalia-colors.conf', '/home/user/.config/hypr/noctalia/noctalia-colors.conf')
path.write_text(text)
PY
```

Alternative, if Hyprland supports environment expansion reliably on this setup, prefer this portable version:

```conf
source = ~/.config/hypr/noctalia/noctalia-colors.conf
```

Use the explicit `/home/user` version if uncertain.

**Step 2: Search for remaining stale paths**

Run:

```bash
grep -RIn '/home/kanoah\|/home/user/Projects/dotfiles\|/home/kanoah/Code/dotfiles' /home/user/Projects/dotflies --exclude-dir=.git
```

Expected:

- No output.

If output remains, inspect each match and decide whether it must be migrated to `/home/user` or `/home/user/Projects/dotflies`.

**Step 3: Commit**

After Task 3 and Task 4 are complete and verified:

```bash
cd /home/user/Projects/dotflies
git diff -- .stowrc hypr/.config/hypr/hyprland.conf
git add .stowrc hypr/.config/hypr/hyprland.conf
git commit -m "chore: update dotfiles paths for fresh CachyOS install"
```

Expected:

- Diff only contains path changes.
- Commit succeeds.

If the user does not want a commit, skip this step.

---

## Task 5: Install Required Packages

**Objective:** Ensure every stowed config has its backing application installed before validation.

**Files:**
- No repo changes.

**Step 1: Update package database**

Run:

```bash
sudo pacman -Syu
```

Expected:

- System updates successfully.
- Reboot first if kernel, driver, mesa, systemd, or Hyprland core packages are upgraded.

**Step 2: Install core repo packages**

Run:

```bash
sudo pacman -S --needed \
  git \
  stow \
  fish \
  wezterm \
  neovim \
  fastfetch \
  hyprland \
  hyprpaper \
  xdg-desktop-portal-hyprland \
  qt6-wayland \
  xdg-utils \
  dolphin \
  vivaldi \
  ripgrep \
  fd \
  fzf \
  unzip \
  wl-clipboard \
  cliphist \
  grim \
  slurp \
  brightnessctl \
  playerctl \
  pipewire \
  pipewire-pulse \
  wireplumber \
  networkmanager
```

Expected:

- Packages install or are already installed.

If `vivaldi` is not available from enabled CachyOS repositories, install it from CachyOS package tooling or AUR in the next step.

**Step 3: Ensure an AUR helper exists**

Run:

```bash
command -v paru || command -v yay || echo 'No AUR helper found'
```

Expected:

- Prints `/usr/bin/paru`, `/usr/bin/yay`, or `No AUR helper found`.

If no AUR helper exists on CachyOS, install one using CachyOS defaults before continuing.

**Step 4: Install AUR/userland dependencies**

Use whichever helper exists.

With `paru`:

```bash
paru -S --needed mise-bin oh-my-posh-bin noctalia-shell
```

With `yay`:

```bash
yay -S --needed mise-bin oh-my-posh-bin noctalia-shell
```

Expected:

- `mise`, `oh-my-posh`, and `noctalia` commands become available.

If `noctalia-shell` is not the correct package name on this install, search and install the package that provides the `noctalia` command:

```bash
paru -Ss noctalia
# or
yay -Ss noctalia
```

**Step 5: Enable required services**

Run:

```bash
sudo systemctl enable --now NetworkManager.service
systemctl --user enable --now pipewire pipewire-pulse wireplumber
```

Expected:

- NetworkManager starts.
- User audio services start or report already running.

**Step 6: Validate commands exist**

Run:

```bash
for cmd in git stow fish wezterm nvim fastfetch hyprland hyprctl dolphin vivaldi mise oh-my-posh noctalia; do
  if command -v "$cmd" >/dev/null 2>&1; then
    printf 'OK: %s -> %s\n' "$cmd" "$(command -v "$cmd")"
  else
    printf 'MISSING: %s\n' "$cmd"
  fi
done
```

Expected:

- All commands print `OK`.
- If any command prints `MISSING`, install/fix that dependency before stowing its config.

**Step 7: Commit**

No commit. Package installation is system state, not repo state.

---

## Task 6: Dry-Run Every Stow Package

**Objective:** Detect conflicts before changing `$HOME` symlinks.

**Files:**
- Read-only: `/home/user/Projects/dotflies/*`
- Read-only: `~/.config/*`

**Step 1: Run Stow simulation for each package**

Run:

```bash
cd /home/user/Projects/dotflies
for package in fastfetch fish wezterm nvim noctalia hypr; do
  echo "===== $package ====="
  stow --simulate --verbose "$package"
done
```

Expected:

- No `CONFLICT` lines.
- Planned links point into `/home/user/Projects/dotflies/...`.
- Target paths are under `/home/user`, not `/home/kanoah`.

**Step 2: Resolve conflicts safely if any appear**

For each conflict, use this pattern:

```bash
backup_dir="$(find "$HOME" -maxdepth 1 -type d -name 'dotfiles-backup-*' | sort | tail -n 1)"
conflict="$HOME/.config/EXAMPLE"
mkdir -p "$backup_dir/conflicts"
mv "$conflict" "$backup_dir/conflicts/"
```

Then rerun the simulation for that package.

Do not run `stow --adopt` on a fresh install unless the explicit goal is to import the fresh-install files into the repo. Here, the goal is to apply the repo dotfiles, not merge unknown files.

**Step 3: Commit**

No commit. Conflict resolution affects `$HOME`, not repo state.

---

## Task 7: Stow Low-Risk Packages First

**Objective:** Apply simple configs before shell/window-manager configs.

**Files:**
- Create symlinks under: `~/.config/fastfetch`
- Create symlinks under: `~/.config/wezterm`

**Step 1: Stow `fastfetch`**

Run:

```bash
cd /home/user/Projects/dotflies
stow --verbose fastfetch
```

Expected:

- Symlinks are created for `~/.config/fastfetch/config.jsonc` and `~/.config/fastfetch/ascii.txt`.

**Step 2: Validate `fastfetch`**

Run:

```bash
fastfetch
```

Expected:

- Fastfetch renders without config parse errors.

**Step 3: Stow `wezterm`**

Run:

```bash
cd /home/user/Projects/dotflies
stow --verbose wezterm
```

Expected:

- Symlinks are created under `~/.config/wezterm`.

**Step 4: Validate WezTerm config syntax**

Run:

```bash
wezterm start --always-new-process --config-file "$HOME/.config/wezterm/wezterm.lua" -- bash -lc 'echo wezterm-config-ok; sleep 1'
```

Expected:

- A WezTerm window opens briefly or runs the command.
- No Lua/config error appears.

If launching a GUI window is inconvenient, run:

```bash
wezterm ls-fonts --config-file "$HOME/.config/wezterm/wezterm.lua"
```

Expected:

- WezTerm loads config and lists fonts without syntax errors.

**Step 5: Commit**

No commit unless repo files were changed.

---

## Task 8: Stow and Validate Fish Shell Config

**Objective:** Apply Fish config without locking the user into a broken login shell.

**Files:**
- Create symlinks under: `~/.config/fish`

**Step 1: Stow `fish`**

Run:

```bash
cd /home/user/Projects/dotflies
stow --verbose fish
```

Expected:

- Symlinks are created under `~/.config/fish`.

**Step 2: Validate Fish config in a non-login shell first**

Run:

```bash
fish -lc 'echo fish-config-ok; command -v mise; command -v oh-my-posh'
```

Expected:

```text
fish-config-ok
/usr/bin/mise
/usr/bin/oh-my-posh
```

If `mise activate fish | source` fails, install or fix `mise` before continuing.

If `oh-my-posh init fish ... | source` fails due to network/theme download, either:

- keep the remote theme and ensure network is available, or
- change the config to use a local theme file.

**Step 3: Change default shell only after validation**

Run:

```bash
chsh -s /usr/bin/fish
```

Expected:

- Password prompt succeeds.
- New terminal sessions use Fish.

Do not run this step until `fish -lc ...` passes.

**Step 4: Verify new shell entry exists**

Run:

```bash
grep -x '/usr/bin/fish' /etc/shells
getent passwd "$USER"
```

Expected:

- `/usr/bin/fish` is listed in `/etc/shells`.
- User passwd entry ends with `/usr/bin/fish` after `chsh`.

**Step 5: Commit**

No commit unless repo files were changed.

---

## Task 9: Stow and Validate Neovim

**Objective:** Apply Neovim config and allow plugin bootstrap to complete.

**Files:**
- Create symlinks under: `~/.config/nvim`

**Step 1: Stow `nvim`**

Run:

```bash
cd /home/user/Projects/dotflies
stow --verbose nvim
```

Expected:

- Symlinks are created under `~/.config/nvim`.

**Step 2: Start Neovim headless once for plugin/bootstrap checks**

Run:

```bash
nvim --headless '+Lazy! sync' +qa
```

Expected:

- Lazy.nvim installs/syncs plugins.
- Command exits successfully.

If this fails due to missing external tools, install the missing tool and rerun.

**Step 3: Run Neovim health check**

Run:

```bash
nvim --headless '+checkhealth' '+w! /tmp/nvim-checkhealth.txt' +qa
sed -n '1,220p' /tmp/nvim-checkhealth.txt
```

Expected:

- Health report is generated.
- Review errors/warnings for missing providers, formatters, linters, language servers.

**Step 4: Validate Salesforce/custom plugin files still load**

Run:

```bash
nvim --headless '+lua require("custom.plugins.salesforce")' +qa
nvim --headless '+lua require("custom.plugins.salesforce_sf")' +qa
```

Expected:

- Both commands exit without Lua module errors.

**Step 5: Commit**

No commit unless repo files were changed.

---

## Task 10: Stow Noctalia Before Hyprland

**Objective:** Ensure Noctalia settings exist before Hyprland autostarts `noctalia`.

**Files:**
- Create symlinks under: `~/.config/noctalia`

**Step 1: Stow `noctalia`**

Run:

```bash
cd /home/user/Projects/dotflies
stow --verbose noctalia
```

Expected:

- Symlinks are created for `~/.config/noctalia/settings.json` and `~/.config/noctalia/plugins.json`.

**Step 2: Validate JSON syntax**

Run:

```bash
python -m json.tool "$HOME/.config/noctalia/settings.json" >/tmp/noctalia-settings.json
python -m json.tool "$HOME/.config/noctalia/plugins.json" >/tmp/noctalia-plugins.json
```

Expected:

- Both commands exit successfully.

If `python` is unavailable, use:

```bash
jq . "$HOME/.config/noctalia/settings.json" >/tmp/noctalia-settings.json
jq . "$HOME/.config/noctalia/plugins.json" >/tmp/noctalia-plugins.json
```

**Step 3: Validate Noctalia command**

Run:

```bash
command -v noctalia
noctalia --help | head -n 40
```

Expected:

- `noctalia` command exists.
- Help output or valid command output appears.

**Step 4: Commit**

No commit unless repo files were changed.

---

## Task 11: Verify Monitor and App Assumptions Before Stowing Hyprland

**Objective:** Prevent a black-screen or unusable Hyprland session due to wrong monitor/output/app names.

**Files:**
- Possibly modify: `/home/user/Projects/dotflies/hypr/.config/hypr/hyprland.lua`

**Step 1: Check available monitor names from the current session**

If already inside Hyprland, run:

```bash
hyprctl monitors all
```

Expected:

- Confirm the active output name.
- The current dotfile expects `DP-3`.

If not inside Hyprland, use:

```bash
ls /sys/class/drm
```

Expected:

- Look for connector names such as `card0-DP-3`, `card0-HDMI-A-1`, etc.

**Step 2: Decide whether `hyprland.lua` monitor line must change**

Current code:

```lua
hl.monitor({
    output   = "DP-3",
    mode     = "3440x1440@180",
    position = "0x0",
    scale    = "1",
})
```

If the fresh install uses the same monitor/output, keep it.

If the output differs, change only the `output`, `mode`, or `scale` values. Example:

```lua
hl.monitor({
    output   = "DP-1",
    mode     = "3440x1440@180",
    position = "0x0",
    scale    = "1",
})
```

**Step 3: Verify app commands exist**

Run:

```bash
for cmd in wezterm vivaldi dolphin; do command -v "$cmd" || echo "missing: $cmd"; done
```

Expected:

- `wezterm`, `vivaldi`, and `dolphin` exist.

If a command is missing, either install it or update these lines in `hyprland.lua`:

```lua
local terminal    = "wezterm"
local browser     = "vivaldi"
local fileManager = "dolphin"
```

**Step 4: Commit if `hyprland.lua` changed**

Run:

```bash
cd /home/user/Projects/dotflies
git diff -- hypr/.config/hypr/hyprland.lua
git add hypr/.config/hypr/hyprland.lua
git commit -m "fix: adapt Hyprland config for current CachyOS hardware"
```

Expected:

- Diff only contains hardware/app-command changes.

Skip commit if no file changed or if the user does not want commits.

---

## Task 12: Stow and Validate Hyprland Config

**Objective:** Apply Hyprland config only after dependencies and stale path fixes are handled.

**Files:**
- Create symlinks under: `~/.config/hypr`

**Step 1: Stow `hypr`**

Run:

```bash
cd /home/user/Projects/dotflies
stow --verbose hypr
```

Expected:

- Symlinks are created under `~/.config/hypr`.

**Step 2: Verify symlinks point into repo**

Run:

```bash
readlink -f "$HOME/.config/hypr/hyprland.lua"
readlink -f "$HOME/.config/hypr/hyprland.conf"
readlink -f "$HOME/.config/hypr/hyprtoolkit.conf"
```

Expected:

```text
/home/user/Projects/dotflies/hypr/.config/hypr/hyprland.lua
/home/user/Projects/dotflies/hypr/.config/hypr/hyprland.conf
/home/user/Projects/dotflies/hypr/.config/hypr/hyprtoolkit.conf
```

**Step 3: Search for stale paths in live config**

Run:

```bash
grep -RIn '/home/kanoah\|/home/kanoah/Code/dotfiles' "$HOME/.config/hypr" || true
```

Expected:

- No matches.

**Step 4: Validate Hyprland config from inside Hyprland**

If already inside Hyprland, run:

```bash
hyprctl reload
hyprctl monitors
hyprctl clients | head -n 80
```

Expected:

- Reload succeeds.
- Monitor appears with expected resolution/scale.
- No config parse error notification appears.

**Step 5: Validate from a TTY if not already inside Hyprland**

Run:

```bash
Hyprland
```

Expected:

- Hyprland starts.
- Noctalia autostarts from this config block:

```lua
hl.on("hyprland.start", function () 
  hl.exec_cmd("noctalia")
end)
```

If Hyprland fails to start, switch back to TTY and inspect:

```bash
journalctl --user -b --no-pager | grep -Ei 'hypr|noctalia|lua|error' | tail -n 120
```

**Step 6: Commit**

No commit unless repo files were changed.

---

## Task 13: Validate Desktop Behavior End-to-End

**Objective:** Confirm the fresh install is actually usable with the restored dotfiles.

**Files:**
- No planned repo changes.

**Step 1: Validate Super-key app binds**

Inside Hyprland, manually test:

```text
Super+Return -> opens WezTerm
Super+B      -> opens Vivaldi
Super+E      -> opens Dolphin
Super+Space  -> toggles Noctalia launcher
Super+Home   -> opens Noctalia control center
Super+X      -> opens session panel
```

Expected:

- Every keybind launches the expected app/panel.

**Step 2: Validate scrolling layout binds**

Open three terminal windows, then manually test:

```text
Super+H/L/J/K             -> focus movement
Super+Shift+H/L/J/K       -> consume/expel windows between columns
Super+Ctrl+H/L            -> pan viewport
Super+Shift+Return        -> promote window to own column
Super+Shift+Backspace     -> fit all columns
Super+F                   -> toggle column width 1.0 <-> 0.5
Super+R                   -> resize submap
Escape                    -> exit resize submap
```

Expected:

- No key leaks literal letters into the focused app while the resize submap is active.
- Scrolling layout behaves like the previous setup.

**Step 3: Validate shell/editor/terminal integration**

Run inside WezTerm:

```bash
echo "$SHELL"
fish -lc 'echo fish-ok; mise --version; oh-my-posh --version'
nvim --headless '+checkhealth' '+w! /tmp/nvim-checkhealth-after-stow.txt' +qa
fastfetch
```

Expected:

- Shell is Fish if `chsh` was performed.
- `mise` and `oh-my-posh` work.
- Neovim health report is generated.
- Fastfetch renders.

**Step 4: Validate Noctalia persistence**

Run:

```bash
noctalia msg panels.status || true
pgrep -a noctalia || true
```

Expected:

- Noctalia process exists after Hyprland start.
- If `noctalia msg panels.status` is not a valid command, check Noctalia docs/help and use the equivalent status command.

**Step 5: Commit**

No commit unless validation led to repo config changes.

---

## Task 14: Optional Cleanup and Documentation

**Objective:** Make the next reinstall easier by documenting the exact successful steps.

**Files:**
- Create or modify: `/home/user/Projects/dotflies/README.md`

**Step 1: Create a bootstrap README after the setup is confirmed**

Create `/home/user/Projects/dotflies/README.md` with this content, adjusted for any discoveries during execution:

```markdown
# dotflies

Personal CachyOS dotfiles managed with GNU Stow.

## Fresh CachyOS bootstrap

```bash
sudo pacman -Syu
sudo pacman -S --needed git stow fish wezterm neovim fastfetch hyprland xdg-desktop-portal-hyprland dolphin vivaldi ripgrep fd fzf unzip wl-clipboard cliphist grim slurp brightnessctl playerctl pipewire pipewire-pulse wireplumber networkmanager
paru -S --needed mise-bin oh-my-posh-bin noctalia-shell

cd /home/user/Projects/dotflies
stow --simulate --verbose fastfetch fish wezterm nvim noctalia hypr
stow --verbose fastfetch wezterm fish nvim noctalia hypr

fish -lc 'mise --version; oh-my-posh --version'
nvim --headless '+Lazy! sync' +qa
fastfetch
```

## Packages

- `fastfetch` -> `~/.config/fastfetch`
- `wezterm` -> `~/.config/wezterm`
- `fish` -> `~/.config/fish`
- `nvim` -> `~/.config/nvim`
- `noctalia` -> `~/.config/noctalia`
- `hypr` -> `~/.config/hypr`
```

**Step 2: Verify Markdown formatting**

Run:

```bash
sed -n '1,220p' /home/user/Projects/dotflies/README.md
```

Expected:

- README explains the successful bootstrap steps clearly.

**Step 3: Commit**

Run:

```bash
cd /home/user/Projects/dotflies
git add README.md
git commit -m "docs: add CachyOS dotfiles bootstrap notes"
```

Expected:

- Documentation commit succeeds.

Skip commit if the user does not want commits.

---

## Tests / Validation Summary

Run these final checks after all packages are stowed:

```bash
cd /home/user/Projects/dotflies

git status --short --branch

for package in fastfetch fish wezterm nvim noctalia hypr; do
  echo "===== $package ====="
  stow --simulate --verbose "$package"
done

for path in \
  "$HOME/.config/fastfetch/config.jsonc" \
  "$HOME/.config/wezterm/wezterm.lua" \
  "$HOME/.config/fish/config.fish" \
  "$HOME/.config/nvim/init.lua" \
  "$HOME/.config/noctalia/settings.json" \
  "$HOME/.config/hypr/hyprland.lua" \
  "$HOME/.config/hypr/hyprland.conf"
do
  printf '%s -> %s\n' "$path" "$(readlink -f "$path")"
done

fish -lc 'echo fish-ok; mise --version; oh-my-posh --version'
wezterm ls-fonts --config-file "$HOME/.config/wezterm/wezterm.lua" >/tmp/wezterm-fonts.txt
nvim --headless '+Lazy! sync' +qa
nvim --headless '+checkhealth' '+w! /tmp/nvim-checkhealth-final.txt' +qa
python -m json.tool "$HOME/.config/noctalia/settings.json" >/tmp/noctalia-settings-final.json
python -m json.tool "$HOME/.config/noctalia/plugins.json" >/tmp/noctalia-plugins-final.json
fastfetch
```

Expected:

- Git status is clean except intentional changes.
- Stow simulations show no conflicts.
- All symlinks resolve into `/home/user/Projects/dotflies`.
- Fish, WezTerm, Neovim, Noctalia JSON, and Fastfetch validations pass.
- Hyprland reload/start succeeds during desktop validation.

---

## Risks, Tradeoffs, and Open Questions

### Risks

- `.stowrc` and `hyprland.conf` currently contain stale `/home/kanoah` paths; using Stow before fixing them can place links correctly but still leave Hyprland sourcing a nonexistent file.
- Monitor output `DP-3` may differ after reinstall depending on GPU/port enumeration.
- `hyprland.lua` uses Hyprland Lua API (`hl.*` globals), not standard `.conf` syntax; validation must happen in the environment that provides that Lua integration.
- `noctalia-shell` package name may differ depending on CachyOS/AUR packaging.
- Fish config executes `mise activate fish | source` and `oh-my-posh init ... | source`; a missing dependency can make new shells noisy or partially broken.
- `fish_variables` is machine/user-specific in some setups. If it causes odd universal-variable behavior, back it up and consider removing it from the stow package in a later cleanup task.

### Tradeoffs

- Keeping explicit `/home/user` paths is simple and reliable on this machine, but less portable than `$HOME`/`~`-based paths.
- Stowing one package at a time is slower than `stow */`, but much safer on a fresh install because conflicts are isolated.
- Avoiding `stow --adopt` prevents accidental import of fresh-install generated files, but requires manual backup/removal of conflicts.

### Open Questions

- Is the repository intentionally named `dotflies`, or should it eventually be renamed to `dotfiles`?
- Is the fresh install still using monitor output `DP-3` at `3440x1440@180`?
- Is `vivaldi` still the preferred browser on this install?
- Should `fish_variables` be stowed, or should it be treated as machine-local state?
- Should a reusable `bootstrap-cachyos.sh` be added after the manual setup succeeds?

---

## Recommended Execution Order

1. Task 1: Confirm repo path and baseline.
2. Task 2: Back up existing configs.
3. Task 3: Fix `.stowrc`.
4. Task 4: Fix stale Hyprland path.
5. Task 5: Install packages.
6. Task 6: Run all Stow simulations.
7. Task 7: Stow `fastfetch` and `wezterm`.
8. Task 8: Stow and validate `fish`; change shell only after validation.
9. Task 9: Stow and validate `nvim`.
10. Task 10: Stow and validate `noctalia`.
11. Task 11: Confirm monitor/app assumptions.
12. Task 12: Stow and validate `hypr`.
13. Task 13: Validate full desktop behavior.
14. Task 14: Optionally document the successful process in `README.md`.

This order minimizes the chance of ending up with a broken shell or broken Hyprland login on the fresh CachyOS install.
