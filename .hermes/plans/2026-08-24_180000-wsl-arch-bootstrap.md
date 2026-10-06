# WSL Arch Linux Bootstrap + Dotfiles Implementation Plan

> **For Hermes:** Execute task-by-task. Every task is 2-5 minutes. Verify each before moving on.

**Goal:** Turn a fresh root-only Arch WSL install into a usable dev box for user `kanoah`, with sudo, GNU Stow-managed dotfiles, Fish + oh-my-posh, and a fully working Neovim (kickstart + custom Salesforce plugins).

**Architecture:** Phase 1 runs as root (pacman bootstrap, user/group creation, sudo, `/etc/wsl.conf`). Phase 2 runs as `kanoah` (dotfiles clone/stow, mise runtimes, Neovim plugin sync, Salesforce toolchain). GUI packages (hypr, noctalia, wezterm) are deliberately skipped — the terminal lives on Windows.

**Tech Stack:** Arch Linux (WSL2, systemd enabled), pacman, GNU Stow, Fish, oh-my-posh, mise (Node 24, Java), Neovim 0.11+ / lazy.nvim / Mason, Salesforce `sf` CLI.

---

## Current Context / Findings

Verified on the live system:

- `/etc/os-release` → Arch Linux; kernel `6.6.87.2-microsoft-standard-WSL2`.
- `/etc/wsl.conf` currently contains only:
  ```ini
  [boot]
  systemd=true
  ```
  No `[user] default=` section → WSL logs in as root. This is the root cause of "only root, no sudo".
- `sudo` binary IS present (`/usr/sbin/sudo`); `git`, `fish`, `rg` present; `stow`, `nvim`, `mise`, `oh-my-posh`, `fd`, `java`, `lazygit`, `yazi` are NOT.
- `/home` is empty — user `kanoah` does not exist yet.
- 331 pacman packages installed; repos `[core]` + `[extra]` enabled (no multilib, no chaotic-aur — fine).
- Repo is currently at the Windows path `/mnt/c/Users/rafael.moraes/Code/dotflies` (note the typo "dotflies"). Working from `/mnt/c` inside WSL is **slow** (9p filesystem) and breaks symlink permissions — the plan clones a fresh copy into `~/Code/dotfiles` on the Linux ext4 filesystem, which is exactly what `.stowrc` already expects.
- `.stowrc`:
  ```
  --target=/home/kanoah
  --dir=/home/kanoah/Code/dotfiles
  ```
  Already correct **if** the user is named `kanoah` and the repo lives at `~/Code/dotfiles`. Plan keeps the username `kanoah` so `.stowrc` needs no edit.
- Stow packages present: `fastfetch`, `fish`, `hypr`, `noctalia`, `nvim`, `wezterm`. **Stow only `fish`, `nvim`, `fastfetch`.**
- `fish/config.fish` sources a CachyOS file that won't exist on Arch — the `else` branch handles it, so it works unmodified. It calls `mise activate fish` and `oh-my-posh init fish` (tokyo theme, fetched from a URL → needs network on every shell start; optionally vendor it locally, see Task 14).
- Neovim needs: `neovim >= 0.11`, `git`, `make`, `gcc` (telescope-fzf-native `build = 'make'`, LuaSnip `make install_jsregexp`), `ripgrep`, `fd`, `unzip`, `curl`, `wget`, `xclip`/`wl-clipboard`.
- Salesforce chain: `apex_ls` = Mason `apex-language-server`, a JAR requiring **Java** at `$JAVA_HOME/bin/java`; `prettier` via Node; `sf` CLI via npm; `ts_ls` and `stylua` via Mason.
- `copilot.lua` requires **Node 24 specifically** (`mise use --global node@24`).

**Assumptions:** Windows-side terminal is already installed and can attach to the WSL distro. Internet works. `pacman` mirrors are functional. Username = `kanoah` (change everywhere if not — including `.stowrc`).

