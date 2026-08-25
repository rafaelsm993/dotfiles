# Fresh WSL Arch Install — Step by Step

Complete walkthrough from a clean Windows machine to a working dev environment.

Steps 1–4 run in **Windows** (PowerShell). Steps 5 onward run **inside WSL**.

Total time: ~15–25 minutes, most of it package downloads.

---

## Step 1 — Install the Arch WSL distro (Windows)

Open **PowerShell as Administrator**:

```powershell
wsl --install -d archlinux
```

If `wsl` itself isn't installed yet:

```powershell
wsl --install
# reboot when prompted, then re-run the command above
```

Verify:

```powershell
wsl -l -v
```

Expected — `archlinux`, `Running`, `VERSION 2`:

```
  NAME         STATE      VERSION
* archlinux    Running    2
```

> If it shows `VERSION 1`, convert it: `wsl --set-version archlinux 2`

---

## Step 2 — Create your user (inside WSL, as root)

A fresh Arch WSL image drops you in as `root`. Enter the distro:

```powershell
wsl -d archlinux
```

Then, **as root**:

```bash
# Initialise the package keyring (required before the first install)
pacman-key --init
pacman-key --populate archlinux

# Refresh and install the essentials for user creation
pacman -Syu --noconfirm sudo

# Create your user (replace 'kanoah' with your username)
useradd -m -G wheel -s /bin/bash kanoah
passwd kanoah

# Grant the wheel group sudo
echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/wheel
chmod 0440 /etc/sudoers.d/wheel
```

Verify sudo works:

```bash
su - kanoah -c 'sudo -v && echo "sudo OK"'
```

Expected: password prompt, then `sudo OK`.

---

## Step 3 — Make your user the default (Windows)

Still as root inside WSL, create a minimal `/etc/wsl.conf` so you don't log in
as root next time. (The bootstrap script rewrites this file properly later.)

```bash
printf '[user]\ndefault=kanoah\n' > /etc/wsl.conf
```

Then, back in **PowerShell**:

```powershell
wsl --shutdown
wsl -d archlinux
```

Verify you land as your user:

```bash
whoami
```

Expected: `kanoah` (not `root`).

---

## Step 4 — Install a Nerd Font (Windows)

The prompt and FastFetch use glyphs that need a Nerd Font. Install one on the
**Windows** side (WSL has no fonts of its own):

```powershell
winget install --id DEVCOM.JetBrainsMonoNerdFont
```

Then set it as the font in your terminal (WezTerm / Windows Terminal).
Without this you'll see boxes and question marks instead of icons.

---

## Step 5 — Clone the dotfiles (inside WSL)

```bash
sudo pacman -Syu --needed --noconfirm git
mkdir -p ~/Code
git clone <your-repo-url> ~/Code/dotfiles
cd ~/Code/dotfiles
```

> Using SSH instead of HTTPS? Generate a key first:
> ```bash
> ssh-keygen -t ed25519 -C "you@example.com"
> cat ~/.ssh/id_ed25519.pub    # add this to GitHub → Settings → SSH keys
> ```

---

## Step 6 — Preview the bootstrap

**Always dry-run first.** This changes nothing:

```bash
./bootstrap.sh --dry-run
```

Read the output. Every line starting with `would run:` is an action that will be
taken. Expect roughly 29 packages to be reported as missing on a fresh box.

---

## Step 7 — Run the bootstrap

```bash
./bootstrap.sh
```

You'll be asked for your sudo password once, early on.

This takes 10–20 minutes — mostly downloading packages, the JDK, and Node.

Phases, in order:

| # | Phase | What happens |
|---|---|---|
| 1 | `packages` | installs ~29 pacman packages |
| 2 | `wslconf` | writes `/etc/wsl.conf` (rendered for *your* username) |
| 3 | `stow` | symlinks fish, nvim, fastfetch, mise configs |
| 4 | `mise` | installs Java (temurin-21) and Node 24 |
| 5 | `npm` | installs Salesforce CLI, prettier, prettier-plugin-apex |
| 6 | `omp` | installs oh-my-posh |
| 7 | `shell` | sets fish as your login shell |
| 8 | `git` | applies global git config |
| 9 | `verify` | checks everything landed |

