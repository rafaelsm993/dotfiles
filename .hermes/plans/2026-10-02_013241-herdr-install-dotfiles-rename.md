# Install Herdr + rename `dotflies` -> `dotfiles` + port WezTerm tmux-style keybinds to Herdr

Date: 2026-10-02
Repo (current path): `/mnt/FILES/Projects/dotflies`
Repo (final path): `/mnt/FILES/Projects/dotfiles`

---

## Goal

Install Herdr on this CachyOS machine, add a stow-managed `herdr` package to the
dotfiles repo whose `config.toml` reproduces the WezTerm `CTRL+Space` tmux-style
keymap, wire Herdr into the installed coding agents (Claude Code, Copilot CLI,
Hermes) with integrations + the Herdr agent skill, and rename the misspelled
local `dotflies` folder to `dotfiles` without leaving a single broken symlink behind.

---

## Current context (verified on disk, 2026-10-02)

- Repo at `/mnt/FILES/Projects/dotflies`, local remote still
  `https://github.com/rafaelsm993/dotflies.git`. **The GitHub repo is ALREADY
  renamed to `rafaelsm993/dotfiles`** (verified 2026-10-05: `gh repo view` on both
  names returns `dotfiles`; the old URL works only via GitHub's redirect).
  Branch `main` tracking `origin/main`.
- Coding agents on PATH: `claude` (`~/.local/bin`, config dir `~/.claude` exists,
  `~/.claude/skills/` exists), `copilot` (`~/.local/bin`, `~/.copilot` exists),
  `hermes` (this agent; active profile `HERMES_HOME=~/.hermes/profiles/trismegistus`).
  Not installed: codex, opencode, pi, etc. Also present: `lazygit`, `yazi`, `fzf`,
  `fd`, `jq`, `btop`, `npx` (via Hermes' bundled node).
- **15 files are modified and uncommitted** (`git diff --stat`): `.stowrc`,
  `fish/*` (3), `hypr/*` (3), `noctalia/*` (2), `nvim/*` (4), `wezterm/*` (2).
  Plus untracked `.hermes/` and `README.md`. This is the "repo is outdated" part.
- Managed with GNU Stow. `/mnt/FILES/Projects/dotflies/.stowrc` is currently:

  ```
  --target=/home/user
  --dir=/mnt/FILES/Projects/dotflies
  ```

- Stow packages: `fastfetch`, `fish`, `hypr`, `noctalia`, `nvim`, `wezterm`.
- Symlink state in `~/.config` is **partially stowed / partially broken**:
  - `~/.config/fastfetch` -> `../Projects/dotflies/fastfetch/.config/fastfetch`
    — **BROKEN**: resolves to `/home/user/Projects/dotflies`, which no longer
    exists (`/home/user/Projects` contains only a `.directory` file).
    `readlink -f ~/.config/fastfetch` prints nothing.
  - `~/.config/wezterm/` is a **real directory** containing a correct symlink
    `wezterm.lua -> /mnt/FILES/.../wezterm/.config/wezterm/wezterm.lua` and an
    **empty real directory** `colors/` — so `colors/Noctalia.toml` from the repo
    is **not** linked into place.
  - `~/.config/fish`, `~/.config/hypr`, `~/.config/nvim`, `~/.config/noctalia`
    are real directories holding per-file symlinks into the repo, mixed with
    machine-local non-repo files (`~/.config/hypr/config/`,
    `~/.config/hypr/noctalia.lua`, `~/.config/hypr/xdph.conf`,
    `~/.config/noctalia/colors.json`). Those local files MUST survive.
- Tools present: `stow`, `git`, `curl`, `fish` (login shell), `wezterm`,
  `gh` (`~/.local/bin/gh`), `python3`. `~/.local/bin` is on `$PATH`.
- Herdr install script (`https://herdr.dev/install.sh`, inspected at
  `/tmp/herdr-install.sh`, 150 lines): downloads a release binary, verifies a
  SHA-256 from a manifest, installs to `${HERDR_INSTALL_DIR:-$HOME/.local/bin}`,
  `chmod +x`, warns if the dir is not on `$PATH`. No root, no systemd units, no
  shell-rc edits. Safe to run as the user.
- Herdr facts used below come from `https://herdr.dev/agent-guide.md`,
  `https://herdr.dev/docs/configuration/`, `https://herdr.dev/docs/config-reference/`
  and `https://herdr.dev/docs/keyboard/` (docs latest = 0.9.3).
  Config file: `~/.config/herdr/config.toml`. Reload: `herdr server reload-config`.
  Print defaults: `herdr --default-config`. Live binding list: `prefix+?`.

### Assumptions

1. The user keeps using WezTerm as the outer terminal, with Herdr running inside
   it as the multiplexer (not a tmux replacement running *next to* WezTerm panes).
2. **Decided by user:** GitHub rename is already done; only the local folder and
   the `origin` URL change. **Prefix is `CTRL+Space`** (WezTerm leader retired).
   **Install the Herdr agent skill + integrations** and agent-workflow tooling.
3. **Standing rule: no `git commit`, no `git push`, no branch creation without
   the user explicitly saying OK.** Every commit step below is "prepare the
   staged change, show `git status`, then ASK". The user commits himself.

---

## Architecture / proposed approach

Herdr becomes the multiplexer and takes over the `CTRL+Space` prefix; WezTerm is
demoted to a plain terminal emulator so it stops swallowing that chord. The
Herdr config ships as a new stow package `herdr/.config/herdr/config.toml` in the
same repo, so it is versioned and deployed exactly like every other package.
The folder rename is done as a clean unstow -> rename -> fix `.stowrc` -> restow
cycle so no symlink is ever left pointing at the old path.

### Why WezTerm must give up its leader

WezTerm's current `config.leader = { key = 'Space', mods = 'CTRL' }` is consumed
by WezTerm **before** the byte reaches the program inside the pane. If Herdr's
prefix is also `ctrl+space`, Herdr never sees it — every `<leader>x` would hit
WezTerm's own (now useless) pane/tab actions instead of Herdr's. So WezTerm's
leader block and all its split/pane/tab bindings are removed, keeping only
direct `CTRL+SHIFT+…` chords that do not collide with Herdr.

### Keybinding mapping (WezTerm -> Herdr)

| Action | WezTerm today | Herdr key name | Herdr binding in this plan | Herdr default |
|---|---|---|---|---|
| Prefix | `CTRL+Space` leader | `prefix` | `ctrl+space` | `ctrl+b` |
| Split side-by-side | `<leader>\` (`SplitHorizontal`) | `split_vertical` | `prefix+backslash`, `prefix+v` | `prefix+v` |
| Split stacked | `<leader>-` (`SplitVertical`) | `split_horizontal` | `prefix+minus` | `prefix+minus` |
| Focus pane left/down/up/right | `<leader>h/j/k/l` | `focus_pane_*` | `prefix+h/j/k/l` | same |
| Zoom pane | `<leader>f` | `zoom` | `prefix+f`, `prefix+z` | `prefix+z` |
| Close pane | `<leader>x` | `close_pane` | `prefix+x` | same |
| Close tab | `<leader>w` | `close_tab` | `prefix+w`, `prefix+shift+x` | `prefix+shift+x` |
| Resize mode | `<leader>r` | `resize_mode` | `prefix+r` | same |
| New tab | `<leader>t` | `new_tab` | `prefix+t`, `prefix+c` | `prefix+c` |
| Next / prev tab | `<leader>n` / `<leader>p` | `next_tab` / `previous_tab` | `prefix+n` / `prefix+p` | same |
| Tab 1-9 | `<leader>1..9` | `switch_tab` | `prefix+1..9` | same |
| Rename tab | `<leader>,` | `rename_tab` | `prefix+comma`, `prefix+shift+t` | `prefix+shift+t` |
| Copy mode | `<leader>[` | `copy_mode` | `prefix+[` | same |
| Search | `<leader>/` | — | none (search lives *inside* copy mode: `prefix+[` then `/`) | — |
| Transparency toggle | `<leader>o` | — | stays in WezTerm, moved to `CTRL+SHIFT+O` | — |

Note the WezTerm naming inversion: WezTerm `SplitHorizontal` = side-by-side =
Herdr `split_vertical`. Do not "fix" this; it is correct as written.

Collision introduced by the above: `prefix+w` is Herdr's default
`workspace_picker`. It is remapped to `prefix+a` (free in the default keymap)
and the always-available `prefix+g` goto picker still works.

Resize mode in WezTerm is `h/j/k/l` inside the mode; Herdr's resize mode already
uses arrows/`hjkl` internally, so `keys.resize_pane_*` stay unset.

---

## Step-by-step tasks

Each task is 2-5 minutes. Run every command from `fish` (the user's shell).
Commands below are fish-compatible (no bashisms; env vars via `set -x`).

**Execution order is NOT numeric.** Run tasks in exactly this order:

```
0, 1, 2, 3, 4, 5, 6, 7, 9, 8, 16, 17, 10, 11, 13, 12, 14, 15
```

- Task 9 (retire WezTerm leader) must precede Task 8 (interactive herdr test),
  otherwise WezTerm swallows `CTRL+Space` and Task 8 fails for the wrong reason.
- Task 13 (README rewrite) must precede Task 12 (repo-wide `dotflies` grep),
  otherwise Task 12's grep gate fails on README.md, which Task 13 fixes.
- Tasks 16-17 (agent integrations + skill) run before the rename: they write only
  outside the repo, and verifying them needs a working Herdr from Task 8.

---

### Task 0 — Snapshot the current symlink state (read-only, 2 min)

**Why:** the rename in Task 10 must restore exactly this set of links.

```fish
cd /mnt/FILES/Projects/dotflies
find ~/.config -type l -lname '*dotflies*' -printf '%p -> %l\n' | sort > /tmp/symlinks-before.txt
wc -l < /tmp/symlinks-before.txt
```

**Expected:** `45` (measured 2026-10-05). Do NOT add `-maxdepth`: the nvim links sit
up to 6 levels deep (`~/.config/nvim/lua/custom/plugins/*.lua`), and a depth-2
search finds only 14 of the 45. The list includes
`/home/user/.config/wezterm/wezterm.lua -> ../../../../mnt/FILES/Projects/dotflies/...`,
the three `hypr` links, the `fish`/`nvim`/`noctalia` links,
and the broken `/home/user/.config/fastfetch -> ../Projects/dotflies/...`.
Keep this file; Task 12 diffs against it.

---

### Task 1 — Deal with the 15 uncommitted files BEFORE touching anything (3 min)

**Why:** the rename and the restow will churn the working tree; an already-dirty
tree makes "what did the plan break" unanswerable.

```fish
cd /mnt/FILES/Projects/dotflies
git status --short
git diff --stat
```

**Expected:** the 15 modified files listed in "Current context", plus untracked
`.hermes/` and `README.md`.

Heads-up: `hypr/.config/hypr/hyprland.lua` now also contains an `HDMI-A-1`
`hl.monitor({... mirror = "DP-3" })` block added 2026-10-04 for the TV. That TV
still had no signal (kernel `EDID err: 2` on HDMI-A-1: a cable/TV handshake problem,
not config). Ask the user whether that block goes into this commit or gets left
unstaged (`git restore --staged hypr/.config/hypr/hyprland.lua`).

Then:

1. Create `/mnt/FILES/Projects/dotflies/.gitignore` **only if it does not exist**,
   with exactly:

   ```gitignore
   .hermes/
   ```

2. Stage everything else and show it:

   ```fish
   git add -A
   git status --short
   ```

   **Expected:** `A  .gitignore`, `A  README.md`, `M` for the 15 files, and **no**
   `.hermes/` entries.

3. **STOP. Ask the user for explicit permission to commit**, suggesting the
   message `Sync dotfiles with current machine state`. Do not commit or push
   without a yes. If the user says no, `git reset` and continue — the rest of the
   plan still works on a dirty tree, it is just harder to audit.

---

### Task 2 — Install Herdr (2 min)

```fish
curl -fsSL https://herdr.dev/install.sh | sh
```

**Expected (last lines):**

```
installed herdr to /home/user/.local/bin/herdr
```

with no PATH warning (`~/.local/bin` is already on `$PATH` via
`fish_add_path`/CachyOS config).

Verify:

```fish
command -v herdr
herdr --version
```

**Expected:** `/home/user/.local/bin/herdr` and a version line `0.9.x` or newer.

If `command -v herdr` fails in this shell, open a new fish shell (`exec fish`)
and retry before changing any PATH config.

---

### Task 3 — Capture the shipped default config as a reference (2 min)

```fish
herdr --default-config > /tmp/herdr-default-config.toml
wc -l /tmp/herdr-default-config.toml
grep -n '^\[' /tmp/herdr-default-config.toml
```

**Expected:** a non-empty TOML with sections including `[keys]`, `[theme]`,
`[ui]`, `[terminal]`, `[update]`.

This file is the ground truth for key names on the installed version. If any key
used in Task 5 is missing from it, **stop and check**
`https://herdr.dev/docs/config-reference/` for that version instead of guessing.

---

### Task 4 — Create the `herdr` stow package directory (2 min)

```fish
mkdir -p /mnt/FILES/Projects/dotflies/herdr/.config/herdr
ls -la /mnt/FILES/Projects/dotflies/herdr/.config/herdr
```

**Expected:** an empty directory.

---

### Task 5 — Write the Herdr config (5 min)

Create `/mnt/FILES/Projects/dotflies/herdr/.config/herdr/config.toml` with
exactly this content:

```toml
# Herdr config — managed in the dotfiles repo, stowed to ~/.config/herdr/config.toml
# Reference for every key/default: https://herdr.dev/docs/config-reference/
# Apply changes to a running server with: herdr server reload-config
#
# Keymap mirrors the old WezTerm tmux-style leader map (CTRL+Space + key).
# WezTerm no longer defines a leader, so CTRL+Space reaches Herdr untouched.

onboarding = false

[terminal]
# Panes start in fish, matching the login shell.
default_shell = "fish"
# Inherit the cwd of the pane/workspace a new pane is created from.
new_cwd = "follow"

[keys]
# ── Prefix ────────────────────────────────────────────────────────────────
prefix = "ctrl+space"

# ── Splits (WezTerm naming is inverted: its SplitHorizontal = side by side) ─
split_vertical   = ["prefix+backslash", "prefix+v"]  # side by side (was <leader>\)
split_horizontal = ["prefix+minus"]               # stacked       (was <leader>-)

# ── Pane focus ────────────────────────────────────────────────────────────
focus_pane_left  = "prefix+h"
focus_pane_down  = "prefix+j"
focus_pane_up    = "prefix+k"
focus_pane_right = "prefix+l"

# ── Pane management ───────────────────────────────────────────────────────
zoom        = ["prefix+f", "prefix+z"]            # was <leader>f
close_pane  = "prefix+x"                          # was <leader>x
resize_mode = "prefix+r"                          # was <leader>r (h/j/k/l inside)
copy_mode   = "prefix+["                          # was <leader>[ ; press / inside to search

# ── Tabs ──────────────────────────────────────────────────────────────────
new_tab      = ["prefix+t", "prefix+c"]           # was <leader>t
next_tab     = "prefix+n"                         # was <leader>n
previous_tab = "prefix+p"                         # was <leader>p
switch_tab   = "prefix+1..9"                      # was <leader>1..9
rename_tab   = ["prefix+comma", "prefix+shift+t"] # was <leader>,
close_tab    = ["prefix+w", "prefix+shift+x"]     # was <leader>w

# ── Workspaces ────────────────────────────────────────────────────────────
# prefix+w is Herdr's default workspace picker; it moves here because
# prefix+w is close_tab above (WezTerm muscle memory wins).
workspace_picker = "prefix+a"
switch_workspace = "prefix+shift+1..9"            # one workspace per repo/task

# ── Agents ────────────────────────────────────────────────────────────────
# prefix+g = goto picker (default): every agent, filter b/w/i/d = blocked/working/idle/done.
# prefix+o = jump to the agent that just raised a notification (default).
focus_agent = "prefix+alt+1..9"                   # jump straight to agent N in the sidebar

# ── Agentic-coding popups (session-modal, layout untouched) ───────────────
[[keys.command]]
key = "prefix+alt+g"
type = "popup"
command = "lazygit"
description = "lazygit (review agent diffs)"
width = "90%"
height = "90%"

[[keys.command]]
key = "prefix+alt+y"
type = "popup"
command = "yazi"
description = "yazi file manager"
width = "90%"
height = "90%"

[[keys.command]]
key = "prefix+alt+s"
type = "popup"
command = "exec fish"
description = "scratch shell"
width = "80%"
height = "80%"

[ui]
tab_bar_position = "bottom"                       # matches wezterm tab_bar_at_bottom
tab_bar_right = [{ type = "zoom" }, { type = "datetime", format = "%H:%M" }]

# Tell me when a background agent finishes or blocks on input.
[ui.toast]
delivery = "herdr"
delay_seconds = 1
```

Verify it parses and has no duplicate keys:

```fish
python3 -c "import tomllib,sys; d=tomllib.load(open('/mnt/FILES/Projects/dotflies/herdr/.config/herdr/config.toml','rb')); print(sorted(d['keys'].keys()), len(d['keys']['command']), d['ui']['toast'])"
```

**Expected:** no traceback, and:

```
['close_pane', 'close_tab', 'command', 'copy_mode', 'focus_agent', 'focus_pane_down', 'focus_pane_left', 'focus_pane_right', 'focus_pane_up', 'new_tab', 'next_tab', 'prefix', 'previous_tab', 'rename_tab', 'resize_mode', 'split_horizontal', 'split_vertical', 'switch_tab', 'switch_workspace', 'workspace_picker', 'zoom'] 3 {'delivery': 'herdr', 'delay_seconds': 1}
```

---

### Task 6 — Prove every key name exists in this Herdr version (2 min)

```fish
for k in (python3 -c "import tomllib;print('\n'.join(tomllib.load(open('/mnt/FILES/Projects/dotflies/herdr/.config/herdr/config.toml','rb'))['keys'].keys()))")
    test "$k" = command; and continue   # [[keys.command]] is a user table, not in the defaults dump
    grep -q "^ *#\? *$k *=" /tmp/herdr-default-config.toml; or echo "MISSING KEY: $k"
end
echo done
```

(`'\n'.join` matters: fish command substitution splits on newlines only, so a
space-joined string becomes ONE loop item and the check silently passes.)

**Expected:** only `done`. Any `MISSING KEY: …` line means that key name does not
exist in the installed version — remove or correct it against
`https://herdr.dev/docs/config-reference/` before continuing. Do not invent names.

---

### Task 7 — Stow the `herdr` package (2 min)

```fish
mkdir -p ~/.config/herdr
cd /mnt/FILES/Projects/dotflies
stow --no-folding --simulate --verbose herdr
```

`mkdir` + `--no-folding` are mandatory: without them stow links the whole
`~/.config/herdr` directory into the repo, and herdr then writes its logs and
`sessions/` runtime state straight into the dotfiles working tree.

**Expected:** a `LINK: .config/herdr/config.toml => ...` line and **no**
`existing target is neither a link nor a directory` conflict. If
`~/.config/herdr/config.toml` already exists as a real file (Herdr may have
written one during first run), move it aside first:

```fish
mv ~/.config/herdr/config.toml ~/.config/herdr/config.toml.herdr-firstrun.bak
```

Then apply:

```fish
stow --no-folding --verbose herdr
test -d ~/.config/herdr; and not test -L ~/.config/herdr; and echo "herdr dir is real"
readlink -f ~/.config/herdr/config.toml
```

**Expected:** `herdr dir is real`, then
`/mnt/FILES/Projects/dotflies/herdr/.config/herdr/config.toml`

---

### Task 8 — Verify Herdr actually accepts the config (3 min)

```fish
herdr server stop 2>/dev/null
herdr --version
```

Then start Herdr in a project and read the status line:

```fish
cd /mnt/FILES/Projects/dotflies
herdr
```

**Expected:** Herdr opens with no yellow/red startup warning banner about invalid
config values (invalid values silently fall back to defaults **and** show a
startup warning — if you see one, the offending key is named in it).

Inside Herdr, press `CTRL+Space` then `?`.

**Expected:** the keybind help panel opens (this alone proves the custom prefix
works) and lists `prefix+backslash` / `prefix+v` for split vertical, `prefix+f` for zoom,
`prefix+w` for close tab, `prefix+a` for the workspace picker.

Smoke-test three bindings, in order:
1. `CTRL+Space` then `\` -> a pane appears to the right.
2. `CTRL+Space` then `h` -> focus returns to the left pane.
3. `CTRL+Space` then `q` -> detaches; the shell prompt returns and the panes keep
   running. `herdr` reattaches to the same layout.

If `CTRL+Space` does nothing at this point, WezTerm is still eating it — Task 9
was skipped or WezTerm has not reloaded. If `CTRL+Space` then `\` does nothing but
the help panel works, the `backslash` key name was rejected: check the startup
warning, and drop it so only `prefix+v` remains.

---

### Task 9 — Retire WezTerm's leader so `CTRL+Space` reaches Herdr (5 min)

Edit `/mnt/FILES/Projects/dotflies/wezterm/.config/wezterm/wezterm.lua`.

**9a.** Delete the leader definition (currently line 65):

```lua
config.leader = { key = 'Space', mods = 'CTRL', timeout_milliseconds = 1000 }
```

**9b.** Delete the whole `config.key_tables = { resize_pane = { … } }` block
(currently lines 69-78) — Herdr owns resize mode now.

**9c.** Replace the entire `config.keys = { … }` table (currently lines 80-138)
with exactly:

```lua
-- Herdr is the multiplexer: WezTerm must not claim CTRL+Space or any
-- leader chord, or Herdr never sees the prefix. Only direct CTRL+SHIFT
-- chords remain here.
config.keys = {
  { key = 'c', mods = 'CTRL|SHIFT', action = act.CopyTo 'Clipboard' },
  { key = 'v', mods = 'CTRL|SHIFT', action = act.PasteFrom 'Clipboard' },
  { key = 'l', mods = 'CTRL|SHIFT', action = act.ShowDebugOverlay },
  -- Toggle terminal + Neovim transparency (Hyprland blur effect). Was <leader>o.
  { key = 'o', mods = 'CTRL|SHIFT', action = act.EmitEvent 'toggle-transparency' },
}
```

**9d.** In the `update-status` handler (currently lines 22-34), the
`window:active_key_table()` branch is now dead but harmless — leave it; it costs
nothing and keeps the file diff small.

Verify the file is still valid Lua and no leader survives:

```fish
cd /mnt/FILES/Projects/dotflies
luac -p wezterm/.config/wezterm/wezterm.lua; and echo "lua ok"
grep -n -E "config\.leader|'LEADER|config\.key_tables" wezterm/.config/wezterm/wezterm.lua; echo "grep-exit:$status"
```

**Expected:** `lua ok`, then `grep-exit:1` (no matches). The status handler's
`leader_is_active()`/`active_key_table()` calls intentionally remain and are not
matched by this pattern.

The file has **CRLF line endings** (`file` reports it). Keep them: an editor
that converts to LF turns this into a whole-file diff. Check with
`git diff --stat wezterm/` and confirm only about 60 lines changed, not 140.

`config.automatically_reload_config = true` is set, so open WezTerm windows pick
this up immediately. Confirm in a running WezTerm: press `CTRL+Space` outside
Herdr — nothing should happen (previously the `LDR` indicator appeared).

Then **ask the user** before committing Tasks 4-9 as e.g.
`Add herdr stow package; retire wezterm leader in favor of herdr prefix`.

---

### Task 10 — Rename `dotflies` -> `dotfiles` (5 min)

**Order matters.** Unstow first, rename second, fix `.stowrc` third, restow last.

**Do this from a TTY or with nothing important open.** Between 10a and 10d,
`~/.config/hypr/hyprland.lua` does not exist. Hyprland auto-reloads its config on
file changes, so the live session may briefly fall back to defaults (wrong
monitor layout, missing keybinds) until 10d restores the links. The repo is never
at risk. If the session gets weird, finish 10d and run `hyprctl reload`.

Close every shell/editor/herdr pane whose cwd is inside the repo, **including
the Hermes agent session**, whose working directory is this repo. The agent must
`cd /` (or be restarted from elsewhere) before 10b.

**10a.** Unstow every package from the old path:

```fish
cd /mnt/FILES/Projects/dotflies
stow -D --verbose fastfetch fish wezterm nvim noctalia hypr herdr
find ~/.config -type l -lname '*dotflies*' -printf '%p -> %l\n'
```

**Expected:** the `find` prints **only** the broken fastfetch link
`/home/user/.config/fastfetch -> ../Projects/dotflies/fastfetch/.config/fastfetch`
(stow refuses to remove links it did not create / that point elsewhere).
Remove that stale one by hand — it is a dangling symlink, nothing is lost:

```fish
test -L ~/.config/fastfetch; and not test -e ~/.config/fastfetch; and rm ~/.config/fastfetch
find ~/.config -type l -lname '*dotflies*' -printf '%p -> %l\n'; echo "exit:$status"
```

**Expected:** no output before `exit:0` — zero links referencing `dotflies`.

**10b.** Close anything holding the directory open (WezTerm tabs `cd`'d into it,
Herdr panes, nvim), then rename:

```fish
cd /mnt/FILES/Projects
mv dotflies dotfiles
ls -d /mnt/FILES/Projects/dotfiles
```

**Expected:** `/mnt/FILES/Projects/dotfiles`. If `mv` fails with
`Device or resource busy`, a process has it as cwd — find it with
`lsof +D /mnt/FILES/Projects/dotflies` (or `fuser -vm`) and close it.

**10c.** Rewrite `/mnt/FILES/Projects/dotfiles/.stowrc` to exactly:

```
--target=/home/user
--dir=/mnt/FILES/Projects/dotfiles
```

Verify:

```fish
cat /mnt/FILES/Projects/dotfiles/.stowrc
```

**10d.** Restow everything from the new path:

```fish
cd /mnt/FILES/Projects/dotfiles
stow --no-folding --simulate --verbose fastfetch fish wezterm nvim noctalia hypr herdr
```

**Expected:** `LINK:` lines only, no `CONFLICT`. Known snag: `~/.config/wezterm/`
is a real directory with an empty real `colors/` subdirectory, so stow will link
`wezterm.lua` and `colors/Noctalia.toml` individually — that is fine and is the
fix for the currently-unlinked `Noctalia.toml`. If stow reports a conflict on a
machine-local file (`~/.config/hypr/noctalia.lua`, `~/.config/hypr/xdph.conf`,
`~/.config/noctalia/colors.json`), **do not delete it** — it is not in the repo;
leave it and stow around it.

Apply:

```fish
stow --no-folding --verbose fastfetch fish wezterm nvim noctalia hypr herdr
hyprctl reload; hyprctl configerrors
```

**Expected:** `ok` and an empty `configerrors`. `--no-folding` means
`~/.config/fastfetch` becomes a real directory of file links instead of one
directory link. That's intended: it is the same shape as every other package and
stops runtime files leaking into the repo.

---

### Task 11 — Point `origin` at the already-renamed GitHub repo (1 min)

The GitHub repo is already `rafaelsm993/dotfiles`. Do **not** run `gh repo rename`.

```fish
cd /mnt/FILES/Projects/dotfiles
git remote set-url origin https://github.com/rafaelsm993/dotfiles.git
git remote get-url origin
git fetch origin --dry-run; echo "fetch-exit:$status"
```

**Expected:** `https://github.com/rafaelsm993/dotfiles.git` and `fetch-exit:0`.

---

### Task 12 — Verify no `dotflies` reference survives (3 min)

```fish
find ~/.config -xtype l -printf 'BROKEN: %p -> %l\n'; echo "broken-scan-exit:$status"
find ~/.config -type l -lname '*dotflies*' -printf '%p -> %l\n'; echo "stale-scan-exit:$status"
grep -rn "dotflies" /mnt/FILES/Projects/dotfiles --exclude-dir=.git --exclude-dir=.hermes; echo "grep-exit:$status"
readlink -f ~/.config/fastfetch ~/.config/wezterm/wezterm.lua ~/.config/wezterm/colors/Noctalia.toml ~/.config/herdr/config.toml ~/.config/fish/config.fish ~/.config/hypr/hyprland.lua
```

**Expected:**
- no `BROKEN:` lines,
- no stale `dotflies` links,
- `grep-exit:1` (no matches outside `.git`/`.hermes`; the old plan file under
  `.hermes/plans/` legitimately still says `dotflies` and is excluded),
- all five `readlink -f` lines resolving under `/mnt/FILES/Projects/dotfiles/`.

Also confirm the new link count matches the pre-rename snapshot:

```fish
find ~/.config -type l -lname '*dotfiles*' -printf '%p\n' | sort | wc -l
wc -l < /tmp/symlinks-before.txt
```

**Expected:** the new count is **at least 45 + 2** (`herdr/config.toml` and the
previously unlinked `colors/Noctalia.toml`, plus one link per file inside
`fastfetch/` now that it is no longer a single folded directory link minus the
old fastfetch dir link). It must never be lower than 45.

Note: `find -xtype l` also reports pre-existing broken links unrelated to this
repo. Only `BROKEN:` lines mentioning `dotflies`/`dotfiles` are failures here.
List any others to the user; do not delete them.

---

### Task 13 — Update `README.md` for the new name and the new package (4 min)

In `/mnt/FILES/Projects/dotfiles/README.md`:

1. Title `# dotflies` -> `# dotfiles`.
2. Every `/mnt/FILES/Projects/dotflies` -> `/mnt/FILES/Projects/dotfiles`.
3. Add to the Packages list:

   ```markdown
   - `herdr` -> `~/.config/herdr`
   ```

4. Update both `stow` command lines to include `herdr`:

   ```bash
   cd /mnt/FILES/Projects/dotfiles
   stow --simulate --verbose fastfetch fish wezterm nvim noctalia hypr herdr
   stow --verbose fastfetch wezterm fish nvim noctalia hypr herdr
   ```

5. Append this section at the end:

   ```markdown
   ## Herdr (terminal multiplexer)

   Installed with `curl -fsSL https://herdr.dev/install.sh | sh` into
   `~/.local/bin/herdr`. Config: `herdr/.config/herdr/config.toml`.

   WezTerm no longer defines a leader key — Herdr owns `CTRL+Space` as its
   prefix, so the old `<leader>` muscle memory works inside Herdr instead.

   | Bind | Action |
   |---|---|
   | `CTRL+Space` then `?` | Show all active bindings |
   | `CTRL+Space` then `\` or `v` | Split side by side |
   | `CTRL+Space` then `-` | Split stacked |
   | `CTRL+Space` then `h/j/k/l` | Focus pane |
   | `CTRL+Space` then `f` or `z` | Zoom pane |
   | `CTRL+Space` then `x` | Close pane |
   | `CTRL+Space` then `r` | Resize mode (`h/j/k/l`, `Esc` to exit) |
   | `CTRL+Space` then `t` or `c` | New tab |
   | `CTRL+Space` then `n` / `p` | Next / previous tab |
   | `CTRL+Space` then `1`-`9` | Jump to tab |
   | `CTRL+Space` then `,` | Rename tab |
   | `CTRL+Space` then `w` | Close tab |
   | `CTRL+Space` then `a` | Workspace picker |
   | `CTRL+Space` then `g` | Goto picker (agents/terminals) |
   | `CTRL+Space` then `[` | Copy mode (`/` searches inside it) |
   | `CTRL+Space` then `q` | Detach (everything keeps running) |

   | `CTRL+Space` then `Shift+1`-`9` | Jump to workspace |
   | `CTRL+Space` then `Alt+1`-`9` | Jump to agent |
   | `CTRL+Space` then `o` | Jump to the agent that just notified |
   | `CTRL+Space` then `Alt+g` | lazygit popup |
   | `CTRL+Space` then `Alt+y` | yazi popup |
   | `CTRL+Space` then `Alt+s` | scratch shell popup |

   Agent integrations (session restore after `herdr server stop`/reboot):
   `herdr integration install claude|copilot|hermes`; check with
   `herdr integration status`.

   WezTerm keeps only direct chords: `CTRL+SHIFT+C/V` copy/paste,
   `CTRL+SHIFT+L` debug overlay, `CTRL+SHIFT+O` transparency toggle.

   Apply config edits to a running server: `herdr server reload-config`.
   Stop everything: `herdr server stop`.
   ```

Verify:

```fish
grep -c dotflies /mnt/FILES/Projects/dotfiles/README.md; echo "exit:$status"
```

**Expected:** `0` and `exit:1`.

---

### Task 14 — Final end-to-end check, then ask to commit (3 min)

```fish
cd /mnt/FILES/Projects/dotfiles
git status --short
herdr server stop
herdr
```

Inside Herdr: `CTRL+Space` `?` (help lists the custom binds), `CTRL+Space` `\`
(split), `CTRL+Space` `t` (new tab), `CTRL+Space` `q` (detach).

Confirm config reload works against the stowed file:

```fish
herdr server reload-config
```

**Expected:** command exits 0 with no error about an unreadable or invalid config.

Then **ask the user** whether to commit (suggested message:
`Rename repo to dotfiles; document herdr package and keymap`) and whether to push.
Do not run `git commit` or `git push` without an explicit yes.

---

### Task 15 — Update Hermes' own notes that hard-code the old path (2 min)

These files outside the repo still say `/mnt/FILES/Projects/dotflies` and would
send future sessions to a path that no longer exists:

- `~/.hermes/profiles/trismegistus/skills/software-development/hyprland-config/SKILL.md`
- `~/.hermes/profiles/trismegistus/skills/software-development/hyprland-config/references/stow-dotfiles-migration.md`
- `~/.hermes/profiles/trismegistus/skills/software-development/hyprland-config/references/noctalia-v5-migration.md`

The agent updates them with `skill_manage` patches (not `sed`), replacing
`Projects/dotflies` with `Projects/dotfiles` and `dotflies/README.md` with
`dotfiles/README.md`. Leave any sentence that describes the rename itself.

Verify:

```fish
grep -rn "Projects/dotflies" ~/.hermes/profiles/trismegistus/skills; echo "exit:$status"
```

**Expected:** `exit:1`.

---

### Task 16 — Install Herdr agent integrations (4 min)

Integrations tell Herdr each agent's session id so panes resume into the same
conversation after a server restart/reboot. Only agents actually installed
here get one. Each config dir must already exist, and it does (see context).

```fish
herdr integration install claude
herdr integration install copilot
set -x HERMES_HOME ~/.hermes/profiles/trismegistus
herdr integration install hermes
set -e HERMES_HOME
herdr integration status
```

**Expected:** `herdr integration status` lists `claude` (v6+), `copilot` (v2+) and
`hermes` (v5+) as installed. Files written, per Herdr docs:
- `~/.claude/hooks/herdr-agent-state.sh` + a `SessionStart` entry in `~/.claude/settings.json`
- `~/.copilot/hooks/herdr-agent-state.sh` + a `SessionStart` entry in `~/.copilot/settings.json`
- `~/.hermes/profiles/trismegistus/plugins/herdr-agent-state/` + `herdr-agent-state`
  in that profile's `config.yaml` `plugins.enabled`

The `HERMES_HOME` line matters: without it Herdr targets `~/.hermes`, which is
the **default** profile, not trismegistus. Only install into the default profile
too if the user runs that profile inside Herdr. Ask; don't assume.

Check that `~/.claude/settings.json` is still valid and kept its keys:

```fish
jq '{model, theme, hooks: (.hooks | keys)}' ~/.claude/settings.json
```

**Expected:** `"model": "sonnet"`, `"theme": "dark"`, and `hooks` containing
`SessionStart`.

Restart Hermes afterwards (Herdr docs: the plugin loads at startup).

These files live outside the dotfiles repo and are **not** stowed. That's
intentional: `herdr integration install` owns and upgrades them, and stowing
`~/.claude/settings.json` would fight Claude Code's own writes.

---

### Task 17 — Install the Herdr agent skill (3 min)

The skill teaches an agent running *inside* a Herdr pane (`HERDR_ENV=1`) to split
panes, run commands in another pane, read output, and wait on other agents.

Claude Code + Copilot CLI via the skills CLI (verified 2026-10-05: the repo
exposes a skill named `herdr`, and `claude-code`/`github-copilot` are valid agent ids):

```fish
npx -y skills add herdrdev/herdr --skill herdr -g -a claude-code github-copilot -y
ls ~/.claude/skills/herdr/SKILL.md
```

**Expected:** install succeeds and `~/.claude/skills/herdr/SKILL.md` exists.

Hermes: do **not** use `-a hermes-agent`. It targets the default profile's
skills dir. Install into the active profile with `skill_manage`, creating
`autonomous-ai-agents/herdr` from the upstream file
`https://raw.githubusercontent.com/herdrdev/herdr/master/skills/herdr/SKILL.md`
(214 lines, verified) unchanged. Verify:

```fish
test -f ~/.hermes/profiles/trismegistus/skills/autonomous-ai-agents/herdr/SKILL.md; and echo ok
```

End-to-end: inside Herdr, start `claude` in a pane and ask
"run `echo hi` in a new Herdr pane to the right and tell me the output".
**Expected:** a new pane appears, and Claude reports `hi`.

---

## Tests / validation

There is no application code here, so classic RED-GREEN-REFACTOR does not apply.
The equivalent deterministic gates, each already embedded above:

| Gate | Command | Pass condition |
|---|---|---|
| TOML validity | `python3 -c "import tomllib;tomllib.load(open('…/herdr/.config/herdr/config.toml','rb'))"` | no traceback |
| Key names real | Task 6 loop against `herdr --default-config` | prints only `done` |
| Lua validity | `luac -p …/wezterm.lua` | exit 0 |
| No leader left in WezTerm | `grep -n "config.leader\|mods = 'LEADER'" …/wezterm.lua` | exit 1 |
| Stow is conflict-free | `stow --simulate --verbose …` | `LINK:` lines only |
| No broken repo symlinks | `find ~/.config -xtype l` | no line mentions dotflies/dotfiles |
| No stale path refs | `grep -rn dotflies … --exclude-dir=.git --exclude-dir=.hermes` | exit 1 |
| Herdr honors the config | `prefix+?` inside Herdr | help panel opens, shows custom binds |
| Integrations installed | `herdr integration status` | claude, copilot, hermes installed |
| Claude settings intact | `jq . ~/.claude/settings.json` | valid JSON, model/theme kept |
| Skill reachable | `ls ~/.claude/skills/herdr/SKILL.md` + Hermes path | both exist |

Run the gates **in task order**; a failing gate blocks the next task.

---

## Risks, tradeoffs, open questions

**Risks**

1. **Unstow/restow window.** Between Task 10a and 10d the machine has no dotfile
   symlinks. If something interrupts the sequence, `~/.config/fish`, `hypr`, etc.
   lose their links and the next Hyprland/fish start uses defaults. Mitigation:
   do 10a-10d in one sitting; nothing is deleted, `stow` from the new path
   restores everything. The repo itself is never at risk.
2. **`mv` fails if a shell/editor is cwd-inside the directory** — including the
   Herdr panes started in Task 8 and this very agent session, whose cwd is
   `/mnt/FILES/Projects/dotflies`. Expect to `cd /` or restart those first.
3. **Machine-local configs that are not in the repo** (`~/.config/hypr/config/`,
   `~/.config/hypr/noctalia.lua`, `~/.config/hypr/xdph.conf`,
   `~/.config/noctalia/colors.json`) must not be deleted during restow. The plan
   never deletes them; stow only removes links it owns.
4. **WezTerm's split was `\` (no shift).** It's mapped as `prefix+backslash`,
   not `prefix+|`. If Herdr rejects the name, keep only `"prefix+v"`:
   Task 6 + the Task 8 help panel will reveal this immediately.
5. **Other clones of the old repo name** still work through GitHub's redirect, but
   should run `git remote set-url origin …/dotfiles.git` too.
6. **Integration hooks edit agent configs outside the repo** (`~/.claude/settings.json`,
   `~/.copilot/settings.json`, Hermes `config.yaml`). Undo with
   `herdr integration uninstall <agent>`.
7. **Popup keys use `prefix+alt+…`.** Alt chords depend on the terminal. If
   WezTerm doesn't pass them through, the help panel still lists them but they
   won't fire. Fallback: rebind to `prefix+shift+g`/`prefix+shift+y`, but check
   `prefix+?` first, because `prefix+shift+g` is the default `new_worktree`.
8. **No `[theme]` block on purpose.** Herdr's default (`catppuccin`) is used.
   WezTerm runs Tokyo Night. If a matching built-in exists, it shows in
   settings (`prefix+s`) and can be added later as `[theme] name = "..."`. The
   plan doesn't guess an unverified theme name.
9. **`backslash` is not in the documented named-punctuation list** (docs name
   `minus`, `comma`, `ampersand`, `plus`, `backtick` "such as…"). If herdr rejects
   it, it falls back with a startup warning; `prefix+v` still splits. Task 8
   detects this.

**Tradeoffs**

- Demoting WezTerm's leader means WezTerm's own splits/tabs are gone. That is the
  point — two multiplexers fighting over one prefix is the actual problem — but it
  does mean WezTerm alone (outside Herdr) no longer has pane management.
- `prefix+w` = close tab (WezTerm muscle memory) costs Herdr's default workspace
  picker its home key; it moves to `prefix+a`, which is a new thing to learn.
- WezTerm's `<leader>/` search has no Herdr equivalent as a top-level binding;
  search lives inside copy mode (`prefix+[` then `/`). Accepted, not worked around.

**Decisions (user, 2026-10-05)**

1. GitHub repo already renamed: Task 11 only repoints `origin`.
2. Prefix = `CTRL+Space`; WezTerm leader retired (Task 9).
3. Herdr skill + integrations: yes (Tasks 16-17), plus agent-workflow popups,
   agent jumps and toast notifications in the config (Task 5).

**Remaining open question**

- Install the Hermes integration into the default `~/.hermes` profile as well, or
  only trismegistus? (Task 16 defaults to trismegistus only.)