---

## Proposed Approach

1. Bootstrap pacman keyring + full system update as root.
2. Create `kanoah`, add to `wheel`, enable wheel in sudoers, set password.
3. Set `[user] default=kanoah` in `/etc/wsl.conf`, plus `[interop]`/`[automount]` niceties. Shutdown WSL from Windows to apply.
4. As `kanoah`: install packages, clone dotfiles to `~/Code/dotfiles`, `stow fish nvim fastfetch`.
5. Install mise → Node 24 + Java 21 → oh-my-posh → `sf` CLI + prettier.
6. Run Neovim headless to sync lazy.nvim + Mason, then verify Salesforce LSP end-to-end on a real `.cls` file.

---

## Task List

### Phase 1 — Root system bootstrap

### Task 1: Refresh pacman keyring and update the system

**Objective:** Make pacman able to install anything (fresh WSL images often ship a stale keyring).

**Files:** none (system state)

**Step 1: Init and populate keyring**

```bash
pacman-key --init
pacman-key --populate archlinux
```

**Step 2: Full system upgrade**

```bash
pacman -Syu --noconfirm
```
Expected: completes with `there is nothing to do` or a list of upgrades. If it fails with `signature is unknown trust`, run `pacman -S --noconfirm archlinux-keyring` then retry.

**Step 3: Verify**

```bash
pacman -Q archlinux-keyring base
```
Expected: both print a version, exit 0.

---

### Task 2: Install the minimal root-level toolset

**Objective:** Get `sudo`, `stow`, editors and build tools available system-wide.

**Step 1: Install**

```bash
pacman -S --needed --noconfirm \
  base-devel git sudo stow which man-db \
  neovim fish stow \
  ripgrep fd fzf unzip zip curl wget tar \
  openssh less tree jq \
  wl-clipboard xclip \
  fastfetch lazygit yazi
```
Note: `base-devel` supplies `make`, `gcc`, `pkgconf` — required by telescope-fzf-native and LuaSnip.

**Step 2: Verify**

```bash
for b in sudo stow nvim fish rg fd make gcc git lazygit yazi fastfetch; do
  printf '%-10s %s\n' "$b" "$(command -v $b || echo MISSING)"
done
nvim --version | head -1
```
Expected: no `MISSING`; Neovim reports `v0.11.x` or newer. If Neovim is older than 0.11, `salesforce.lua` will error — stop and resolve before continuing.

---

### Task 3: Create the `kanoah` user and groups

**Objective:** Stop living as root; create the account `.stowrc` already points at.

**Step 1: Create user with fish as login shell**

```bash
useradd -m -G wheel -s /usr/bin/fish kanoah
```

**Step 2: Set the password (interactive)**

```bash
passwd kanoah
```
Expected: two prompts, then `password updated successfully`.

**Step 3: Verify**

```bash
id kanoah
getent passwd kanoah
ls -ld /home/kanoah
```
Expected: `uid=1000(kanoah) gid=1000(kanoah) groups=1000(kanoah),998(wheel)`; home owned by `kanoah:kanoah`.

---

### Task 4: Enable sudo for the wheel group

**Objective:** `sudo` works for `kanoah`.

**Files:**
- Create: `/etc/sudoers.d/10-wheel`

**Step 1: Write the drop-in (never edit `/etc/sudoers` directly)**

```bash
install -m 0440 /dev/stdin /etc/sudoers.d/10-wheel <<'EOF'
%wheel ALL=(ALL:ALL) ALL
EOF
```

**Step 2: Validate syntax before trusting it**

```bash
visudo -c -f /etc/sudoers.d/10-wheel
visudo -c
```
Expected: `/etc/sudoers.d/10-wheel: parsed OK` and `/etc/sudoers: parsed OK`.

**Step 3: Verify as the user**

```bash
su - kanoah -c 'sudo -l'
```
Expected: after entering the password, lists `(ALL : ALL) ALL`.