Expected ending:

```
  ok all checks passed

==> Bootstrap complete.
```

> **If a phase fails**, the script keeps going and lists the failures at the end.
> Re-run just that phase after fixing, e.g. `./bootstrap.fish --only npm`.

---

## Step 8 — Restart WSL

`/etc/wsl.conf` changed, so a full restart is required for the `metadata`
automount option and your login shell to take effect.

In **PowerShell**:

```powershell
wsl --shutdown
```

Then reopen your terminal.

**This step is not optional.** Without it `/mnt/c` files stay mode `777` and the
Salesforce CLI will refuse to read its own credentials.

---

## Step 9 — Verify

Back inside WSL:

```bash
cd ~/Code/dotfiles
./bootstrap.fish --only verify
```

Expected: all `ok`, ending in `ok all checks passed`.

Confirm the shell and mount options changed:

```bash
echo $SHELL                          # /usr/bin/fish
mount | grep ' /mnt/c '              # must contain 'metadata'
```

---

## Step 10 — Personal setup (manual)

The bootstrap deliberately skips anything personal or interactive.

**Git identity:**

```bash
git config --global user.name  "Your Name"
git config --global user.email "you@example.com"
```

**Salesforce orgs** — auth must be done *inside WSL* (Windows auth is invisible here):

```bash
sf org login web --alias DEV
sf org login web --alias PREPROD
sf config set target-org PREPROD
sf org list                           # confirm 'Connected'
```

**Neovim plugins** — first launch installs everything via lazy.nvim:

```bash
nvim
# wait for lazy.nvim to finish, then:
:checkhealth
:Mason
```

---

## Troubleshooting

**`sf` says "No authenticated orgs found" / "secret-tool: The name is not activatable"**

First, **check which shell you're in.** `SF_USE_GENERIC_UNIX_KEYCHAIN` is exported
from `config.fish`, so any *bash* shell (scripts, CI, agent/tool terminals) will
show `No Orgs found` and `secret-tool` warnings even on a perfectly working setup:

```bash
fish -c 'sf org list'      # correct
sf org list                # misleading if the current shell is bash
```

If it also fails from fish, verify the export is present:

```bash
./bootstrap.fish --only verify | grep KEYCHAIN
```

Then open a **new** shell — the variable only applies to shells started after it
was set.

**`sf` says "Invalid file permissions for secret file"**

`/mnt/c` is missing the `metadata` mount option:

```bash
mount | grep ' /mnt/c '     # look for 'metadata'
cat /etc/wsl.conf           # check [automount] options
```

Fix and run `wsl --shutdown` from Windows.

Note: auth files under `/mnt/c` can *never* satisfy the CLI's permission check.
Keep them in the Linux home (`~/.sfdx`, mode `700`, files `600`).

**Stow reports a conflict**

The script backs up conflicting real files to `<path>.pre-stow.<timestamp>`.
Compare and delete once you're happy:

```bash
ls -d ~/.config/*.pre-stow.*
diff ~/.config/mise.pre-stow.*/config.toml ~/Code/dotfiles/mise/.config/mise/config.toml
```

**Boxes / question marks instead of icons**

The Nerd Font from Step 4 isn't installed, or isn't selected in your terminal.

**Login shell didn't change**

`chsh` only takes effect on next login. Run `wsl --shutdown` from Windows.

---

## Re-running later

The bootstrap is idempotent — safe to re-run any time to pick up new packages
after a `git pull`:

```bash
cd ~/Code/dotfiles && git pull && ./bootstrap.fish
```

A second run on an already-configured machine should be all `skip` and `ok`.