---

### Task 5: Configure `/etc/wsl.conf` so WSL logs in as `kanoah`

**Objective:** Default user is no longer root; sane WSL interop.

**Files:**
- Modify: `/etc/wsl.conf`

**Step 1: Back up and write the new config**

```bash
cp /etc/wsl.conf /etc/wsl.conf.bak
install -m 0644 /dev/stdin /etc/wsl.conf <<'EOF'
[boot]
systemd=true

[user]
default=kanoah

[automount]
enabled=true
options="metadata,umask=22,fmask=11"

[interop]
enabled=true
appendWindowsPath=true

[network]
generateResolvConf=true
EOF
```
`metadata` in automount is what allows real Linux permissions on `/mnt/c` — useful, but we still keep dotfiles on ext4.

**Step 2: Verify file contents**

```bash
cat /etc/wsl.conf
```

**Step 3: Apply — run from Windows PowerShell/CMD, not inside WSL**

```powershell
wsl --shutdown
```
Then reopen the WSL terminal.

**Step 4: Verify after restart**

```bash
whoami        # expect: kanoah
groups        # expect: kanoah wheel
echo $SHELL   # expect: /usr/bin/fish
sudo true     # expect: password prompt, then exit 0
```

**Everything below runs as `kanoah`, not root.**

---

### Phase 2 — Dotfiles

### Task 6: Clone the dotfiles repo to the ext4 path `.stowrc` expects

**Objective:** `~/Code/dotfiles` exists and matches `--dir` in `.stowrc`.

**Files:**
- Create: `/home/kanoah/Code/dotfiles/` (git clone)

**Step 1: Clone**

```bash
mkdir -p ~/Code
git clone https://github.com/kanoah/dotfiles.git ~/Code/dotfiles
```
If the remote URL differs, get it from the Windows copy:
```bash
git -C /mnt/c/Users/rafael.moraes/Code/dotflies remote get-url origin
```
Fallback if the repo is private / no network auth yet — copy the working tree instead:
```bash
mkdir -p ~/Code/dotfiles
cp -a /mnt/c/Users/rafael.moraes/Code/dotflies/. ~/Code/dotfiles/
```

**Step 2: Strip CRLF line endings (the Windows copy has them)**

```bash
cd ~/Code/dotfiles
git config core.autocrlf input
grep -rlIU $'\r' --exclude-dir=.git . | xargs -r sed -i 's/\r$//'
```
CRLF in `config.fish` causes cryptic fish parse errors — do not skip this.

**Step 3: Verify**

```bash
cat ~/Code/dotfiles/.stowrc
ls ~/Code/dotfiles
file ~/Code/dotfiles/fish/.config/fish/config.fish
```
Expected: `.stowrc` targets `/home/kanoah` and dir `/home/kanoah/Code/dotfiles`; `file` reports ASCII text **without** "CRLF".

---

### Task 7: Clear conflicts and dry-run stow

**Objective:** Prove stow will not clobber anything before it does.

**Step 1: Move aside any pre-existing configs**

```bash
mkdir -p ~/.config-backup
for p in fish nvim fastfetch; do
  [ -e ~/.config/$p ] && [ ! -L ~/.config/$p ] && mv ~/.config/$p ~/.config-backup/$p
done
mkdir -p ~/.config
```

**Step 2: Dry run**

```bash
cd ~/Code/dotfiles
stow -n -v fish nvim fastfetch
```
Expected: only `LINK:` lines. Any `existing target is neither a link nor a directory` → resolve that path first, re-run.

---

### Task 8: Stow fish, nvim, fastfetch (GUI packages intentionally skipped)

**Objective:** Symlinks live in `~/.config`.

**Step 1: Stow**

```bash
cd ~/Code/dotfiles
stow -v fish nvim fastfetch
```
Do **not** stow `hypr`, `noctalia`, or `wezterm` — Hyprland/Noctalia are a Wayland desktop and WezTerm runs on Windows with its own config.

**Step 2: Verify the links resolve into the repo**

```bash
ls -l ~/.config/fish ~/.config/nvim ~/.config/fastfetch
readlink -f ~/.config/nvim/init.lua
```
Expected: each is a symlink into `~/Code/dotfiles/...`.

**Step 3: Commit nothing** — stow makes no repo changes; `git -C ~/Code/dotfiles status` should be clean apart from the CRLF normalization from Task 6. Commit that if desired:
```bash
git -C ~/Code/dotfiles add -A && git -C ~/Code/dotfiles commit -m "chore: normalize line endings to LF"
```

---

### Phase 3 — Shell and runtimes

### Task 9: Install mise and set global runtimes

**Objective:** `mise activate fish` in `config.fish` has something to activate; Node 24 (Copilot constraint) and Java (Apex LSP) available.

**Step 1: Install mise**

```bash
sudo pacman -S --needed --noconfirm mise
```
(If not in `[extra]` on this mirror: `curl https://mise.run | sh` → installs to `~/.local/bin/mise`.)

**Step 2: Pin runtimes**

```bash
mise use --global node@24
mise use --global java@temurin-21
mise install
```

**Step 3: Verify**

```bash
mise ls
~/.local/share/mise/shims/node --version   # expect v24.x
mise exec -- java -version                 # expect openjdk 21
```
Node **must** be 24 — `copilot.lua` documents that 26 breaks it.

**Step 4: Export JAVA_HOME for the Apex LSP**

`salesforce.lua` uses `$JAVA_HOME/bin/java` falling back to `java`. Add a fish conf.d drop-in **in the repo** (so it's tracked), then it's live via the existing symlink:

- Create: `~/Code/dotfiles/fish/.config/fish/conf.d/java.fish`
```fish
# JAVA_HOME for the Salesforce apex-language-server (Mason JAR)
if command -q mise
    set -gx JAVA_HOME (mise where java 2>/dev/null)
end
```

**Step 5: Verify**

```bash
fish -c 'echo $JAVA_HOME; test -x $JAVA_HOME/bin/java; and echo JAVA_OK'
```
Expected: a path plus `JAVA_OK`.

**Step 6: Commit**

```bash
cd ~/Code/dotfiles
git add fish/.config/fish/conf.d/java.fish
git commit -m "feat(fish): export JAVA_HOME from mise for apex_ls"
```

---

### Task 10: Install oh-my-posh

**Objective:** `config.fish` line 16 stops erroring.

**Step 1: Install**

```bash
sudo pacman -S --needed --noconfirm oh-my-posh
```
Fallback if absent from repos:
```bash
curl -s https://ohmyposh.dev/install.sh | bash -s -- -d ~/.local/bin
```

**Step 2: Verify**

```bash
oh-my-posh --version
```

---

### Task 11: Make fish the working login shell

**Objective:** New shells start clean with no errors.

**Step 1: Confirm the shell is registered and set**

```bash
grep -q /usr/bin/fish /etc/shells || echo /usr/bin/fish | sudo tee -a /etc/shells
chsh -s /usr/bin/fish
```

**Step 2: Start a fresh fish and read the output carefully**

```bash
exec fish -l
```
Expected: prompt renders with the oh-my-posh **tokyo** theme, no red error text.
- `mise: command not found` → Task 9 failed.
- `oh-my-posh: command not found` → Task 10 failed.
- Long startup delay → the theme is fetched over HTTP each launch; see Task 14.

**Step 3: Verify PATH additions from the `else` branch**

```bash
fish -c 'echo $PATH | tr " " "\n" | grep -E "local/bin|/bin$"'
```

---

### Phase 4 — Neovim

### Task 12: First Neovim sync (lazy.nvim + Mason)

**Objective:** All plugins installed and compiled, headless, with real output to read.

**Step 1: Headless plugin install**

```bash
nvim --headless "+Lazy! sync" +qa
```
Expected: lazy clones every plugin; telescope-fzf-native runs `make`; LuaSnip runs `make install_jsregexp`. Failures here mean `base-devel` is missing (Task 2).

**Step 2: Let Mason install the servers**

```bash
nvim --headless "+MasonToolsInstall" "+sleep 90" +qa
```
Expected tools: `ts_ls`, `lua_ls`, `stylua`, `apex-language-server`.

**Step 3: Verify from inside Neovim**

```bash
nvim
```
Then run, in order:
- `:Lazy` — every plugin shows installed, no errors. `q` to close.
- `:Mason` — `lua_ls`, `ts_ls`, `stylua`, `apex-language-server` all marked installed.
- `:checkhealth` — no ERROR entries. Warnings about optional providers (perl/ruby/python) are fine; `tree-sitter CLI not found` is fine unless you build parsers from grammar.
- `:TSUpdate` then `:TSInstall apex lua javascript typescript html css xml json` — needed for `salesforce.lua`'s explicit `vim.treesitter.start(buf, 'apex')` and for the custom fold queries in `queries/apex/folds.scm`.

**Step 4: Verify the apex parser specifically**

```bash
nvim --headless -c 'lua print(vim.treesitter.language.add("apex") and "APEX_PARSER_OK" or "MISSING")' -c qa
```
Expected: `APEX_PARSER_OK`.

---

### Task 13: Salesforce toolchain — `sf` CLI + prettier

**Objective:** `salesforce_sf.lua` keymaps and `salesforce.lua` formatting actually work.

**Step 1: Install the CLIs via the mise-managed Node 24**

```bash
npm install -g @salesforce/cli prettier prettier-plugin-apex
```

**Step 2: Verify**

```bash
sf --version
prettier --version
```
Expected: `@salesforce/cli/2.x` and a prettier 3.x version.

**Step 3: End-to-end Apex LSP smoke test**

```bash
mkdir -p /tmp/sfsmoke/force-app/main/default/classes
cd /tmp/sfsmoke
printf '{"packageDirectories":[{"path":"force-app","default":true}],"sourceApiVersion":"61.0"}\n' > sfdx-project.json
cat > force-app/main/default/classes/Smoke.cls <<'EOF'
public with sharing class Smoke {
    public static String hello() {
        return 'world';
    }
}
EOF
nvim force-app/main/default/classes/Smoke.cls
```
Inside Neovim verify all four:
1. `:echo &filetype` → `apex` (filetype detection from `salesforce.lua`).
2. `:LspInfo` → `apex_ls` attached. If it says "no client", check `:messages` and confirm the JAR exists:
   `ls ~/.local/share/nvim/mason/share/apex-language-server/apex-jorje-lsp.jar`
3. `zc` on the method → folds using the custom `apex_foldtext` (syntax-highlighted fold line, no fold background).
4. `<leader>Fo` → the Salesforce org picker opens (proves `sf` is on PATH and the sfdx-project guard passed).

**Step 4: Authorize an org (interactive, optional now)**

```bash
sf org login web --alias dev --set-default
```
On WSL this opens the Windows default browser via interop — requires `[interop] enabled=true` from Task 5. If the browser doesn't open, use `sf org login device`.

**Step 5: Clean up**

```bash
rm -rf /tmp/sfsmoke
```

---

### Phase 5 — Polish

### Task 14: (Optional) Vendor the oh-my-posh theme locally

**Objective:** Kill the per-shell-launch HTTP fetch in `config.fish:16`.

**Files:**
- Create: `~/Code/dotfiles/fish/.config/fish/tokyo.omp.json`
- Modify: `~/Code/dotfiles/fish/.config/fish/config.fish:16`

**Step 1: Download the theme**

```bash
curl -fsSL https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/refs/heads/main/themes/tokyo.omp.json \
  -o ~/Code/dotfiles/fish/.config/fish/tokyo.omp.json
```

**Step 2: Point config.fish at the local copy**

Replace line 16 with:
```fish
oh-my-posh init fish --config "$__fish_config_dir/tokyo.omp.json" | source
```

**Step 3: Verify**

```bash
time fish -c 'true'
```
Expected: noticeably under the previous timing; prompt still renders identically in a new shell.

**Step 4: Commit**

```bash
cd ~/Code/dotfiles
git add fish/.config/fish/tokyo.omp.json fish/.config/fish/config.fish
git commit -m "perf(fish): vendor oh-my-posh tokyo theme instead of fetching over HTTP"
```

---

### Task 15: Fix the fastfetch Windows logo path

**Objective:** `fastfetch` stops erroring on a `C:/...` path.

**Files:**
- Modify: `~/Code/dotfiles/fastfetch/.config/fastfetch/config.jsonc`

**Step 1: Inspect and repoint the logo source**

Change the hardcoded `C:/Users/kanoah/.config/fastfetch/ascii.txt` to:
```
~/.config/fastfetch/ascii.txt
```

**Step 2: Verify**

```bash
fastfetch
```
Expected: renders the ASCII logo, no "failed to load logo" warning.

**Step 3: Commit**

```bash
cd ~/Code/dotfiles
git add fastfetch/.config/fastfetch/config.jsonc
git commit -m "fix(fastfetch): use Linux path for the ASCII logo"
```

---

### Task 16: Git identity + SSH key

**Objective:** Commits are attributable; GitHub push works.

**Step 1: Identity**

```bash
git config --global user.name  "kanoah"
git config --global user.email "YOUR_EMAIL_HERE"
git config --global init.defaultBranch main
git config --global core.autocrlf input
```

**Step 2: SSH key**

```bash
ssh-keygen -t ed25519 -C "kanoah@wsl-arch" -f ~/.ssh/id_ed25519
cat ~/.ssh/id_ed25519.pub
```
Add the printed key at https://github.com/settings/keys.

**Step 3: Verify**

```bash
ssh -T git@github.com
```
Expected: `Hi kanoah! You've successfully authenticated...`

---

### Task 17: Final acceptance check

**Objective:** One command proves the whole box.

**Step 1: Run**

```bash
echo "user:   $(whoami)  groups: $(groups)"
sudo -n true 2>/dev/null && echo "sudo:   nopasswd" || echo "sudo:   password-gated (ok)"
for b in nvim fish stow mise oh-my-posh node java sf prettier rg fd lazygit yazi fastfetch; do
  printf '%-12s %s\n' "$b" "$(command -v $b || echo MISSING)"
done
node --version; java -version 2>&1 | head -1
ls -l ~/.config/fish ~/.config/nvim ~/.config/fastfetch | sed 's/^/link: /'
nvim --headless "+Lazy! check" +qa 2>&1 | tail -5
```

**Expected:** user `kanoah` in `wheel`; zero `MISSING`; Node `v24.x`; Java 21; all three configs are symlinks into `~/Code/dotfiles`; Lazy reports no problems.

---

## Files Likely to Change

| Path | Action |
|---|---|
| `/etc/wsl.conf` | modify — add `[user] default=kanoah`, automount metadata, interop |
| `/etc/sudoers.d/10-wheel` | create — `%wheel ALL=(ALL:ALL) ALL` |
| `/etc/shells` | modify — ensure `/usr/bin/fish` listed |
| `/home/kanoah/` | create — user home |
| `~/Code/dotfiles/` | create — clone of this repo (ext4) |
| `~/.config/{fish,nvim,fastfetch}` | create — stow symlinks |
| `fish/.config/fish/conf.d/java.fish` | create (repo) — `JAVA_HOME` export |
| `fish/.config/fish/config.fish:16` | modify (repo, optional) — local theme |
| `fish/.config/fish/tokyo.omp.json` | create (repo, optional) |
| `fastfetch/.config/fastfetch/config.jsonc` | modify (repo) — Linux logo path |
| all tracked text files | modify (repo) — CRLF → LF normalization |

**Explicitly NOT stowed:** `hypr/`, `noctalia/`, `wezterm/`.

---

## Tests / Validation

| What | Command | Expected |
|---|---|---|
| Default user | `whoami` after `wsl --shutdown` | `kanoah` |
| sudo | `sudo -l` | `(ALL : ALL) ALL` |
| sudoers syntax | `visudo -c` | `parsed OK` |
| Stow links | `readlink -f ~/.config/nvim/init.lua` | under `~/Code/dotfiles` |
| Fish startup | `exec fish -l` | themed prompt, no errors |
| Neovim plugins | `:Lazy` / `nvim --headless "+Lazy! check" +qa` | no errors |
| Neovim health | `:checkhealth` | no ERROR |
| Apex parser | headless `treesitter.language.add("apex")` | `APEX_PARSER_OK` |
| Apex LSP | `:LspInfo` on a `.cls` | `apex_ls` attached |
| Apex folding | `zc` in a `.cls` | custom highlighted fold text |
| sf keymaps | `<leader>Fo` inside an sfdx-project | org picker opens |
| Node pin | `node --version` | `v24.x` |
| Java | `echo $JAVA_HOME && java -version` | temurin 21 |

---

## Risks, Tradeoffs, Open Questions

**Risks**
1. **`wsl --shutdown` must run from Windows.** Running it inside WSL does nothing. If `whoami` still returns root after reopening, the distro didn't fully stop — close every WSL terminal (and VS Code / Hermes sessions attached to it) and retry.
2. **Locking yourself out of sudo.** Always validate with `visudo -c` before closing the root session (Task 4 Step 2). Keep one root shell open until `su - kanoah -c 'sudo -l'` succeeds.
3. **CRLF line endings** from the `/mnt/c` copy silently break fish and shell scripts. Task 6 Step 2 is mandatory.
4. **Neovim < 0.11** makes `salesforce.lua` fail on `vim.lsp.config()`. Gate on Task 2 Step 2.
5. **Apex LSP is a Java JAR** and needs ~1GB RAM plus a warm-up on first attach. On a memory-capped `.wslconfig`, it may be OOM-killed — bump `memory=8GB` in `C:\Users\<you>\.wslconfig` if `apex_ls` keeps dying.
6. **Node version drift.** A later `mise use --global node@latest` will silently break Copilot. Pin stays at 24.
7. **Repo directory name typo** — the Windows checkout is `dotflies`, the plan clones to `dotfiles` because that is what `.stowrc` requires. Don't "fix" `.stowrc` to match the typo.

**Tradeoffs**
- Cloning into ext4 rather than symlinking `/mnt/c` — costs a second checkout, buys correct permissions and ~10x file I/O for Neovim/lazy.
- Fish set as the login shell via `useradd -s`; if anything breaks catastrophically, recover with `wsl -d <distro> -u root`.
- Java installed via mise, not pacman `jdk-openjdk` — keeps the version pinnable per-project, at the cost of `JAVA_HOME` needing the conf.d drop-in.

**Open questions**
1. Confirm the username should be `kanoah` (matching `.stowrc`) rather than `rafael.moraes`.
2. Is the dotfiles repo public? If not, Task 6 needs SSH set up first (Task 16 moves before Task 6).
3. Should `hypr`/`noctalia`/`wezterm` be pruned from the repo, or kept for a future native Linux machine? Plan assumes kept-but-unstowed.
4. Any org-specific Salesforce setup — sandbox aliases, a `jsconfig.json` template for LWC (referenced in copilot-instructions as `tramontina-sf/jsconfig.json`)?
